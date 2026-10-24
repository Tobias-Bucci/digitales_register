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
    expect(
        calculateGradeForecast(
          subjects: [
            _subject([700, 750, 800, 850], days: [10, 10, 20, 20])
          ],
          semester: Semester.first,
          ignoredSubjects: const [],
          now: DateTime(2026, 1, 1),
        ),
        isNull);
  });

  test('detects rising, falling, and stable trends', () {
    expect(_forecast([600, 700, 800, 900])!.trend, GradeForecastTrend.rising);
    expect(_forecast([900, 800, 700, 600])!.trend, GradeForecastTrend.falling);
    expect(_forecast([750, 750, 750, 750])!.trend, GradeForecastTrend.stable);
  });

  test('combines existing grades with the weighted recent performance estimate',
      () {
    // Four equally weighted grades 30 days apart: recent weights are
    // 1/8, 1/4, 1/2, 1, giving an expected future grade of 826 2/3.
    // 114 observed days and 180 remaining days give 180/114 times the
    // existing assessment weight for future grades.
    final result = _forecast([600, 700, 800, 900])!;
    expect(result.currentAverage, 750);
    expect(result.predictedAverage, closeTo(796.93877551, 0.00001));
  });

  test('a short downward trend cannot extrapolate good grades to 1.0', () {
    final result = calculateGradeForecast(
      subjects: [
        _subject([900, 800, 700, 600], days: [1, 2, 3, 4])
      ],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2025, 9, 5),
      schoolYearEnd: DateTime(2026, 6, 30),
    )!;
    expect(result.currentAverage, 750);
    expect(result.predictedAverage, inExclusiveRange(600, 750));
    expect(result.trend, GradeForecastTrend.falling);
  });

  test('a short upward trend cannot extrapolate to a perfect 10', () {
    final result = calculateGradeForecast(
      subjects: [
        _subject([600, 700, 800, 900], days: [1, 2, 3, 4])
      ],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2025, 9, 5),
    )!;
    expect(result.predictedAverage, inExclusiveRange(750, 900));
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

  test('subjects count equally regardless of their number of grades', () {
    final result = calculateGradeForecast(
      subjects: [
        _subject([600, 600, 600, 600]),
        buildSubject(name: 'Geschichte', gradesAll: {
          Semester.first: BuiltList([
            buildGradeAll(date: UtcDateTime(2025, 10, 10), grade: 1000),
          ]),
        }),
      ],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: DateTime(2026, 1, 1),
    )!;
    expect(result.currentAverage, 800);
    expect(result.predictedAverage, closeTo(800, 0.001));
  });

  test(
      'zero and negative weights, cancellation and excluded subjects do not count',
      () {
    final subject = _subject([750, 750, 750, 750]);
    final withInvalid = subject.rebuild((b) => b.gradesAll[Semester.first] =
        subject.gradesAll[Semester.first]!.rebuild((b) => b.addAll([
              buildGradeAll(
                  date: UtcDateTime(2025, 12, 10),
                  grade: 100,
                  weightPercentage: 0),
              buildGradeAll(
                  date: UtcDateTime(2025, 12, 11),
                  grade: 100,
                  weightPercentage: -100),
              buildGradeAll(
                  date: UtcDateTime(2025, 12, 12), grade: 100, cancelled: true),
            ])));
    final result = calculateGradeForecast(
      subjects: [withInvalid, subject.rebuild((b) => b.name = 'Sport')],
      semester: Semester.first,
      ignoredSubjects: const ['sPoRt'],
      now: DateTime(2026, 1, 1),
    )!;
    expect(result.gradeCount, 4);
    expect(result.distinctDates, 4);
    expect(result.currentAverage, 750);
    expect(result.predictedAverage, closeTo(750, 0.001));
  });

  test('at and after year end the forecast equals the current average', () {
    for (final asOf in [DateTime(2026, 6, 30), DateTime(2026, 7, 10)]) {
      final result = calculateGradeForecast(
        subjects: [
          _subject([900, 800, 700, 600])
        ],
        semester: Semester.first,
        ignoredSubjects: const [],
        now: asOf,
        schoolYearEnd: DateTime(2026, 6, 30),
      )!;
      expect(result.predictedAverage, result.currentAverage);
      expect(result.trend, GradeForecastTrend.stable);
      expect(result.changePerMonth, 0);
    }
  });
}
