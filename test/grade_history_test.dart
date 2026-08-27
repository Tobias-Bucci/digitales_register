import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

Subject _subject(String name, List<GradeAll> first, List<GradeAll> second) =>
    buildSubject(
      name: name,
      gradesAll: <Semester, BuiltList<GradeAll>>{
        Semester.first: BuiltList<GradeAll>(first),
        Semester.second: BuiltList<GradeAll>(second),
      },
    );

GradeAll _grade(int value, int day, {int weight = 100}) => buildGradeAll(
      date: UtcDateTime(2026, 1, day),
      grade: value,
      weightPercentage: weight,
    );

void main() {
  test('compares semester averages and shared subjects', () {
    final result = compareGradeSemesters(
      subjects: [
        _subject('Mathematik', [_grade(700, 2)], [_grade(850, 3)]),
        _subject('Deutsch', [_grade(800, 4)], [_grade(600, 5)]),
        buildSubject(name: 'Nur aktuell', gradesAll: {
          Semester.second: BuiltList([_grade(900, 6)]),
        }),
      ],
      currentSemester: Semester.second,
      previousSemester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2026, 2, 1),
    );

    expect(result, isNotNull);
    expect(result!.currentAverage, closeTo(783.33, 0.01));
    expect(result.previousAverage, closeTo(750, 0.01));
    expect(result.change, closeTo(33.33, 0.01));
    expect(result.subjects.map((s) => s.subject), ['Deutsch', 'Mathematik']);
  });

  test('does not include future demo or normal-date grades', () {
    final result = compareGradeSemesters(
      subjects: [
        _subject(
            'Mathematik', [_grade(700, 2)], [_grade(900, 3), _grade(1000, 20)]),
      ],
      currentSemester: Semester.second,
      previousSemester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2026, 1, 10),
    );
    expect(result!.currentAverage, 900);
  });

  test('returns null without historical data', () {
    expect(
      compareGradeSemesters(
        subjects: [buildSubject(name: 'Mathematik')],
        currentSemester: Semester.second,
        previousSemester: Semester.first,
        ignoredSubjects: const [],
      ),
      isNull,
    );
  });
}
