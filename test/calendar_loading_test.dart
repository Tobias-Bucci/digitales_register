import 'dart:async';

import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import 'support/test_harness.dart';

class _DelayedCalendar extends Wrapper {
  _DelayedCalendar({this.blockAt = 1, this.failFirst = false});
  int blockAt;
  bool failFirst;
  final blocked = Completer<void>();
  final release = Completer<void>();
  final requestedWeeks = <String>[];

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
    final start = args['startDate']! as String;
    requestedWeeks.add(start);
    if (failFirst && requestedWeeks.length == 1) return null;
    if (requestedWeeks.length >= blockAt) {
      if (!blocked.isCompleted) blocked.complete();
      await release.future;
      return null;
    }
    final monday = DateTime.parse(start);
    return <String, dynamic>{
      for (var offset = 0; offset < 6; offset++)
        monday.add(Duration(days: offset)).toIso8601String().substring(0, 10):
            <String, dynamic>{
          'class': <String, dynamic>{'group': <String, dynamic>{}},
        },
    };
  }
}

AppState _signedInState() => AppState((b) => b
  ..loginState.loggedIn = true
  ..loginState.username = 'calendar-test');

void main() {
  tearDown(resetTestState);

  group('calendar widgets', () {
    late _DelayedCalendar session;
    setUp(() async {
      session = _DelayedCalendar(blockAt: 999);
      await bootstrapTestEnvironment(
          wrapperOverride: session, fixedNow: UtcDateTime(2026, 10, 20));
    });

    testWidgets('a failed week stops spinning and can be loaded again',
        (tester) async {
      session.failFirst = true;
      final store = createStore(
          initialState: _signedInState().rebuild((b) => b
            ..loginState.username = null
            ..calendarState.currentMonday = toMonday(now)),
          withMiddleware: true);
      await pumpApp(tester, store: store, home: CalendarContainer());
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('calendar-retry-week')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-retry-week')));
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(session.requestedWeeks.length, 2);
      expect(store.state.calendarState.currentDays.length, 6);
      expect(find.byKey(const Key('calendar-retry-week')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening the timetable does not wait for the history scan',
        (tester) async {
      session.blockAt = 2;
      final store = createStore(
          initialState:
              _signedInState().rebuild((b) => b.loginState.username = null),
          withMiddleware: true);
      await pumpApp(tester,
          store: store,
          home: ResponsiveScaffold<Pages>(
            key: app.scaffoldKey,
            navKey: app.nestedNavKey,
            homeId: Pages.homework,
            homeBody: const Text('Dashboard'),
            homeAppBar: AppBar(title: const Text('Register')),
            drawerBuilder: (_, __, ___, ____) => const SizedBox(width: 68),
          ));
      var opened = false;
      final navigation = store.actions.routingActions
          .showCalendar()
          .then((_) => opened = true);
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(session.blocked.isCompleted, isTrue);
      expect(opened, isTrue);
      expect(store.state.calendarState.currentDays.length, 6);
      expect(find.byType(AlertDialog), findsNothing);
      // End the background session before disposing the widget test's clock.
      wrapper = Wrapper();
      session.release.complete();
      await settleFor(tester);
      await navigation;
      expect(session.requestedWeeks.length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  test('nearby holiday data is published before the full year completes',
      () async {
    final session = _DelayedCalendar(blockAt: 5);
    await bootstrapTestEnvironment(
        wrapperOverride: session, fixedNow: UtcDateTime(2026, 10, 20));
    final store = createStore(initialState: _signedInState());
    final pending = loadExportCalendarYear(
      state: () => store.state,
      onLoaded: store.actions.calendarActions.loaded.call,
      progressive: true,
    );
    try {
      await session.blocked.future.timeout(const Duration(seconds: 3));
      expect(session.requestedWeeks.first, '2026-10-19');
      expect(session.requestedWeeks[1], '2026-10-26');
      expect(store.state.calendarState.days.length, 24);
      expect(store.state.calendarState.prefetchedSchoolYears, isEmpty);
      final timeline = SchoolTimeline.fromCalendarData(
          dashboardDays: [],
          calendarDays: store.state.calendarState.days.values);
      expect(timeline.holidays, isNotEmpty,
          reason: 'holidays must not wait for the final school-year request');
    } finally {
      session.release.complete();
    }
    expect(await pending, isFalse);
    expect(store.state.calendarState.days.length, 24,
        reason: 'keep successfully loaded holidays after a later failure');
    expect(session.requestedWeeks.length, 5);
  });

  test('visible week and year background scan share a pending request',
      () async {
    final session = _DelayedCalendar();
    await bootstrapTestEnvironment(
        wrapperOverride: session, fixedNow: UtcDateTime(2026, 10, 20));
    final store =
        createStore(initialState: _signedInState(), withMiddleware: true);
    final history = loadExportCalendarYear(
      state: () => store.state,
      onLoaded: store.actions.calendarActions.loaded.call,
      progressive: true,
    );
    await session.blocked.future;
    final visible = store.actions.calendarActions.load(toMonday(now));
    await Future<void>.delayed(Duration.zero);
    expect(session.requestedWeeks.length, 1);
    session.release.complete();
    await visible;
    expect(await history, isFalse);
    expect(session.requestedWeeks.length, 1);
  });

  test('dashboard finishes while calendar history is still waiting', () async {
    final session = _DelayedCalendar();
    await bootstrapTestEnvironment(
        wrapperOverride: session, fixedNow: UtcDateTime(2026, 10, 20));
    final store =
        createStore(initialState: _signedInState(), withMiddleware: true);
    await store.actions.dashboardActions
        .load(true)
        .timeout(const Duration(seconds: 3));
    await session.blocked.future.timeout(const Duration(seconds: 3));
    expect(store.state.dashboardState.loading, isFalse);
    expect(session.requestedWeeks.length, 1,
        reason: 'calendar should load without manually opening the timetable');
    session.release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(session.requestedWeeks.length, 1,
        reason: 'a failure must not trigger 25 more fallback requests');
  });

  test('switching accounts prevents a pending calendar response being applied',
      () async {
    final session = _DelayedCalendar();
    await bootstrapTestEnvironment(
        wrapperOverride: session, fixedNow: UtcDateTime(2026, 10, 20));
    final store = createStore(initialState: _signedInState());
    var active = true;
    var applied = 0;
    final pending = loadExportCalendarYear(
      state: () => store.state,
      onLoaded: (_) async => applied++,
      progressive: true,
      isActive: () => active,
    );
    await session.blocked.future;
    active = false;
    session.release.complete();
    expect(await pending, isFalse);
    expect(applied, 0);
  });
}
