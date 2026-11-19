import 'dart:convert';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

class AccountWrapper extends MockWrapper {
  @override
  String? user, pass, url;
  @override
  bool safeMode = false;
  @override
  bool noInternet = false;
  @override
  bool demoMode = false;
  @override
  void Function()? onLogout;
  bool signedIn = false;
  int endedSessions = 0;

  @override
  String get loginAddress => '$url/v2/api/auth/login';
  @override
  Future<bool> get loggedIn async => signedIn;
  @override
  Config get config => Config((b) => b
    ..autoLogoutSeconds = 300
    ..currentSemesterMaybe = 1
    ..fullName = 'Test'
    ..imgSource = ''
    ..isStudentOrParent = true
    ..userId = 1);

  @override
  Future<dynamic> login(
      String? user, String? pass, String? tfaCode, String? url,
      {void Function()? logout,
      Future<void>? Function()? configLoaded,
      void Function()? relogin,
      AddNetworkProtocolItem? addProtocolItem}) async {
    this.user = user;
    this.pass = pass;
    this.url = url;
    onLogout = logout;
    signedIn = true;
    await configLoaded?.call();
    return null;
  }

  @override
  Future<dynamic> send(String path,
          {Map<String, Object?> args = const {},
          String method = 'POST',
          bool isRetryAfterUnexpectedLogout = false,
          bool forceRelogin = false,
          int unexpectedLogoutRetryCount = 0,
          bool acceptEmptyResponse = false}) async =>
      null;

  @override
  void logout({required bool hard, bool logoutForcedByServer = false}) {
    endedSessions++;
    signedIn = false;
    if (hard) user = pass = url = null;
  }
}

Map<String, Object?> account(String user) => {
      'user': user,
      'pass': 'password-$user',
      'url': 'https://example.org',
    };

Future<Map<String, dynamic>> savedLogin() async =>
    jsonDecode((await secureStorage.read(key: 'login'))!)
        as Map<String, dynamic>;

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  test('full two-account flow retains both accounts after restarting',
      () async {
    wrapper = AccountWrapper();
    final store = createStore(withMiddleware: true);
    Future<void> signIn(String user) =>
        store.actions.loginActions.login(LoginPayload((b) => b
          ..user = user
          ..pass = 'password-$user'
          ..url = 'https://example.org'
          ..fromStorage = false));
    await signIn('a');
    await store.actions.settingsActions.deleteDataOnLogout(true);
    await store.actions.settingsActions.saveNoPass(true);
    await store.actions.loginActions.addAccount();
    expect(store.state.loginState.otherAccounts.toList(), ['a']);
    await signIn('b');
    expect(store.state.loginState.otherAccounts.toList(), ['a']);
    for (final user in ['a', 'b', 'a']) {
      await store.actions.loginActions.selectAccount(0);
      expect(store.state.loginState.username, user);
      expect(store.state.loginState.otherAccounts.toList(),
          [user == 'a' ? 'b' : 'a']);
    }

    store.dispose();
    await resetTestState();
    // A fresh store and real wrapper use only the persisted credentials and
    // global settings, just as startup does. No sign-in may happen here.
    wrapper = Wrapper();
    final settings = await settingsPersistenceService.load();
    expect(settings?.noPasswordSaving, isTrue);
    final restarted = createStore(
        withMiddleware: true,
        initialState: AppState((b) => b.settingsState.replace(settings!)));
    addTearDown(restarted.dispose);
    await restarted.actions.load();
    expect(restarted.state.loginState.loggedIn, isFalse);
    expect(restarted.state.loginState.loading, isFalse);
    expect(restarted.state.loginState.otherAccounts.toList(), ['a', 'b']);
    expect((await savedLogin())['user'], 'a');
    wrapper = AccountWrapper();
    await restarted.actions.loginActions.selectAccount(0);
    expect(restarted.state.loginState.username, 'a');
    expect(restarted.state.loginState.otherAccounts.toList(), ['b']);
    await restarted.actions.loginActions.selectAccount(0);
    expect(restarted.state.loginState.username, 'b');
    expect(restarted.state.loginState.otherAccounts.toList(), ['a']);
  });

  test('a real demo login remains selectable without automatic startup sign-in',
      () async {
    wrapper = Wrapper()..safeMode = true;
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) => b.settingsState.noPasswordSaving = true));
    addTearDown(store.dispose);
    await store.actions.loginActions.login(LoginPayload((b) => b
      ..user = 'demo'
      ..pass = 'demo'
      ..url = ''
      ..fromStorage = false));
    expect((await savedLogin())['user'], 'demo');
    await store.actions.loginActions.addAccount();
    expect(store.state.loginState.otherAccounts.toList(), ['demo']);
    await store.actions.loginActions.selectAccount(0);
    expect(store.state.loginState.username, 'demo');
    expect((await savedLogin())['user'], 'demo');
  });

  for (final index in [0, 1]) {
    test('startup picker signs into the selected account at index $index',
        () async {
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account('a'),
            'otherAccounts': [account('b')],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState:
              AppState((b) => b.settingsState.noPasswordSaving = true));
      addTearDown(store.dispose);
      await store.actions.load();
      wrapper = AccountWrapper();
      await store.actions.loginActions.selectAccount(index);
      expect(store.state.loginState.username, index == 0 ? 'a' : 'b');
      expect(store.state.loginState.otherAccounts.toList(),
          [index == 0 ? 'b' : 'a']);
    });

    test('remove the correct account from the startup picker at index $index',
        () async {
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account('a'),
            'otherAccounts': [account('b')],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState:
              AppState((b) => b.settingsState.noPasswordSaving = true));
      addTearDown(store.dispose);
      await store.actions.load();
      expect(store.state.loginState.otherAccounts.toList(), ['a', 'b']);
      await store.actions.loginActions.removeAccount(index);
      expect(store.state.loginState.otherAccounts.toList(),
          [index == 0 ? 'b' : 'a']);
    });
  }

  for (final noPasswordSaving in [false, true]) {
    test(
        'explicit logout deletes account data but keeps the account, '
        'remember off: $noPasswordSaving', () async {
      wrapper = AccountWrapper()
        ..user = 'a'
        ..pass = 'password-a'
        ..url = 'https://example.org'
        ..signedIn = true;
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account('a'),
            'otherAccounts': [account('b')],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState: AppState((b) => b
            ..loginState.loggedIn = true
            ..loginState.username = 'a'
            ..settingsState.noPasswordSaving = noPasswordSaving
            ..settingsState.deleteDataOnLogout = true
            ..absencesState.statistic.counter = 5));
      addTearDown(store.dispose);
      await store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = false));
      expect(store.state.loginState.loggedIn, isFalse);
      // Signing out keeps the account (#142); only removal deletes it.
      expect(store.state.loginState.otherAccounts.toList(), ['a', 'b']);
      expect(await savedLogin(), {
        ...account('a'),
        'signedOut': true,
        'otherAccounts': [account('b')],
      });
      final stored = await secureStorage.read(
          key: escapeKey(
              getStorageKey('a', 'https://example.org/v2/api/auth/login')));
      expect(serializers.deserialize(jsonDecode(stored!) as Object),
          isA<SettingsState>());
    });
  }

  for (final addNewAccount in [false, true]) {
    test(
        'disabling remember me before ${addNewAccount ? 'adding' : 'switching'} '
        'does not lose the outgoing account', () async {
      final session = AccountWrapper()
        ..user = 'a'
        ..pass = 'password-a'
        ..url = 'https://example.org'
        ..signedIn = true;
      wrapper = session;
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account('a'),
            'otherAccounts': [account('b')],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState: AppState((b) => b
            ..loginState.loggedIn = true
            ..loginState.username = 'a'
            ..settingsState.deleteDataOnLogout = true));
      addTearDown(store.dispose);

      // Exercise the actual setting action, rather than initializing the state
      // with noPasswordSaving already enabled as the earlier tests did.
      await store.actions.settingsActions.saveNoPass(true);
      if (addNewAccount) {
        await store.actions.loginActions.addAccount();
      } else {
        await store.actions.loginActions.selectAccount(0);
      }
      expect(store.state.loginState.otherAccounts, contains('a'));
    });
  }

  for (final noPasswordSaving in [false, true]) {
    test(
        'repeated switches retain accounts and data, remember off: '
        '$noPasswordSaving', () async {
      final session = AccountWrapper()
        ..user = 'a'
        ..pass = 'password-a'
        ..url = 'https://example.org'
        ..signedIn = true;
      wrapper = session;
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account('a'),
            'otherAccounts': [account('b'), account('c')],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState: AppState((b) => b
            ..loginState.loggedIn = true
            ..loginState.username = 'a'
            ..settingsState.noPasswordSaving = noPasswordSaving
            ..settingsState.deleteDataOnLogout = true
            ..absencesState.statistic.counter = 5));
      addTearDown(store.dispose);
      var logouts = 0;
      final subscription =
          store.actionStream(LoginActionsNames.logout).listen((_) => logouts++);
      addTearDown(subscription.cancel);

      for (final user in ['b', 'a', 'b', 'a']) {
        await store.actions.loginActions.selectAccount(0);
        expect(store.state.loginState.username, user);
        expect(store.state.loginState.loggedIn, isTrue);
        final login = await savedLogin();
        expect(login['user'], user);
        expect({
          login['user'],
          for (final other in login['otherAccounts'] as List) other['user'],
        }, {
          'a',
          'b',
          'c'
        });
        expect(store.state.settingsState.noPasswordSaving, noPasswordSaving);
        expect(session.safeMode, noPasswordSaving);
        expect(deletedData, isFalse);
      }
      final stored = await secureStorage.read(
          key: escapeKey(
              getStorageKey('a', 'https://example.org/v2/api/auth/login')));
      final restored =
          serializers.deserialize(jsonDecode(stored!) as Object) as AppState;
      expect(restored.absencesState.statistic?.counter, 5);
      expect(session.endedSessions, 4);
      expect(logouts, 0);
    });
  }

  test('adding an account does not save a transient login or delete saved ones',
      () async {
    final session = AccountWrapper()
      ..user = 'transient'
      ..pass = 'temporary-password'
      ..url = 'https://example.org'
      ..signedIn = true;
    wrapper = session;
    await secureStorage.write(
        key: 'login',
        value: jsonEncode({
          'otherAccounts': [account('a'), account('b')],
        }));
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) => b
          ..loginState.loggedIn = true
          ..loginState.username = 'transient'
          ..settingsState.noPasswordSaving = true
          ..settingsState.deleteDataOnLogout = true));
    addTearDown(store.dispose);
    await store.actions.loginActions.addAccount();
    expect((await savedLogin())['otherAccounts'], [account('a'), account('b')]);
    expect((await savedLogin()).containsKey('pass'), isFalse);
    expect(store.state.loginState.otherAccounts.toList(), ['a', 'b']);
    expect(session.endedSessions, 1);
    expect(deletedData, isFalse);
  });

  test('late logout callback from an old session cannot delete current data',
      () async {
    final old = AccountWrapper();
    wrapper = old;
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) => b.settingsState
          ..noPasswordSaving = true
          ..deleteDataOnLogout = true));
    addTearDown(store.dispose);
    await store.actions.loginActions.login(LoginPayload((b) => b
      ..user = 'a'
      ..pass = 'password-a'
      ..url = 'https://example.org'
      ..fromStorage = false));
    final lateLogout = old.onLogout!;
    wrapper = AccountWrapper();
    lateLogout();
    await Future<void>.delayed(Duration.zero);
    expect(store.state.loginState.loggedIn, isTrue);
    expect(deletedData, isFalse);
  });

  group('signing out keeps the account (#142)', () {
    Future<Store<AppState, AppStateBuilder, AppActions>> signedInAs(
      String user, {
      List<String> others = const [],
      bool noPasswordSaving = false,
      bool deleteDataOnLogout = false,
    }) async {
      wrapper = AccountWrapper()
        ..user = user
        ..pass = 'password-$user'
        ..url = 'https://example.org'
        ..signedIn = true;
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({
            ...account(user),
            'otherAccounts': [for (final other in others) account(other)],
          }));
      final store = createStore(
          withMiddleware: true,
          initialState: AppState((b) => b
            ..loginState.loggedIn = true
            ..loginState.username = user
            ..url = 'https://example.org'
            ..settingsState.noPasswordSaving = noPasswordSaving
            ..settingsState.deleteDataOnLogout = deleteDataOnLogout));
      addTearDown(store.dispose);
      return store;
    }

    Future<void> signOut(Store<AppState, AppStateBuilder, AppActions> store) =>
        store.actions.loginActions.logout(LogoutPayload((b) => b
          ..hard = true
          ..forced = false));

    String storageKeyOf(String user) =>
        escapeKey(getStorageKey(user, 'https://example.org/v2/api/auth/login'));

    for (final noPasswordSaving in [false, true]) {
      test(
          'the account is listed after signing out and signs in without '
          'its password, remember off: $noPasswordSaving', () async {
        final store = await signedInAs('a',
            others: ['b'], noPasswordSaving: noPasswordSaving);

        await signOut(store);

        expect(store.state.loginState.loggedIn, isFalse);
        expect(store.state.loginState.otherAccounts.toList(), ['a', 'b']);
        // The session is gone; nothing can sign in on its own.
        final session = AccountWrapper();
        wrapper = session;

        await store.actions.loginActions.selectAccount(0);

        expect(store.state.loginState.loggedIn, isTrue);
        expect(store.state.loginState.username, 'a');
        expect(session.user, 'a');
        expect(session.pass, 'password-a');
        expect(store.state.loginState.otherAccounts.toList(), ['b']);
        // Signed in again: the account is no longer marked as signed out.
        expect(await savedLogin(), {
          ...account('a'),
          'otherAccounts': [account('b')],
        });
      });
    }

    test('the other saved account can be chosen after signing out', () async {
      final store = await signedInAs('a', others: ['b']);
      await signOut(store);
      wrapper = AccountWrapper();

      await store.actions.loginActions.selectAccount(1);

      expect(store.state.loginState.username, 'b');
      expect(store.state.loginState.otherAccounts.toList(), ['a']);
      final login = await savedLogin();
      expect(login['user'], 'b');
      expect(login.containsKey('signedOut'), isFalse);
      expect(login['otherAccounts'], [account('a')]);
    });

    test('the app does not sign in on its own at the next start', () async {
      final store = await signedInAs('a', others: ['b']);
      await signOut(store);
      store.dispose();
      await resetTestState();

      final session = AccountWrapper();
      wrapper = session;
      final restarted = createStore(withMiddleware: true);
      addTearDown(restarted.dispose);
      await restarted.actions.load();

      expect(restarted.state.loginState.loggedIn, isFalse);
      expect(session.signedIn, isFalse);
      expect(restarted.state.loginState.otherAccounts.toList(), ['a', 'b']);

      await restarted.actions.loginActions.selectAccount(0);
      expect(restarted.state.loginState.username, 'a');
      expect(session.pass, 'password-a');
    });

    test('a sign-in typed on the sign-in screen clears the mark', () async {
      final store = await signedInAs('a');
      await signOut(store);
      wrapper = AccountWrapper();

      await store.actions.loginActions.login(LoginPayload((b) => b
        ..user = 'a'
        ..pass = 'password-a'
        ..url = 'https://example.org'
        ..fromStorage = false));

      expect(await savedLogin(), {...account('a'), 'otherAccounts': []});
    });

    test('deleting data on sign out keeps the account and its credentials',
        () async {
      final store = await signedInAs('a', deleteDataOnLogout: true);
      await signOut(store);

      expect(deletedData, isTrue);
      expect(await savedLogin(), {
        ...account('a'),
        'signedOut': true,
        'otherAccounts': [],
      });
      // Only the settings are saved for the account, no register data.
      final stored = serializers.deserialize(
          jsonDecode((await secureStorage.read(key: storageKeyOf('a')))!)
              as Object);
      expect(stored, isA<SettingsState>());
      expect(store.state.loginState.otherAccounts.toList(), ['a']);
    });

    for (final index in [0, 1]) {
      test('removing account $index after signing out removes only it',
          () async {
        final store = await signedInAs('a', others: ['b']);
        await secureStorage.write(key: storageKeyOf('b'), value: 'state of b');
        await signOut(store);
        expect(await secureStorage.read(key: storageKeyOf('a')), isNotNull);

        await store.actions.loginActions.removeAccount(index);

        final removed = index == 0 ? 'a' : 'b';
        final kept = index == 0 ? 'b' : 'a';
        expect(store.state.loginState.otherAccounts.toList(), [kept]);
        final login = await savedLogin();
        final users = {
          if (login['user'] != null) login['user'],
          for (final other in login['otherAccounts'] as List) other['user'],
        };
        expect(users, {kept});
        expect(jsonEncode(login), isNot(contains('password-$removed')));
        expect(await secureStorage.read(key: storageKeyOf(removed)), isNull);
        expect(await secureStorage.read(key: storageKeyOf(kept)), isNotNull);
        if (index == 0) expect(login.containsKey('signedOut'), isFalse);
      });
    }

    test('an expired session keeps forgetting the credentials as before',
        () async {
      final store =
          await signedInAs('a', others: ['b'], noPasswordSaving: true);

      await store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = true));

      expect(store.state.loginState.loggedIn, isFalse);
      expect(store.state.loginState.otherAccounts.toList(), ['b']);
      expect((await savedLogin()).containsKey('pass'), isFalse);
      expect((await savedLogin()).containsKey('signedOut'), isFalse);
    });

    test('signing out of the demo leaves no saved demo account', () async {
      wrapper = Wrapper();
      final store = createStore(withMiddleware: true);
      addTearDown(store.dispose);
      await store.actions.loginActions.login(LoginPayload((b) => b
        ..user = 'demo'
        ..pass = 'demo'
        ..url = ''
        ..fromStorage = false));
      expect((await savedLogin())['user'], 'demo');

      await signOut(store);

      final login = await savedLogin();
      expect(login.containsKey('user'), isFalse);
      expect(login.containsKey('pass'), isFalse);
      expect(login.containsKey('signedOut'), isFalse);
      expect(store.state.loginState.otherAccounts.toList(), isEmpty);
    });
  });
}
