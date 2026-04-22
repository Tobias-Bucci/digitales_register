import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiver/testing/src/async/fake_async.dart';

import 'support/test_harness.dart';

void main() {
  late MockWrapper mockWrapper;
  late TestSecureStorage storage;

  setUp(() async {
    mockWrapper = MockWrapper();
    when(() => mockWrapper.loginAddress).thenReturn(testLoginAddress);
    await bootstrapTestEnvironment(wrapperOverride: mockWrapper);
    storage = secureStorage as TestSecureStorage;
  });

  tearDown(() {
    resetTestState();
  });

  test('save state occurs after the debounce interval', () {
    FakeAsync().run((async) async {
      final store = _createLoggedInStore(username: 'debounce-user');

      await store.actions.setUrl('https://example.com');
      async.elapse(const Duration(seconds: 4));

      expect(await storedPayload(storage, 'debounce-user'), isNull);

      async.elapse(const Duration(seconds: 2));
      expect(await storedPayload(storage, 'debounce-user'), isNotNull);
    });
  });

  test('saveState persists immediately', () async {
    final store = _createLoggedInStore(username: 'immediate-user');

    await store.actions.saveState();

    final payload = await storedPayload(storage, 'immediate-user');
    expect(payload, isNotNull);
    expect(serializers.deserialize(json.decode(payload!) as Object),
        isA<AppState>());
  });

  test('subject nicks persist immediately after changes', () async {
    final store = _createLoggedInStore(username: 'subject-nicks-user');

    await store.actions.settingsActions.subjectNicks(
      BuiltMap<String, String>({
        ...defaultSubjectNicks,
        'Mathematik': 'M',
        'Geschichte': 'Ge',
      }),
    );

    final payload = await storedPayload(storage, 'subject-nicks-user');
    expect(payload, isNotNull);

    final deserialized =
        serializers.deserialize(json.decode(payload!) as Object) as AppState;
    expect(deserialized.settingsState.subjectNicks['Mathematik'], 'M');
    expect(deserialized.settingsState.subjectNicks['Geschichte'], 'Ge');
  });

  test('calendar substitute helper visibility persists immediately', () async {
    final store = _createLoggedInStore(username: 'calendar-substitute-user');

    await store.actions.settingsActions.showCalendarSubstituteBar(false);

    final payload = await storedPayload(storage, 'calendar-substitute-user');
    expect(payload, isNotNull);

    final deserialized =
        serializers.deserialize(json.decode(payload!) as Object) as AppState;
    expect(deserialized.settingsState.showCalendarSubstituteBar, isFalse);
  });

  test('noDataSaving stores only settings state', () async {
    final store = _createLoggedInStore(
      username: 'settings-only-user',
      state: AppState(
        (b) {
          b.loginState
            ..loggedIn = true
            ..username = 'settings-only-user';
          b.settingsState.noDataSaving = true;
        },
      ),
    );

    await store.actions.saveState();

    final payload = await storedPayload(storage, 'settings-only-user');
    expect(payload, isNotNull);
    expect(
      serializers.deserialize(json.decode(payload!) as Object),
      isA<SettingsState>(),
    );
  });

  test('deleteData saves a settings-only snapshot', () async {
    final store = _createLoggedInStore(username: 'delete-user');

    await store.actions.deleteData();

    final payload = await storedPayload(storage, 'delete-user');
    expect(payload, isNotNull);
    expect(
      serializers.deserialize(json.decode(payload!) as Object),
      isA<SettingsState>(),
    );
  });

  test(
      'logout with deleteDataOnLogout replaces persisted app state with settings',
      () async {
    final store = _createLoggedInStore(
      username: 'logout-user',
      state: AppState(
        (b) {
          b.loginState
            ..loggedIn = true
            ..username = 'logout-user';
          b.settingsState.deleteDataOnLogout = true;
        },
      ),
    );

    await store.actions.saveState();
    expect(
      serializers.deserialize(
        json.decode((await storedPayload(storage, 'logout-user'))!) as Object,
      ),
      isA<AppState>(),
    );

    await store.actions.loginActions.logout(
      LogoutPayload(
        (b) => b
          ..hard = true
          ..forced = true,
      ),
    );

    final payload = await storedPayload(storage, 'logout-user');
    expect(payload, isNotNull);
    expect(
      serializers.deserialize(json.decode(payload!) as Object),
      isA<SettingsState>(),
    );
  });

  test('storage key preserves username before url order', () {
    final key = getStorageKey('anna', testLoginAddress);
    final decoded = json.decode(key) as Map<String, dynamic>;

    expect(decoded.keys.toList(), <String>['username', 'server_url']);
  });
}

Future<String?> storedPayload(TestSecureStorage storage, String username) {
  return storage.read(
    key: escapeKey(getStorageKey(username, testLoginAddress)),
  );
}

Store<AppState, AppStateBuilder, AppActions> _createLoggedInStore({
  required String username,
  AppState? state,
}) {
  return Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    state ??
        AppState(
          (b) => b.loginState
            ..loggedIn = true
            ..username = username,
        ),
    AppActions(),
    middleware: middleware(includeErrorMiddleware: false),
  );
}
