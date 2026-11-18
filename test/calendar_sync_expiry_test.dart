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

// Past and ticked-off entries leave the device calendar (#138).

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 11, 18, 10));
    isAndroidOverride = () => true;
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 41;
    CalendarSyncService.getWritableCalendarsOverride =
        () async => const <CalendarSyncCalendar>[
              CalendarSyncCalendar(
                id: 41,
                displayName: 'School',
                accountName: 'school@example.com',
                ownerAccount: 'school@example.com',
                isPrimary: true,
              ),
            ];
  });

  tearDown(resetTestState);

  /// The reconcile a middleware starts in the background partly runs in the
  /// fake async zone of the widget test, so it needs frames to finish.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
  }

  AppState stateWith({
    List<Homework> homework = const <Homework>[],
    List<HomeworkExam> exams = const <HomeworkExam>[],
    bool loggedIn = false,
  }) {
    final date = UtcDateTime(2026, 11, 18);
    return AppState((b) {
      b.settingsState.calendarSyncEnabled = true;
      b.loginState.loggedIn = loggedIn;
      b.dashboardState.allDays = ListBuilder<Day>(<Day>[
        buildDay(date: date, homework: homework),
      ]);
      b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
        date: buildCalendarDay(
          date: date,
          hours: <CalendarHour>[
            buildCalendarHour(subject: 'Deutsch', homeworkExams: exams),
          ],
        ),
      });
    });
  }

  HomeworkExam exam() => buildHomeworkExam(
        id: 55,
        name: '1. Schularbeit',
        homework: false,
        typeName: 'Schularbeit',
        deadline: UtcDateTime(2026, 11, 18, 9),
      );

  Homework gradeGroup({bool checked = false}) => buildHomework(
        id: 91,
        title: 'Schularbeit',
        subtitle: '1. Schularbeit',
        label: 'Deutsch',
        type: HomeworkType.gradeGroup,
        checkable: true,
        checked: checked,
      );

  Homework reminder({bool checked = false}) => buildHomework(
        id: 7,
        title: 'Reminder',
        type: HomeworkType.homework,
        checkable: true,
        checked: checked,
      );

  test('an exam of yesterday is deleted at the next reconcile', () async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 500;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    final state = stateWith(exams: <HomeworkExam>[exam()]);

    expect(await CalendarSyncService.reconcile(state), isTrue);
    expect(deletedIds, isEmpty);

    // 19.11.: the same data, no load in between.
    mockNow = UtcDateTime(2026, 11, 19, 0, 0, 1);
    expect(await CalendarSyncService.reconcile(state), isTrue);

    expect(deletedIds, <int>[500]);
  });

  test('homework of yesterday is deleted when the day changes without a load',
      () async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 600;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    final state = stateWith(homework: <Homework>[reminder()]);

    await CalendarSyncService.reconcile(state);
    mockNow = UtcDateTime(2026, 11, 18, 23, 59);
    await CalendarSyncService.reconcile(state);
    expect(deletedIds, isEmpty, reason: 'still today');

    mockNow = UtcDateTime(2026, 11, 19, 7);
    await CalendarSyncService.reconcile(state);
    expect(deletedIds, <int>[600]);
  });

  test('checked homework is deleted and unchecked again is recreated',
      () async {
    final deletedIds = <int>[];
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 700 + upserts.length;
    };
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);

    await CalendarSyncService.reconcile(
        stateWith(homework: <Homework>[reminder()]));
    await CalendarSyncService.reconcile(
        stateWith(homework: <Homework>[reminder(checked: true)]));
    expect(deletedIds, <int>[701]);

    await CalendarSyncService.reconcile(
        stateWith(homework: <Homework>[reminder()]));
    expect(upserts, hasLength(2));
    expect(upserts.last.eventId, isNull);
  });

  test('an exam ticked off on the dashboard leaves the device calendar',
      () async {
    final deletedIds = <int>[];
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 800 + upserts.length;
    };
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);

    // The exam is synced once, from the calendar entry.
    await CalendarSyncService.reconcile(stateWith(
      homework: <Homework>[gradeGroup()],
      exams: <HomeworkExam>[exam()],
    ));
    expect(upserts, hasLength(1));
    expect(upserts.single.title, 'Schularbeit: Deutsch');

    await CalendarSyncService.reconcile(stateWith(
      homework: <Homework>[gradeGroup(checked: true)],
      exams: <HomeworkExam>[exam()],
    ));
    expect(deletedIds, <int>[801]);
    expect(upserts, hasLength(1));

    await CalendarSyncService.reconcile(stateWith(
      homework: <Homework>[gradeGroup()],
      exams: <HomeworkExam>[exam()],
    ));
    expect(upserts, hasLength(2));
    expect(upserts.last.title, 'Schularbeit: Deutsch');
  });

  test('events that are not tracked in the sync records are never deleted',
      () async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 900;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    // Events of the user or of other apps the calendar also contains.
    CalendarSyncService.findExistingEventsOverride =
        (calendarId, eventIds) async => <int>[...eventIds, 1, 2, 3];

    await CalendarSyncService.reconcile(
        stateWith(homework: <Homework>[reminder()]));
    mockNow = UtcDateTime(2026, 11, 25);
    await CalendarSyncService.reconcile(
        stateWith(homework: <Homework>[reminder()]));
    await CalendarSyncService.reconcile(stateWith());

    expect(deletedIds, <int>[900]);
  });

  test('a failed delete keeps the record and is retried next time', () async {
    final deleteAttempts = <int>[];
    var failDelete = true;
    CalendarSyncService.upsertEventOverride = (_) async => 950;
    CalendarSyncService.deleteEventOverride = (id) async {
      deleteAttempts.add(id);
      if (failDelete) {
        throw PlatformException(code: 'delete_failed');
      }
    };
    final state = stateWith(homework: <Homework>[reminder()]);

    await CalendarSyncService.reconcile(state);
    mockNow = UtcDateTime(2026, 11, 19);
    expect(await CalendarSyncService.reconcile(state), isFalse);
    expect(deleteAttempts, <int>[950]);

    failDelete = false;
    expect(await CalendarSyncService.reconcile(state), isTrue);
    expect(deleteAttempts, <int>[950, 950]);

    expect(await CalendarSyncService.reconcile(state), isTrue);
    expect(deleteAttempts, <int>[950, 950], reason: 'record is gone');
  });

  testWidgets('the day watch fires once the calendar day has changed',
      (tester) async {
    final fired = <UtcDateTime>[];
    mockNow = UtcDateTime(2026, 11, 18, 23, 59);
    CalendarSyncService.watchDayChange(() => fired.add(now));

    await tester.pump(const Duration(seconds: 50));
    expect(fired, isEmpty);

    mockNow = UtcDateTime(2026, 11, 19, 0, 0, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(fired, <UtcDateTime>[UtcDateTime(2026, 11, 19, 0, 0, 1)]);
    CalendarSyncService.stopDayChangeWatch();
  });

  testWidgets('returning to the app removes expired events without a load',
      (tester) async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 1000;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    final mockWrapper = MockWrapper();
    when(() => mockWrapper.noInternet).thenReturn(false);
    when(() => mockWrapper.url).thenReturn('https://example.com');
    when(() => mockWrapper.user).thenReturn('user');
    when(() => mockWrapper.lastInteraction).thenReturn(DateTime.now());
    wrapper = mockWrapper;

    final store = createStore(
      initialState: stateWith(
        homework: <Homework>[reminder()],
        loggedIn: true,
      ),
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: const Scaffold());

    await tester.runAsync(() async {
      await CalendarSyncService.reconcile(store.state);
      mockNow = UtcDateTime(2026, 11, 19, 8);
      await store.actions.restarted();
    });
    await pumpUntil(tester, () => deletedIds.isNotEmpty);

    expect(deletedIds, <int>[1000]);
  });

  testWidgets('ticking off an exam removes its event right away',
      (tester) async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 1100;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    final mockWrapper = MockWrapper();
    when(() => mockWrapper.noInternet).thenReturn(false);
    when(
      () => mockWrapper.send(
        'api/student/dashboard/toggle_reminder',
        args: any(named: 'args'),
      ),
    ).thenAnswer((_) async => <String, Object>{'success': true});
    wrapper = mockWrapper;

    final store = createStore(
      initialState: stateWith(
        homework: <Homework>[gradeGroup()],
        exams: <HomeworkExam>[exam()],
      ),
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: const Scaffold());

    await tester.runAsync(() async {
      await CalendarSyncService.reconcile(store.state);
      await store.actions.dashboardActions.toggleDone(
        ToggleDonePayload(
          (b) => b
            ..homeworkId = 91
            ..type = HomeworkType.gradeGroup.name
            ..done = true,
        ),
      );
    });
    await pumpUntil(tester, () => deletedIds.isNotEmpty);

    expect(deletedIds, <int>[1100]);
  });

  testWidgets('a failed toggle on the server keeps the event', (tester) async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 1200;
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
    final mockWrapper = MockWrapper();
    when(() => mockWrapper.noInternet).thenReturn(false);
    when(
      () => mockWrapper.send(
        'api/student/dashboard/toggle_reminder',
        args: any(named: 'args'),
      ),
    ).thenAnswer((_) async => <String, Object>{'success': false});
    wrapper = mockWrapper;

    final store = createStore(
      initialState: stateWith(homework: <Homework>[reminder()]),
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: const Scaffold());

    await tester.runAsync(() async {
      await CalendarSyncService.reconcile(store.state);
      await store.actions.dashboardActions.toggleDone(
        ToggleDonePayload(
          (b) => b
            ..homeworkId = 7
            ..type = HomeworkType.homework.name
            ..done = true,
        ),
      );
      // Waits for the reconcile the toggle started.
      await CalendarSyncService.reconcile(store.state);
    });
    await tester.pump(const Duration(seconds: 5));

    expect(
      store.state.dashboardState.allDays!.single.homework.single.checked,
      isFalse,
    );
    expect(deletedIds, isEmpty);
  });
}
