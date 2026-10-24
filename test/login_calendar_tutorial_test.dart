import 'dart:async';
import 'dart:convert';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/home_page.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

class _StartupSession extends Wrapper {
  final requested = Completer<void>();
  final release = Completer<void>();
  int calendarRequests = 0;

  @override
  Future<bool> get loggedIn async => true;

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
    config = Config((b) => b
      ..userId = 1
      ..autoLogoutSeconds = 300
      ..fullName = ''
      ..imgSource = ''
      ..isStudentOrParent = true);
    await configLoaded?.call();
    return {'loggedIn': true};
  }

  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    if (url == 'api/student/dashboard/dashboard') return <dynamic>[];
    if (url != 'api/calendar/student') return null;
    calendarRequests++;
    if (!requested.isCompleted) requested.complete();
    await release.future;
    if (calendarRequests > 4) return null;
    final monday = DateTime.parse(args['startDate']! as String);
    return <String, dynamic>{
      for (var offset = 0; offset < 6; offset++)
        monday.add(Duration(days: offset)).toIso8601String().substring(0, 10):
            <String, dynamic>{
          'class': <String, dynamic>{'group': <String, dynamic>{}},
        },
    };
  }
}

void main() {
  late _StartupSession session;
  setUp(() async {
    session = _StartupSession();
    await bootstrapTestEnvironment(
        wrapperOverride: session,
        fixedNow: UtcDateTime(2026, 10, 20),
        sharedPreferences: const {});
  });
  tearDown(resetTestState);

  for (final restored in [false, true]) {
    testWidgets(
        'login and skipping the tutorial populates dashboard holidays (restored=$restored)',
        (tester) async {
      if (restored) {
        // Older snapshots may have been saved before the login URL was set.
        await secureStorage.write(
            key: escapeKey(getStorageKey(
                'startup-test', '$testServerUrl/v2/api/auth/login')),
            value: jsonEncode(serializers.serialize(AppState())));
      }
      final store = createStore(withMiddleware: true);
      // Optional onboarding now belongs to the mounted home route and follows
      // the startup notices instead of being pushed by login middleware.
      schoolNotificationStartupReady.value = true;
      await pumpApp(tester, store: store, home: HomePage());
      final pending = store.actions.loginActions.login(LoginPayload((b) => b
        ..user = 'startup-test'
        ..pass = 'test-password'
        ..url = testServerUrl
        ..fromStorage = false));
      await settleFor(tester, duration: const Duration(seconds: 1));
      await pending;
      expect(session.requested.isCompleted, isTrue);
      expect(store.state.url, testServerUrl);
      expect(store.state.calendarState.days, isEmpty);
      expect(find.text('Willkommen!'), findsOneWidget,
          reason: 'offer must appear before any tap on the dashboard');
      await tester.tap(find.text('Überspringen'));
      await settleFor(tester);
      expect(tutorialService.active, isFalse);
      session.release.complete();
      for (var attempt = 0;
          attempt < 40 && session.calendarRequests < 5;
          attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await settleFor(tester);
      expect(store.state.calendarState.days.length, 24,
          reason:
              'the login URL update must not cancel the first history request');
      expect(
          find.byKey(const ValueKey('holiday-countdown-card')), findsOneWidget);
      expect(store.state.calendarState.currentMonday, isNull,
          reason: 'holidays must load without opening the calendar page');
      expect(session.calendarRequests, 5);
      expect(tester.takeException(), isNull);
      statePersistenceService.clear();
      unawaited(androidWidgetSnapshotService.clear());
      store.dispose();
    });
  }
}
