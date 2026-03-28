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

  test('chartGraphs exclude cancelled and null grades and preserve subject theme', () {
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
}
