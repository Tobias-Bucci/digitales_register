// Copyright (C) 2026 Tobias Bucci

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    mockNow = UtcDateTime(2026, 3, 28);
  });

  tearDown(() {
    mockNow = null;
  });

  test('dashboardDays filters by future flag and blacklist', () {
    final state = AppState(
      (b) {
        b.dashboardState
          ..future = false
          ..blacklist = ListBuilder<HomeworkType>(<HomeworkType>[
            HomeworkType.homework,
            HomeworkType.gradeGroup,
          ])
          ..allDays = ListBuilder<Day>(<Day>[
            Day(
              (b) => b
                ..date = UtcDateTime(2026, 3, 27)
                ..lastRequested = UtcDateTime(2026, 3, 28)
                ..deletedHomework = ListBuilder<Homework>()
                ..homework = ListBuilder<Homework>(<Homework>[
                  Homework(
                    (b) => b
                      ..id = 1
                      ..title = 'Hausaufgabe'
                      ..subtitle = 'Deutsch'
                      ..type = HomeworkType.lessonHomework
                      ..checkable = false
                      ..checked = false
                      ..deleteable = false
                      ..deleted = false
                      ..warning = false
                      ..firstSeen = UtcDateTime(2026, 3, 28)
                      ..lastNotSeen = UtcDateTime(2026, 3, 28),
                  ),
                  Homework(
                    (b) => b
                      ..id = 2
                      ..title = 'Erinnerung'
                      ..subtitle = 'Nicht sichtbar'
                      ..type = HomeworkType.homework
                      ..checkable = false
                      ..checked = false
                      ..deleteable = false
                      ..deleted = false
                      ..warning = false
                      ..firstSeen = UtcDateTime(2026, 3, 28)
                      ..lastNotSeen = UtcDateTime(2026, 3, 28),
                  ),
                ]),
            ),
            Day(
              (b) => b
                ..date = UtcDateTime(2026, 3, 29)
                ..lastRequested = UtcDateTime(2026, 3, 28)
                ..deletedHomework = ListBuilder<Homework>()
                ..homework = ListBuilder<Homework>(),
            ),
          ]);
      },
    );

    final days = appSelectors.dashboardDays(state);

    expect(days, hasLength(1));
    expect(days.single.homework, hasLength(1));
    expect(days.single.homework.single.title, 'Hausaufgabe');
  });

  test('allSubjectsAverage ignores configured subjects case-insensitively', () {
    final state = AppState(
      (b) {
        b.gradesState
          ..semester = Semester.first.toBuilder()
          ..subjects = ListBuilder<Subject>(<Subject>[
            Subject(
              (b) => b
                ..name = 'Deutsch'
                ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>(
                  <Semester, BuiltList<GradeAll>>{
                    Semester.first: BuiltList<GradeAll>(<GradeAll>[
                      GradeAll(
                        (b) => b
                          ..grade = 800
                          ..weightPercentage = 100
                          ..date = UtcDateTime(2026, 3, 28)
                          ..cancelled = false
                          ..type = 'Schularbeit',
                      ),
                    ]),
                  },
                )
                ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
                ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
            ),
            Subject(
              (b) => b
                ..name = 'Mathematik'
                ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>(
                  <Semester, BuiltList<GradeAll>>{
                    Semester.first: BuiltList<GradeAll>(<GradeAll>[
                      GradeAll(
                        (b) => b
                          ..grade = 600
                          ..weightPercentage = 100
                          ..date = UtcDateTime(2026, 3, 28)
                          ..cancelled = false
                          ..type = 'Test',
                      ),
                    ]),
                  },
                )
                ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
                ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
            ),
          ]);
        b.settingsState.ignoreForGradesAverage =
            ListBuilder<String>(<String>['deutsch']);
      },
    );

    expect(appSelectors.allSubjectsAverage(state), '6,00');
  });

  test('hasGradesData respects the selected semester', () {
    final state = AppState(
      (b) => b.gradesState
        ..semester = Semester.second.toBuilder()
        ..subjects = ListBuilder<Subject>(<Subject>[
          Subject(
            (b) => b
              ..name = 'Deutsch'
              ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>(
                <Semester, BuiltList<GradeAll>>{
                  Semester.first: BuiltList<GradeAll>(<GradeAll>[
                    GradeAll(
                      (b) => b
                        ..grade = 800
                        ..weightPercentage = 100
                        ..date = UtcDateTime(2026, 3, 28)
                        ..cancelled = false
                        ..type = 'Schularbeit',
                    ),
                  ]),
                },
              )
              ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
              ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
          ),
        ]),
    );

    expect(appSelectors.hasGradesData(state), isFalse);
    expect(
      appSelectors.hasGradesData(
        state.rebuild((b) => b.gradesState.semester = Semester.all.toBuilder()),
      ),
      isTrue,
    );
  });

  test(
      'chartGraphs exclude cancelled and null grades and preserve subject theme',
      () {
    final state = AppState(
      (b) {
        b.gradesState
          ..semester = Semester.first.toBuilder()
          ..subjects = ListBuilder<Subject>(<Subject>[
            Subject(
              (b) => b
                ..name = 'Deutsch'
                ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>(
                  <Semester, BuiltList<GradeAll>>{
                    Semester.first: BuiltList<GradeAll>(<GradeAll>[
                      GradeAll(
                        (b) => b
                          ..grade = 725
                          ..weightPercentage = 100
                          ..date = UtcDateTime(2026, 3, 28)
                          ..cancelled = false
                          ..type = 'Schularbeit',
                      ),
                      GradeAll(
                        (b) => b
                          ..grade = null
                          ..weightPercentage = 100
                          ..date = UtcDateTime(2026, 3, 29)
                          ..cancelled = false
                          ..type = 'Mitarbeit',
                      ),
                      GradeAll(
                        (b) => b
                          ..grade = 500
                          ..weightPercentage = 100
                          ..date = UtcDateTime(2026, 3, 30)
                          ..cancelled = true
                          ..type = 'Test',
                      ),
                    ]),
                  },
                )
                ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
                ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
            ),
          ]);
        b.settingsState.subjectThemes = MapBuilder<String, SubjectTheme>(
          <String, SubjectTheme>{
            'Deutsch': SubjectTheme(
              (b) => b
                ..color = Colors.red.toARGB32()
                ..thick = 3,
            ),
          },
        );
      },
    );

    final chartGraphs = appSelectors.chartGraphs(state);

    expect(chartGraphs, hasLength(1));
    final subjectGrades = chartGraphs.keys.single;
    expect(subjectGrades.name, 'Deutsch');
    expect(subjectGrades.grades, hasLength(1));
    expect(chartGraphs.values.single.thick, 3);
  });

  test(
      'absenceStatistics converts lessons into monthly history and sorts ascending',
      () {
    final state = AppState(
      (b) => b.absencesState
        ..statistic = AbsenceStatisticBuilder()
        ..absences = ListBuilder<AbsenceGroup>(<AbsenceGroup>[
          AbsenceGroup(
            (b) => b
              ..justified = AbsenceJustified.justified
              ..hours = 0
              ..minutes = 0
              ..absences = ListBuilder<Absence>(<Absence>[
                Absence(
                  (b) => b
                    ..date = UtcDateTime(2026, 3, 12)
                    ..hour = 2
                    ..minutes = 10
                    ..minutesCameTooLate = 10
                    ..minutesLeftTooEarly = 0,
                ),
                Absence(
                  (b) => b
                    ..date = UtcDateTime(2026, 3, 13)
                    ..hour = 3
                    ..minutes = 50
                    ..minutesCameTooLate = 0
                    ..minutesLeftTooEarly = 0,
                ),
              ]),
          ),
          AbsenceGroup(
            (b) => b
              ..justified = AbsenceJustified.notJustified
              ..hours = 0
              ..minutes = 0
              ..absences = ListBuilder<Absence>(<Absence>[
                Absence(
                  (b) => b
                    ..date = UtcDateTime(2026, 1, 8)
                    ..hour = 1
                    ..minutes = 25
                    ..minutesCameTooLate = 10
                    ..minutesLeftTooEarly = 15,
                ),
              ]),
          ),
        ]),
    );

    final stats = appSelectors.absenceStatistics(state.absencesState);

    expect(stats.monthlyHistory, hasLength(2));
    expect(stats.monthlyHistory[0].month, UtcDateTime(2026));
    expect(stats.monthlyHistory[0].lessons, closeTo(0.5, 0.0001));
    expect(stats.monthlyHistory[1].month, UtcDateTime(2026, 3));
    expect(stats.monthlyHistory[1].lessons, closeTo(1.2, 0.0001));
  });

  test('absenceStatistics ignore future absences for history aggregation', () {
    final state = AppState(
      (b) => b.absencesState
        ..statistic = AbsenceStatisticBuilder()
        ..absences = ListBuilder<AbsenceGroup>(<AbsenceGroup>[
          AbsenceGroup(
            (b) => b
              ..justified = AbsenceJustified.justified
              ..hours = 0
              ..minutes = 0
              ..absences = ListBuilder<Absence>(<Absence>[
                Absence(
                  (b) => b
                    ..date = UtcDateTime(2026, 2, 12)
                    ..hour = 2
                    ..minutes = 50
                    ..minutesCameTooLate = 0
                    ..minutesLeftTooEarly = 0,
                ),
              ]),
          ),
        ])
        ..futureAbsences = ListBuilder<FutureAbsence>(<FutureAbsence>[
          FutureAbsence(
            (b) => b
              ..justified = AbsenceJustified.notYetJustified
              ..startDate = UtcDateTime(2026, 5, 2)
              ..endDate = UtcDateTime(2026, 5, 2)
              ..startHour = 1
              ..endHour = 4,
          ),
        ]),
    );

    final stats = appSelectors.absenceStatistics(state.absencesState);

    expect(stats.monthlyHistory, hasLength(1));
    expect(stats.monthlyHistory.single.month, UtcDateTime(2026, 2));
    expect(stats.monthlyHistory.single.lessons, closeTo(1, 0.0001));
  });
}
