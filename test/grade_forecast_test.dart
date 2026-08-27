import 'package:built_collection/built_collection.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/app_state.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

Subject _subject(List<int> values, {List<int>? days}) {
  final dates = days ?? <int>[10, 40, 70, 100];
  return buildSubject(
    name: 'Mathematik',
    gradesAll: <Semester, BuiltList<GradeAll>>{
      Semester.first: BuiltList<GradeAll>([
        for (var i = 0; i < values.length; i++)
          buildGradeAll(
            date: UtcDateTime(2025, 9, dates[i]),
            grade: values[i],
          ),
      ]),
    },
  );
}

GradeForecast? _forecast(List<int> values) => calculateGradeForecast(
      subjects: [_subject(values)],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2026, 1, 1),
      schoolYearEnd: DateTime(2026, 6, 30),
    );

void main() {
  test('requires enough grades and distinct dates', () {
    expect(_forecast([700, 750, 800]), isNull);
    expect(_forecast([700, 750, 800, 850]), isNotNull);
  });

  test('detects rising, falling, and stable trends', () {
    expect(_forecast([600, 700, 800, 900])!.trend, GradeForecastTrend.rising);
    expect(_forecast([900, 800, 700, 600])!.trend, GradeForecastTrend.falling);
    expect(_forecast([750, 750, 750, 750])!.trend, GradeForecastTrend.stable);
  });

  test('filters future grades and respects weights', () {
    final subject = buildSubject(
      name: 'Mathematik',
      gradesAll: <Semester, BuiltList<GradeAll>>{
        Semester.first: BuiltList<GradeAll>([
          buildGradeAll(date: UtcDateTime(2025, 9, 10), grade: 600),
          buildGradeAll(
              date: UtcDateTime(2025, 9, 20),
              grade: 800,
              weightPercentage: 200),
          buildGradeAll(date: UtcDateTime(2025, 10, 1), grade: 1000),
          buildGradeAll(date: UtcDateTime(2025, 10, 5), grade: 1000),
          buildGradeAll(date: UtcDateTime(2025, 10, 20), grade: 1000),
          buildGradeAll(date: UtcDateTime(2025, 12, 1), grade: 1000),
        ]),
      },
    );
    final result = calculateGradeForecast(
      subjects: [subject],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2025, 10, 10),
      schoolYearEnd: DateTime(2026, 6, 30),
    )!;
    expect(result.gradeCount, 4);
    expect(result.currentAverage, closeTo(840, 0.01));
  });
}
