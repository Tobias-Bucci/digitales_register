import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

enum GradeForecastTrend { rising, falling, stable }

class GradeForecast {
  const GradeForecast({
    required this.currentAverage,
    required this.predictedAverage,
    required this.trend,
    required this.changePerMonth,
    required this.gradeCount,
    required this.distinctDates,
    required this.asOf,
    required this.schoolYearEnd,
  });

  final double currentAverage;
  final double predictedAverage;
  final GradeForecastTrend trend;
  final double changePerMonth;
  final int gradeCount;
  final int distinctDates;
  final DateTime asOf;
  final DateTime schoolYearEnd;

  bool get isReliable => gradeCount >= 4 && distinctDates >= 3;
}

/// Calculates a forecast from cumulative, weighted averages over time.
/// Several grades on one day are combined into one observation, so that a
/// test-heavy day does not get extra influence merely because it has entries.
GradeForecast? calculateGradeForecast({
  required Iterable<Subject> subjects,
  required Semester semester,
  required Iterable<String> ignoredSubjects,
  DateTime? now,
  DateTime? schoolYearEnd,
}) {
  final asOf = _dateOnly(now ?? appClock.now);
  final schoolYearStart = appClock.isDemoMode
      ? AppClock.demoSchoolYearStart
      : (asOf.month >= 8 ? DateTime(asOf.year, 9) : DateTime(asOf.year - 1, 9));
  final end = schoolYearEnd ??
      (appClock.isDemoMode ? AppClock.demoSchoolYearEnd : _schoolYearEnd(asOf));
  final ignored = ignoredSubjects.map((s) => s.toLowerCase()).toSet();
  final grades = <GradeAll>[];
  for (final subject in subjects) {
    if (ignored.contains(subject.name.toLowerCase())) continue;
    for (final grade in subject.basicGrades(semester) ?? const <GradeAll>[]) {
      if (grade.grade != null &&
          !grade.cancelled &&
          !grade.date.isBefore(schoolYearStart) &&
          !grade.date.isAfter(asOf)) {
        grades.add(grade);
      }
    }
  }
  if (grades.isEmpty) return null;
  grades.sort((a, b) => a.date.compareTo(b.date));

  final byDay = <DateTime, List<GradeAll>>{};
  for (final grade in grades) {
    final day = DateTime(grade.date.year, grade.date.month, grade.date.day);
    byDay.putIfAbsent(day, () => <GradeAll>[]).add(grade);
  }
  if (grades.length < 4 || byDay.length < 3) return null;

  final observations = <_Observation>[];
  var sum = 0;
  var weight = 0;
  for (final entry in byDay.entries) {
    for (final grade in entry.value) {
      final gradeWeight =
          grade.weightPercentage > 0 ? grade.weightPercentage : 1;
      sum += grade.grade! * gradeWeight;
      weight += gradeWeight;
    }
    observations.add(_Observation(
      entry.key,
      sum / weight,
    ));
  }
  final first = observations.first.date;
  final xs = observations
      .map((o) => o.date.difference(first).inDays.toDouble())
      .toList();
  final ys = observations.map((o) => o.average).toList();
  final xMean = xs.reduce((a, b) => a + b) / xs.length;
  final yMean = ys.reduce((a, b) => a + b) / ys.length;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < xs.length; i++) {
    numerator += (xs[i] - xMean) * (ys[i] - yMean);
    denominator += (xs[i] - xMean) * (xs[i] - xMean);
  }
  if (denominator == 0) return null;
  final slope = numerator / denominator;
  final intercept = yMean - slope * xMean;
  final endX = end.difference(first).inDays.toDouble();
  final prediction = (intercept + slope * endX).clamp(100.0, 1000.0);
  return GradeForecast(
    currentAverage: sum / weight,
    predictedAverage: prediction,
    trend: slope > 0.002
        ? GradeForecastTrend.rising
        : slope < -0.002
            ? GradeForecastTrend.falling
            : GradeForecastTrend.stable,
    changePerMonth: slope * 30,
    gradeCount: grades.length,
    distinctDates: byDay.length,
    asOf: asOf,
    schoolYearEnd: end,
  );
}

class _Observation {
  const _Observation(this.date, this.average);
  final DateTime date;
  final double average;
}

DateTime _schoolYearEnd(DateTime date) => date.month >= 8
    ? DateTime(date.year + 1, 6, 30)
    : DateTime(date.year, 6, 30);

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
