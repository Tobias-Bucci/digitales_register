import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractAllSubjects combines calendar, grades, and dashboard subjects', () {
    final state = AppState(
      (b) {
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>(
          <UtcDateTime, CalendarDay>{
            UtcDateTime(2026, 3, 28): CalendarDay(
              (b) => b
                ..date = UtcDateTime(2026, 3, 28)
                ..hours = ListBuilder<CalendarHour>(<CalendarHour>[
                  CalendarHour(
                    (b) => b
                      ..subject = 'Mathematik'
                      ..fromHour = 1
                      ..toHour = 1
                      ..rooms = ListBuilder<String>()
                      ..teachers = ListBuilder<Teacher>()
                      ..timeSpans = ListBuilder<TimeSpan>()
                      ..homeworkExams = ListBuilder<HomeworkExam>()
                      ..lessonContents = ListBuilder<LessonContent>(),
                  ),
                ])
                ..lastFetched = UtcDateTime(2026, 3, 28),
            ),
          },
        );
        b.gradesState.subjects = ListBuilder<Subject>(<Subject>[
          Subject(
            (b) => b
              ..name = 'Deutsch'
              ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>()
              ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
              ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
          ),
          Subject(
            (b) => b
              ..name = 'Mathematik'
              ..gradesAll = MapBuilder<Semester, BuiltList<GradeAll>>()
              ..grades = MapBuilder<Semester, BuiltList<GradeDetail>>()
              ..observations = MapBuilder<Semester, BuiltList<Observation>>(),
          ),
        ]);
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          Day(
            (b) => b
              ..date = UtcDateTime(2026, 3, 28)
              ..lastRequested = UtcDateTime(2026, 3, 28)
              ..deletedHomework = ListBuilder<Homework>()
              ..homework = ListBuilder<Homework>(<Homework>[
                Homework(
                  (b) => b
                    ..id = 1
                    ..title = 'Arbeitsblatt'
                    ..subtitle = 'S. 10'
                    ..label = 'Biologie'
                    ..type = HomeworkType.lessonHomework
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
        ]);
      },
    );

    expect(
      state.extractAllSubjects(),
      unorderedEquals(const <String>['Mathematik', 'Deutsch', 'Biologie']),
    );
  });

  test('extractAllSubjects caches the computed subject list per state instance', () {
    final state = AppState();

    final first = state.extractAllSubjects();
    final second = state.extractAllSubjects();

    expect(identical(first, second), isTrue);
  });
}
