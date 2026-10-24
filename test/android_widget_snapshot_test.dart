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

import 'package:built_collection/built_collection.dart';
import 'package:dr/android_widget_snapshot.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/app_state.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  setUp(() {
    mockNow = fixtureNow;
  });

  tearDown(() {
    mockNow = null;
  });

  test('ready snapshot omits account identifiers when cached data is empty',
      () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..url = 'https://school.example',
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.ready);
    expect(snapshot.meta.username, isNull);
    expect(snapshot.meta.server, isNull);
    expect(snapshot.dashboard.items, isEmpty);
    expect(snapshot.grades.overallAverage, isEmpty);
    expect(snapshot.grades.subjects, isEmpty);
    expect(snapshot.today.items, isEmpty);
  });

  test('marks snapshot as data saving disabled when noDataSaving is active',
      () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..settingsState.noDataSaving = true,
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(
      snapshot.meta.status,
      AndroidWidgetSnapshotStatus.dataSavingDisabled,
    );
  });

  test('marks snapshot as app locked when biometric lock is enabled', () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..settingsState.biometricAppLockEnabled = true,
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.appLocked);
  });

  test('marks snapshot as logged out when no authenticated user exists', () {
    final snapshot = buildAndroidWidgetSnapshot(AppState());

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.loggedOut);
    expect(snapshot.dashboard.items, isEmpty);
    expect(snapshot.grades.subjects, isEmpty);
    expect(snapshot.today.items, isEmpty);
  });

  AppState populatedState() {
    final today = fixtureNow.stripTime();
    return AppState((b) {
      b.loginState
        ..loggedIn = true
        ..username = 'private-user';
      b.gradesState
        ..semester = Semester.first.toBuilder()
        ..subjects = ListBuilder([
          buildSubject(name: 'Kunst'),
          buildSubject(name: 'Mathematik', gradesAll: {
            Semester.first: BuiltList([
              buildGradeAll(date: today, grade: 500, weightPercentage: 50),
              buildGradeAll(date: today, grade: 600, weightPercentage: 50),
              buildGradeAll(date: today, grade: 100, cancelled: true),
            ]),
          }),
          buildSubject(name: 'Deutsch', gradesAll: {
            Semester.first: BuiltList([buildGradeAll(date: today, grade: 800)]),
          }),
        ]);
      b.dashboardState.allDays = ListBuilder([
        buildDay(date: today.add(const Duration(days: 1)), homework: [
          buildHomework(
              id: 2, label: 'Mathematik', title: 'Test', warning: true),
        ]),
        buildDay(date: today, homework: [
          buildHomework(
              id: 1,
              label: 'Deutsch',
              title: '<b>Lesen</b>',
              subtitle: 'S. 5 &amp; 6'),
          buildHomework(id: 3, title: 'Erledigt', checked: true),
          buildHomework(id: 4, title: 'Gelöscht', deleted: true),
        ]),
        buildDay(date: today.subtract(const Duration(days: 1)), homework: [
          buildHomework(id: 5, title: 'Vergangen'),
        ]),
      ]);
      b.calendarState.days = MapBuilder({
        today: buildCalendarDay(date: today, hours: [
          buildCalendarHour(
              subject: 'Mathematik',
              fromHour: 2,
              toHour: 2,
              rooms: [
                'A2'
              ],
              timeSpans: [
                buildTimeSpan(
                    from: UtcDateTime(2026, 3, 28, 9),
                    to: UtcDateTime(2026, 3, 28, 9, 50))
              ]),
          buildCalendarHour(
              subject: 'Deutsch',
              fromHour: 1,
              toHour: 1,
              isDetectedSubstitute: true),
        ]),
      });
    });
  }

  test(
      'dashboard exports upcoming entries in date order without completed/deleted items',
      () {
    final snapshot = buildAndroidWidgetSnapshot(populatedState());
    expect(
        snapshot.dashboard.items.map((item) => item.title), ['Lesen', 'Test']);
    expect(snapshot.dashboard.items.map((item) => item.dayLabel),
        ['Heute', 'Morgen']);
    expect(snapshot.dashboard.items.first.subtitle, 'S. 5 & 6');
    expect(snapshot.dashboard.items.last.warning, isTrue);
  });

  test('grade averages use app weights, cancellations and ignored subjects',
      () {
    final state = populatedState().rebuild((b) {
      b.settingsState
        ..colorGrades = true
        ..ignoreForGradesAverage = ListBuilder(['deutsch']);
    });
    final snapshot = buildAndroidWidgetSnapshot(state);
    expect(
        snapshot.grades.overallAverage, appSelectors.allSubjectsAverage(state));
    expect(snapshot.grades.subjects.map((item) => item.average),
        ['5,50', '8,00', '—']);
    expect(snapshot.grades.subjects.first.category, 'satisfactory');
    expect(snapshot.grades.category, 'satisfactory');
    expect(snapshot.grades.subjects.last.category, isNull);
    final plain = buildAndroidWidgetSnapshot(
        state.rebuild((b) => b.settingsState.colorGrades = false));
    expect(plain.grades.category, isNull);
    expect(
        plain.grades.subjects.every((item) => item.category == null), isTrue);
  });

  test('today exports ordered lessons, times, rooms and substitutions', () {
    final snapshot = buildAndroidWidgetSnapshot(populatedState());
    expect(snapshot.today.items.map((item) => item.subject),
        ['Deutsch', 'Mathematik']);
    expect(snapshot.today.items.first.warning, isTrue);
    expect(snapshot.today.items.last.timeLabel, '09:00–09:50');
    expect(snapshot.today.items.last.roomLabel, 'A2');
  });

  test('loaded free day differs from missing timetable', () {
    final state = populatedState();
    final free = state.rebuild((b) =>
        b.calendarState.days[fixtureNow.stripTime()] =
            buildCalendarDay(date: fixtureNow.stripTime()));
    expect(buildAndroidWidgetSnapshot(free).today.emptyMessage,
        'Heute kein Unterricht');
    final unknown = state.rebuild((b) => b.calendarState.days.clear());
    expect(buildAndroidWidgetSnapshot(unknown).today.emptyMessage,
        contains('noch kein Stundenplan'));
  });

  test(
      'all populated widgets redact their data when privacy restrictions apply',
      () {
    final state = populatedState();
    for (final blocked in [
      state.rebuild((b) => b.loginState.loggedIn = false),
      state.rebuild((b) => b.settingsState.noDataSaving = true),
      state.rebuild((b) => b.settingsState.biometricAppLockEnabled = true),
    ]) {
      final snapshot = buildAndroidWidgetSnapshot(blocked);
      expect(snapshot.dashboard.items, isEmpty);
      expect(snapshot.today.items, isEmpty);
      expect(snapshot.grades.subjects, isEmpty);
      expect(snapshot.grades.overallAverage, isEmpty);
      expect(snapshot.meta.username, isNull);
    }
  });
}
