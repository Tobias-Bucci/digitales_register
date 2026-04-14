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
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
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

  test('builds ready snapshot with dashboard, grades and today data', () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..url = 'https://school.example'
        ..dashboardState.future = true
        ..dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: fixtureNow,
            homework: <Homework>[
              buildHomework(
                title: 'Arbeitsblatt',
                subtitle: 'Seite 12',
                label: 'Mathematik',
                warning: true,
              ),
            ],
          ),
        ])
        ..gradesState.semester = Semester.first.toBuilder()
        ..gradesState.subjects = ListBuilder<Subject>(<Subject>[
          buildSubject(
            name: 'Mathematik',
            gradesAll: <Semester, BuiltList<GradeAll>>{
              Semester.first: BuiltList<GradeAll>(<GradeAll>[
                buildGradeAll(
                  date: UtcDateTime(2026, 3, 27),
                  grade: 875,
                ),
              ]),
            },
          ),
        ])
        ..calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 3, 28): buildCalendarDay(
            date: UtcDateTime(2026, 3, 28),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Mathematik',
                toHour: 2,
                rooms: const <String>['A101'],
              ),
            ],
          ),
        })
        ..settingsState.subjectNicks = MapBuilder<String, String>(
            {...defaultSubjectNicks, 'Mathematik': 'Mat'}),
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.ready);
    expect(snapshot.dashboard.items, hasLength(1));
    expect(snapshot.dashboard.items.single.subject, 'Mat');
    expect(snapshot.grades.overallAverage, '8,75');
    expect(snapshot.grades.subjects.single.average, '8,75');
    expect(snapshot.today.items.single.subject, 'Mat');
    expect(snapshot.today.items.single.roomLabel, 'A101');
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
}
