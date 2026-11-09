// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart' hide Action;
import 'package:dio/dio.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/biometric_app_lock.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' hide main;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

const _configPage = '''
<script>var currentUserId=3539;
var config = { auto_logout_seconds: 300, };</script>
<img id="navigationProfilePicture" src="profile.png">Test User<
''';

const _loginRedirect = '''
<script type="text/javascript">
window.location = "https://example.digitalesregister.it/v2/login";
</script>
''';

/// A server whose session can die. Sign-ins bring it back.
class _Server implements HttpClientAdapter {
  bool sessionAlive = true;

  /// What a request gets from a dead session.
  ResponseBody Function() onDeadSession = () => ResponseBody.fromString(
        _loginRedirect,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );

  /// How many of the next requests to the API fail on the connection.
  int connectionFailures = 0;
  DioExceptionType failureType = DioExceptionType.connectionError;
  Object failure = const SocketException('Connection reset');
  int logins = 0, saves = 0;

  /// Answers everything but a sign-in with this status, whatever the session.
  int? refusal;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('api/auth/login')) {
      logins++;
      sessionAlive = true;
      return ResponseBody.fromString(
        jsonEncode({'loggedIn': true}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'set-cookie': ['session=test; Path=/'],
        },
      );
    }
    if (options.path.endsWith('/v2/')) {
      return ResponseBody.fromString(
        _configPage,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      );
    }
    if (connectionFailures > 0) {
      connectionFailures--;
      throw DioException(
        requestOptions: options,
        type: failureType,
        error: failure,
      );
    }
    if (refusal != null) return ResponseBody.fromString('', refusal!);
    if (!sessionAlive) return onDeadSession();
    saves++;
    return ResponseBody.fromString(
      jsonEncode({'success': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(Wrapper, _Server)> _signedIn() async {
  final server = _Server();
  final session = Wrapper()
    ..safeMode = false
    ..dio.httpClientAdapter = server;
  await session.login(
    'user',
    'password',
    null,
    'https://example.digitalesregister.it',
    logout: () {},
    configLoaded: () => null,
    relogin: () {},
    addProtocolItem: (_) {},
  );
  expect(await session.loggedIn, isTrue);
  server.logins = 0;
  return (session, server);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dr/biometric_app_lock');

  final defaultStorageDelays = storageRetryDelays;
  final defaultRequestDelay = requestRetryDelay;

  setUp(() async {
    await bootstrapTestEnvironment();
    storageRetryDelays = const [Duration.zero, Duration.zero];
    requestRetryDelay = Duration.zero;
    // What the wrapper reports to the app goes through the global actions.
    createStore(appActions: actions);
  });
  tearDown(() async {
    wrapper.resumeNetworkActivity();
    storageRetryDelays = defaultStorageDelays;
    requestRetryDelay = defaultRequestDelay;
    await resetTestState();
  });

  group('after the app returned to the foreground', () {
    late Completer<bool> authentication;
    late LifecycleObserver observer;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      biometricAppLockController.syncEnabled(false);
      biometricAppLockController.syncEnabled(true);
      authentication = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'authenticate') return authentication.future;
        return 'success';
      });
      observer = LifecycleObserver(() {}, () {});
    });

    tearDown(() {
      biometricAppLockController.syncEnabled(false);
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('requests work again when the prompt covered the app for a moment',
        () async {
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // The prompt, or a quick switch to another app, hides the app while its
      // resume is still running.
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(wrapper.isAppInForeground, isTrue);
      authentication.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(wrapper.isAppInForeground, isTrue);
    });
  });

  group('a request to a session that has died', () {
    test('signs in again after a login page, as before', () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server.sessionAlive = false;
      final result = await session.send('api/student/dashboard/save_reminder');
      expect(result, {'success': true});
      expect(server.logins, 1);
    });

    for (final status in const [401, 403]) {
      test('signs in again after status $status', () async {
        final (session, server) = await _signedIn();
        addTearDown(() => session.logout(hard: true));
        server
          ..sessionAlive = false
          ..onDeadSession = () => ResponseBody.fromString('', status);
        final result =
            await session.send('api/student/dashboard/save_reminder');
        expect(result, {'success': true});
        expect(server.logins, 1);
        expect(server.saves, 1);
      });
    }

    test('a refusal that stays gets one new session, and no more', () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server.refusal = 403;
      expect(await session.send('api/not/for/this/account'), isNull);
      expect(server.logins, 1);
      // Within the minute the next one does not sign in again.
      expect(await session.send('api/not/for/this/account'), isNull);
      expect(server.logins, 1);
    });

    test('an upload signs in again after a login page as well', () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server
        ..sessionAlive = false
        ..onDeadSession = () => ResponseBody.fromString(
              '<html><head><title>Login</title></head></html>',
              200,
              headers: {
                Headers.contentTypeHeader: ['text/html'],
              },
            );
      final result = await session.sendBytes(
        'api/profile/uploadProfilePicture',
        bytes: const [1, 2, 3],
      );
      expect(result, {'success': true});
      expect(server.logins, 1);
    });
  });

  group('a request that loses its connection', () {
    test('a save survives a connection that went stale', () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server.connectionFailures = 1;
      final result = await session.send('api/student/dashboard/save_reminder');
      expect(result, {'success': true});
      expect(server.saves, 1);
      expect(session.noInternet, isFalse);
    });

    test('a closed keep-alive connection counts as well', () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server
        ..connectionFailures = 1
        ..failureType = DioExceptionType.unknown
        ..failure = const HttpException(
          'Connection closed before full header was received',
        );
      final result = await session.send('api/student/dashboard/save_reminder');
      expect(result, {'success': true});
      expect(session.noInternet, isFalse);
    });

    test('a save that timed out may have arrived and is not sent twice',
        () async {
      final (session, server) = await _signedIn();
      addTearDown(() => session.logout(hard: true));
      server
        ..connectionFailures = 1
        ..failureType = DioExceptionType.receiveTimeout;
      await session.send('api/student/dashboard/save_reminder');
      expect(server.saves, 0);
    });
  });

  group('writing the state of an account', () {
    AppState state(String username) => AppState((b) {
          b.loginState
            ..loggedIn = true
            ..username = username;
        });

    Future<void> flush(
      AppStatePersistenceService service,
      PersistStateWriter writer, {
      String username = 'anna',
    }) =>
        service.flush(
          state: state(username),
          deletedData: false,
          server: 'server',
          writer: writer,
          keyFactory: (user, server) => '$user@$server',
        );

    test('a storage that fails for a moment does not lose the write', () async {
      final service = AppStatePersistenceService();
      var calls = 0;
      await flush(service, (key, value) async {
        if (++calls < 3) throw const FileSystemException('locked');
        await Future<void>.value();
      });
      expect(calls, 3);
    });

    test('a write that keeps failing is tried again later, and works',
        () async {
      var warnings = 0;
      final service = AppStatePersistenceService(
        failureRetry: const Duration(milliseconds: 10),
        onWriteFailed: () => warnings++,
      );
      addTearDown(service.clear);
      var broken = true;
      final written = <String>[];
      await expectLater(
        flush(service, (key, value) {
          if (broken) throw const FileSystemException('locked');
          written.add(key);
          return Future<void>.value();
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(warnings, 1);
      broken = false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await service.drain();
      expect(written, ['anna@server']);
    });

    test('a failed write does not block the next one', () async {
      final service = AppStatePersistenceService();
      addTearDown(service.clear);
      await expectLater(
        flush(
            service, (key, value) => throw const FileSystemException('locked')),
        throwsA(isA<FileSystemException>()),
      );
      final written = <String>[];
      await flush(service, (key, value) {
        written.add(key);
        return Future<void>.value();
      });
      expect(written, ['anna@server']);
    });

    test('a retry does not outlive the account it was for', () async {
      final service = AppStatePersistenceService();
      var calls = 0;
      await flush(service, (key, value) {
        calls++;
        service.clear();
        throw const FileSystemException('locked');
      });
      expect(calls, 1);
    });
  });

  group('writing the shared settings', () {
    late _FlakyPreferences preferences;

    setUp(() {
      preferences = _FlakyPreferences();
      SharedPreferencesStorePlatform.instance = preferences;
      SharedPreferences.resetStatic();
    });

    test('a file that is locked for a moment does not lose the change',
        () async {
      preferences.failures = 2;
      await SettingsPersistenceService().save(SettingsState());
      expect(preferences.failures, 0);
    });

    test('a store that stays broken fails, and the next save works', () async {
      final service = SettingsPersistenceService();
      preferences.failures = 100;
      await expectLater(
        service.save(SettingsState()),
        throwsA(isA<StateError>()),
      );
      preferences.failures = 0;
      await service.save(SettingsState());
    });

    test('the retry of an older save gives way to a newer one', () async {
      storageRetryDelays = const [Duration(milliseconds: 20)];
      final service = SettingsPersistenceService();
      preferences.failures = 1;
      final older =
          service.save(SettingsState((b) => b.noPasswordSaving = true));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.save(SettingsState((b) => b.noPasswordSaving = false));
      await older;
      expect((await service.load())!.noPasswordSaving, isFalse);
    });
  });

  group('saving a change on the dashboard', () {
    final day = UtcDateTime(2050);
    late MockWrapper session;

    Homework reminder() => buildHomework(
          id: 7,
          title: 'Erinnerung',
          subtitle: 'Alter Text',
          deleteable: true,
        );

    Future<(Store<AppState, AppStateBuilder, AppActions>, List<String>)>
        setUpDashboard({required bool offline}) async {
      session = MockWrapper();
      when(() => session.noInternet).thenReturn(offline);
      when(() => session.url).thenReturn(testServerUrl);
      when(() => session.user).thenReturn('user');
      wrapper = session;
      final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) {
          b.dashboardState.allDays = ListBuilder<Day>([
            buildDay(date: day, homework: [reminder()]),
          ]);
          b.noInternet = offline;
        }),
      );
      return (store, <String>[]);
    }

    void failRequests() => when(
          () => session.send(any(), args: any(named: 'args')),
        ).thenAnswer((_) async => null);

    Future<void> pumpMessenger(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(),
      ));
    }

    testWidgets('offline, a new reminder fails with a message', (tester) async {
      await pumpMessenger(tester);
      final (store, _) = await setUpDashboard(offline: true);
      failRequests();
      await tester.runAsync(() => store.actions.dashboardActions.addReminder(
            AddReminderPayload((b) => b
              ..date = day
              ..msg = 'Neu'),
          ));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);
      expect(store.state.dashboardState.allDays![0].homework, hasLength(1));
    });

    testWidgets('offline, an entry is not removed for good', (tester) async {
      await pumpMessenger(tester);
      final (store, _) = await setUpDashboard(offline: true);
      failRequests();
      await tester.runAsync(
        () => store.actions.dashboardActions.deleteHomework(reminder()),
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(store.state.dashboardState.allDays![0].homework, hasLength(1));
      verifyNever(() => session.send(any(), args: any(named: 'args')));
    });

    testWidgets('a failed edit leaves the old entry on the server',
        (tester) async {
      await pumpMessenger(tester);
      final (store, _) = await setUpDashboard(offline: false);
      failRequests();
      await tester.runAsync(() => store.actions.dashboardActions.editReminder(
            EditReminderPayload((b) => b
              ..date = day
              ..msg = 'Neu'
              ..previousHomework.replace(reminder())),
          ));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      verifyNever(() => session.send(
            'api/student/dashboard/delete_reminder',
            args: any(named: 'args'),
          ));
    });

    testWidgets('a tick shows at once and goes back if it is not saved',
        (tester) async {
      await pumpMessenger(tester);
      final (store, _) = await setUpDashboard(offline: false);
      final answer = Completer<dynamic>();
      when(() => session.send(any(), args: any(named: 'args')))
          .thenAnswer((_) => answer.future);
      bool checked() =>
          store.state.dashboardState.allDays![0].homework[0].checked;

      late Future<void> toggle;
      await tester.runAsync(() async {
        toggle = store.actions.dashboardActions.toggleDone(
          ToggleDonePayload((b) => b
            ..homeworkId = 7
            ..type = 'homework'
            ..done = true),
        );
        await Future<void>.delayed(Duration.zero);
      });
      expect(checked(), isTrue, reason: 'before the server answered');

      await tester.runAsync(() async {
        answer.complete(null);
        await toggle;
      });
      await tester.pump();
      expect(checked(), isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('the button sends a failed change again', (tester) async {
      await pumpMessenger(tester);
      final (store, _) = await setUpDashboard(offline: false);
      failRequests();
      await tester.runAsync(() => store.actions.dashboardActions.toggleDone(
            ToggleDonePayload((b) => b
              ..homeworkId = 7
              ..type = 'gradeGroup'
              ..done = true),
          ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      when(() => session.send(any(), args: any(named: 'args'))).thenAnswer(
        (_) async => <String, Object?>{'success': true},
      );
      await tester.runAsync(() async {
        await tester.tap(find.byType(SnackBarAction));
        await Future<void>.delayed(Duration.zero);
      });
      verify(() => session.send(
            'api/student/dashboard/toggle_reminder',
            args: any(named: 'args'),
          )).called(2);
    });
  });
}

class _FlakyPreferences extends SharedPreferencesStorePlatform {
  final _store = InMemorySharedPreferencesStore.empty();
  int failures = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failures > 0) {
      failures--;
      return false;
    }
    return _store.setValue(valueType, key, value);
  }

  @override
  Future<bool> clear() => _store.clear();

  @override
  Future<Map<String, Object>> getAll() => _store.getAll();

  @override
  Future<bool> remove(String key) => _store.remove(key);

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _store.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) =>
      _store.getAllWithParameters(parameters);
}
