import 'dart:convert';

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
}
