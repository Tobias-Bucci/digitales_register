import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dr/account_scope.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  test('removing a saved account also removes its local data', () async {
    const user = 'removed-user';
    const url = 'https://removed.digitalesregister.it';
    final accountStorageKey = getStorageKey(user, '$url/v2/api/auth/login');
    await secureStorage.write(
      key: 'login',
      value: jsonEncode({
        'user': 'active-user',
        'pass': 'active-password',
        'url': 'https://active.digitalesregister.it',
        'otherAccounts': [
          {'user': user, 'pass': 'removed-password', 'url': url},
          {
            'user': 'kept-user',
            'pass': 'kept-password',
            'url': 'https://kept.digitalesregister.it',
          },
        ],
      }),
    );
    await secureStorage.write(
      key: escapeKey(accountStorageKey),
      value: 'account-state',
    );
    final prefs = await SharedPreferences.getInstance();
    for (final namespace in <String>[
      'classRegisterLessons',
      'courseMaterials',
      'homeworkSummary',
      'gradeDeadlineOverrides',
    ]) {
      await prefs.setString('$namespace:$accountStorageKey', 'cached-data');
    }

    final store = createStore(
      initialState: AppState(),
      withMiddleware: true,
    );
    await store.actions.loginActions.removeAccount(0);

    expect(
      await secureStorage.read(key: escapeKey(accountStorageKey)),
      isNull,
    );
    for (final namespace in <String>[
      'classRegisterLessons',
      'courseMaterials',
      'homeworkSummary',
      'gradeDeadlineOverrides',
    ]) {
      expect(prefs.getString('$namespace:$accountStorageKey'), isNull);
    }
    final login = jsonDecode((await secureStorage.read(key: 'login'))!) as Map;
    expect((login['otherAccounts'] as List).single['user'], 'kept-user');
    expect(store.state.loginState.otherAccounts, <String>['kept-user']);
  });

  test('removing an account deletes its downloads and nothing of another',
      () async {
    const user = 'removed-user';
    const url = 'https://removed.digitalesregister.it';
    final base = await Directory.systemTemp.createTemp('removal-downloads-');
    addTearDown(() async {
      attachmentDownloadDirectoryOverride = null;
      await base.delete(recursive: true);
    });
    attachmentDownloadDirectoryOverride = () async => base.path;
    await secureStorage.write(
      key: 'login',
      value: jsonEncode({
        'user': 'active-user',
        'pass': 'active-password',
        'url': 'https://active.digitalesregister.it',
        'otherAccounts': [
          {'user': user, 'pass': 'removed-password', 'url': url},
          {
            'user': 'kept-user',
            'pass': 'kept-password',
            'url': 'https://kept.digitalesregister.it',
          },
        ],
      }),
    );
    final removed = AccountScope(url, user);
    final kept = AccountScope('https://kept.digitalesregister.it', 'kept-user');
    final files = <String, File>{
      'removed': File('${base.path}/${removed.fileId}/course_1_a.pdf'),
      'removed nested': File('${base.path}/${removed.fileId}/x/msg_1_b.pdf'),
      'kept': File('${base.path}/${kept.fileId}/course_1_a.pdf'),
      // Saved before accounts had folders: belongs to no account.
      'legacy': File('${base.path}/course_1_a.pdf'),
    };
    for (final file in files.values) {
      file.createSync(recursive: true);
      file.writeAsStringSync('content');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('courseMaterialFileVersions:${removed.fileId}', '{}');
    await prefs.setString('courseMaterialFileVersions:${kept.fileId}', '{}');
    await prefs.setString('courseMaterialFileVersions', '{}');

    final store = createStore(initialState: AppState(), withMiddleware: true);
    await store.actions.loginActions.removeAccount(0);

    expect(Directory('${base.path}/${removed.fileId}').existsSync(), isFalse);
    expect(files['kept']!.existsSync(), isTrue);
    expect(files['legacy']!.existsSync(), isTrue);
    expect(prefs.getString('courseMaterialFileVersions:${removed.fileId}'),
        isNull);
    expect(prefs.getString('courseMaterialFileVersions:${kept.fileId}'),
        isNotNull);
    expect(prefs.getString('courseMaterialFileVersions'), isNotNull);
  });

  test('removing the active account clears its local state and credentials',
      () async {
    const user = 'active-user';
    const url = 'https://active.digitalesregister.it';
    final accountStorageKey = getStorageKey(user, '$url/v2/api/auth/login');
    await secureStorage.write(
      key: 'login',
      value: jsonEncode({
        'user': user,
        'pass': 'active-password',
        'url': url,
      }),
    );
    await secureStorage.write(
      key: escapeKey(accountStorageKey),
      value: 'account-state',
    );

    final store = createStore(initialState: AppState(), withMiddleware: true);
    await store.actions.loginActions.removeCurrentAccount();

    expect(
      await secureStorage.read(key: escapeKey(accountStorageKey)),
      isNull,
    );
    expect(await secureStorage.read(key: 'login'), isNull);
    expect(store.state.loginState.loggedIn, isFalse);
  });

  test(
      'a slow write that was already running cannot bring a removed account back',
      () async {
    const user = 'active-user';
    const url = 'https://active.digitalesregister.it';
    const loginAddress = '$url/v2/api/auth/login';
    final accountStorageKey = getStorageKey(user, loginAddress);
    await secureStorage.write(
      key: 'login',
      value: jsonEncode({'user': user, 'pass': 'active-password', 'url': url}),
    );
    final store = createStore(initialState: AppState(), withMiddleware: true);
    final release = Completer<void>();
    final write = statePersistenceService.flush(
      state: AppState((b) => b.loginState
        ..loggedIn = true
        ..username = user),
      deletedData: false,
      server: loginAddress,
      writer: (key, value) async {
        await release.future;
        await secureStorage.write(key: escapeKey(key), value: value);
      },
      keyFactory: getStorageKey,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final removal = store.actions.loginActions.removeCurrentAccount();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    release.complete();
    await Future.wait([write, removal]);

    expect(
      await secureStorage.read(key: escapeKey(accountStorageKey)),
      isNull,
    );
  });
}
