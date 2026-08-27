// Copyright (C) 2026 Tobias Bucci

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  test('normal users always receive the real date', () async {
    await appClock.initialize();
    final before = DateTime.now();
    final value = appClock.now;
    final after = DateTime.now();

    expect(value.isBefore(before), isFalse);
    expect(value.isAfter(after), isFalse);
    expect(appClock.isDemoMode, isFalse);
    expect(
      () => appClock.setSimulatedDate(DateTime(2025, 10, 10)),
      throwsStateError,
    );
  });

  test('demo date changes, persists, resets and stays inside the school year',
      () async {
    appClock.setDemoMode(true);
    await appClock.setSimulatedDate(DateTime(2025, 10, 10));

    expect(_dateOnly(appClock.now), DateTime(2025, 10, 10));
    expect(appClock.selectedDemoDate, DateTime(2025, 10, 10));

    appClock.resetForTest();
    await appClock.initialize();
    appClock.setDemoMode(true);
    expect(_dateOnly(appClock.now), DateTime(2025, 10, 10));

    expect(
      () => appClock.setSimulatedDate(DateTime(2026, 8, 27)),
      throwsRangeError,
    );

    await appClock.resetSimulatedDate();
    expect(appClock.selectedDemoDate, isNull);
    expect(_dateOnly(appClock.now), AppClock.defaultDemoDate);
  });

  test('past and future dashboard entries follow the simulated date', () async {
    appClock.setDemoMode(true);
    await appClock.setSimulatedDate(DateTime(2025, 10, 10));
    final state = AppState(
      (b) => b.dashboardState
        ..future = true
        ..allDays = ListBuilder<Day>([
          _day(2025, 10, 9),
          _day(2025, 10, 10),
          _day(2025, 10, 11),
        ]),
    );

    expect(
      appSelectors.dashboardDays(state).map((day) => day.date.day),
      <int>[10, 11],
    );
    expect(Day.format(UtcDateTime(2025, 10, 10)), 'Heute');

    final pastState = state.rebuild((b) => b.dashboardState.future = false);
    expect(
      appSelectors.dashboardDays(pastState).map((day) => day.date.day),
      <int>[9],
    );
  });

  testWidgets('calendar marks the simulated date as today', (tester) async {
    appClock.setDemoMode(true);
    await appClock.setSimulatedDate(DateTime(2025, 10, 10));
    final day = CalendarDay(
      (b) => b
        ..date = UtcDateTime(2025, 10, 10)
        ..hours = ListBuilder<CalendarHour>(),
    );
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: SizedBox(
          width: 220,
          height: 400,
          child: CalendarDayWidget(
            max: 0,
            calendarDay: day,
            subjectNicks: BuiltMap<String, String>(),
            isSelected: false,
            selectedHour: null,
            colorBackground: false,
            subjectThemes: BuiltMap<String, SubjectTheme>(),
            showNoFavoriteSubject: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('calendar-today-indicator')), findsOneWidget);
  });
}

Day _day(int year, int month, int day) => Day(
      (b) => b
        ..date = UtcDateTime(year, month, day)
        ..homework = ListBuilder<Homework>(),
    );

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
