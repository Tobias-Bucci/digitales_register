import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_average.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/grade_statistics.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

GradeAll _grade(int value, int weight, int day, {bool cancelled = false}) =>
    buildGradeAll(
      date: UtcDateTime(2025, 10, day),
      grade: value,
      weightPercentage: weight,
      cancelled: cancelled,
    );

Subject _subject(List<GradeAll> current) => buildSubject(
      name: 'Mathematik',
      gradesAll: <Semester, BuiltList<GradeAll>>{
        Semester.first: BuiltList<GradeAll>(current),
        Semester.second: BuiltList<GradeAll>([
          buildGradeAll(
              date: UtcDateTime(2026, 2, 2), grade: 600, weightPercentage: 100),
        ]),
      },
    );

final _now = DateTime(2025, 11, 1);

/// The current first-semester average as each feature computes it.
({int? canonical, double? statistics, double? history, double? forecast})
    _averages(Subject subject) {
  final statistics = calculateGradeStatistics(
    subjects: [subject],
    semester: Semester.first,
    ignoredSubjects: const [],
    now: _now,
  ).subjectAverages;
  final history = compareGradeSemesters(
    subjects: [subject],
    currentSemester: Semester.first,
    previousSemester: Semester.second,
    ignoredSubjects: const [],
    now: DateTime(2026, 3, 1),
  );
  final forecast = calculateGradeForecast(
    subjects: [subject],
    semester: Semester.first,
    ignoredSubjects: const [],
    now: _now,
    schoolYearEnd: DateTime(2026, 6, 30),
  );
  return (
    canonical: subject.average(Semester.first),
    statistics: statistics.isEmpty ? null : statistics.single.average,
    history: history?.subjects.singleOrNull?.current,
    forecast: forecast?.currentAverage,
  );
}

void main() {
  test('one 4.00/100 % and three 10.00/0 % grades average 4.00 everywhere', () {
    final averages = _averages(_subject([
      _grade(400, 100, 1),
      _grade(1000, 0, 2),
      _grade(1000, 0, 3),
      _grade(1000, 0, 4),
    ]));
    expect(averages.canonical, 400);
    expect(averages.statistics, 400);
    expect(averages.history, 400);
    // Only one grade counts, which is too little for a forecast.
    expect(averages.forecast, isNull);
  });

  test('zero, negative and cancelled grades are excluded consistently', () {
    final subject = _subject([
      _grade(400, 100, 1),
      _grade(600, 50, 8),
      _grade(700, 100, 15),
      _grade(500, 25, 22),
      _grade(1000, 0, 8),
      _grade(1000, 0, 29),
      _grade(1000, -100, 15),
      _grade(1000, 100, 22, cancelled: true),
    ]);
    // (400·100 + 600·50 + 700·100 + 500·25) / 275 = 554.54… → 555.
    final averages = _averages(subject);
    expect(averages.canonical, 555);
    expect(averages.statistics, 555);
    expect(averages.history, 555);
    expect(averages.forecast, 555);

    final forecast = calculateGradeForecast(
      subjects: [subject],
      semester: Semester.first,
      ignoredSubjects: const [],
      now: _now,
      schoolYearEnd: DateTime(2026, 6, 30),
    )!;
    expect(forecast.gradeCount, 4);
    expect(forecast.distinctDates, 4);
  });

  test('a subject whose grades all weigh 0 % has no average anywhere', () {
    final averages = _averages(_subject([
      _grade(600, 0, 1),
      _grade(700, 0, 8),
      _grade(800, 0, 15),
      _grade(900, 0, 22),
    ]));
    expect(averages.canonical, isNull);
    expect(averages.statistics, isNull);
    expect(averages.history, isNull);
    expect(averages.forecast, isNull);
  });

  test('all features share the hundredth rounding of the subject average', () {
    // 6.9375 rounds half up to 6.94; derived features no longer keep 693.75.
    final averages = _averages(_subject([
      _grade(600, 1, 1),
      _grade(700, 15, 2),
    ]));
    expect(averages.canonical, 694);
    expect(averages.statistics, 694);
    expect(averages.history, 694);
  });

  test('countsTowardAverage only accepts numeric uncancelled positive weights',
      () {
    expect(countsTowardAverage(_grade(700, 100, 1)), isTrue);
    expect(countsTowardAverage(_grade(700, 1, 1)), isTrue);
    expect(countsTowardAverage(_grade(700, 0, 1)), isFalse);
    expect(countsTowardAverage(_grade(700, -50, 1)), isFalse);
    expect(countsTowardAverage(_grade(700, 100, 1, cancelled: true)), isFalse);
    expect(
        countsTowardAverage(GradeAll((b) => b
          ..date = UtcDateTime(2025, 10, 1)
          ..type = 'Test'
          ..weightPercentage = 100
          ..cancelled = false)),
        isFalse);
    expect(weightedGradeAverage(const []), isNull);
  });
}
