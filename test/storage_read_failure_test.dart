import 'dart:convert';
import 'package:built_redux/built_redux.dart';
import 'package:flutter/services.dart';

import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show secureStorage;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

/// Secure storage whose reads and writes can fail like an unavailable
/// keystore or keyring.
class _FlakyStorage extends TestSecureStorage {
  _FlakyStorage({super.storage});

  /// Keys whose reads fail; `null` fails every read.
  Set<String>? failingReads = {};
  int remainingReadFailures = 1 << 30;
  bool failWrites = false;
  int deleteAllCalls = 0;
  int reads = 0;
  final writtenKeys = <String>[];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    reads++;
    final failing = failingReads;
    if ((failing == null || failing.contains(key)) &&
        remainingReadFailures > 0) {
      remainingReadFailures--;
      throw PlatformException(code: 'synthetic', message: 'keystore busy');
    }
    return super.read(key: key);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (failWrites) {
      throw PlatformException(code: 'synthetic', message: 'write failed');
    }
    writtenKeys.add(key);
    return super.write(key: key, value: value);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    deleteAllCalls++;
    return super.deleteAll();
  }
}

final _accountKey = escapeKey(getStorageKey('account_a', testLoginAddress));
const _loginEntry = '{"user":"account_a","pass":"synthetic-password"}';
const _unrelated = 'synthetic unrelated account data';

String _savedState(String fullName) => jsonEncode(serializers.serialize(
      AppState((b) => b
        ..gradesState.subjects.add(Subject((s) => s
          ..id = 1
          ..name = fullName))),
    ));

void main() {
  late _FlakyStorage storage;
  late String original;

  setUp(() async {
    final session = MockWrapper();
    when(() => session.loginAddress).thenReturn(testLoginAddress);
    when(() => session.baseAddress).thenReturn('$testServerUrl/v2/');
    when(() => session.user).thenReturn('account_a');
    when(() => session.url).thenReturn(testServerUrl);
    when(() => session.demoMode).thenReturn(false);
    when(() => session.noInternet).thenReturn(false);
    when(() => session.ensureLoggedIn()).thenAnswer((_) async => true);
    await bootstrapTestEnvironment(wrapperOverride: session);
    storageReadRetryDelay = Duration.zero;
    original = _savedState('Synthetic saved subject');
    storage = _FlakyStorage(storage: {
      'login': _loginEntry,
      _accountKey: original,
      'unrelated_account': _unrelated,
    });
    secureStorage = storage;
  });
  tearDown(resetTestState);

  Future<Store<AppState, AppStateBuilder, AppActions>> logIn() async {
    final store = createStore(withMiddleware: true);
    await store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
      ..username = 'account_a'
      ..fromStorage = true
      ..offlineOnly = true));
    return store;
  }

  List<String> subjects(Store<AppState, AppStateBuilder, AppActions> store) =>
      store.state.gradesState.subjects.map((s) => s.name).toList();

  test('B06 a read error for one account deletes nothing', () async {
    storage.failingReads = {_accountKey};
    await logIn();

    expect(storage.deleteAllCalls, 0);
    expect(storage.storage, {
      'login': _loginEntry,
      _accountKey: original,
      'unrelated_account': _unrelated,
    });
  });

  test('an unavailable keystore keeps every entry', () async {
    storage.failingReads = null;
    final store = await logIn();

    expect(storage.deleteAllCalls, 0);
    expect(storage.storage, hasLength(3));
    expect(store.state.loginState.loggedIn, isTrue);
  });

  test('a transient read error is retried and loads the saved state', () async {
    storage
      ..failingReads = {_accountKey}
      ..remainingReadFailures = 1;
    final store = await logIn();

    expect(subjects(store), ['Synthetic saved subject']);
    expect(storage.storage[_accountKey], original);
  });

  test('an unreadable entry is not overwritten by the new session', () async {
    storage.failingReads = {_accountKey};
    final store = await logIn();
    await store.actions.saveState();

    expect(storage.writtenKeys, isNot(contains(_accountKey)));
    expect(storage.storage[_accountKey], original);
    expect(storage.deleteAllCalls, 0);
  });

  test('a later successful read lets the account be saved again', () async {
    storage.failingReads = {_accountKey};
    final failed = await logIn();
    await failed.actions.saveState();
    expect(storage.writtenKeys, isNot(contains(_accountKey)));

    // The keystore is reachable again, e.g. on the next start.
    storage.failingReads = {};
    final store = await logIn();
    expect(subjects(store), ['Synthetic saved subject']);
    await store.actions.saveState();
    expect(storage.writtenKeys, contains(_accountKey));
    expect(storage.storage['unrelated_account'], _unrelated);
  });

  test('deleting the data still replaces an unreadable entry', () async {
    storage.failingReads = {_accountKey};
    final store = await logIn();
    await store.actions.deleteData();
    await store.actions.saveState();

    final saved = serializers
        .deserialize(jsonDecode(storage.storage[_accountKey]!) as Object);
    expect(saved, isA<SettingsState>());
    expect(storage.storage['login'], _loginEntry);
  });

  test('a damaged account entry only replaces that entry', () async {
    storage.storage[_accountKey] = '{"damaged';
    final store = await logIn();
    expect(subjects(store), isEmpty);
    expect(storage.storage['login'], _loginEntry);
    expect(storage.storage['unrelated_account'], _unrelated);

    await store.actions.saveState();
    expect(
        serializers
            .deserialize(jsonDecode(storage.storage[_accountKey]!) as Object),
        isA<AppState>());
    expect(storage.storage['login'], _loginEntry);
    expect(storage.storage['unrelated_account'], _unrelated);
    expect(storage.deleteAllCalls, 0);
  });

  test('a write error deletes nothing and leaves reads working', () async {
    final store = await logIn();
    storage.failWrites = true;
    await expectLater(store.actions.saveState(), throwsA(anything));

    expect(storage.deleteAllCalls, 0);
    expect(storage.storage, {
      'login': _loginEntry,
      _accountKey: original,
      'unrelated_account': _unrelated,
    });
    storage.failWrites = false;
    expect(subjects(await logIn()), ['Synthetic saved subject']);
  });

  testWidgets('the user is told that the saved data was kept', (tester) async {
    storage.failingReads = {_accountKey};
    final store = createStore(
      initialState: AppState((b) => b..settingsState.languageCode = 'en'),
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: const Scaffold());
    await tester.runAsync(
      () => store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
        ..username = 'account_a'
        ..fromStorage = true
        ..offlineOnly = true)),
    );
    await tester.pump();
    expect(
      find.text('The saved data of this account could not be read right '
          'now. It is kept and will be loaded again on the next start. '
          'Until then, changes for this account are not saved.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
