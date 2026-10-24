import 'dart:math' as math;

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_average.dart';

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

/// Estimates each subject's future grades from its recency-weighted results
/// (30-day half-life), then combines them with grades already earned at the
/// observed assessment rate. Subjects contribute equally to the overall mean.
/// This keeps predictions within demonstrated performance instead of extending
/// a short cumulative-average slope unboundedly across the school year.
GradeForecast? calculateGradeForecast({
  required Iterable<Subject> subjects,
  required Semester semester,
  required Iterable<String> ignoredSubjects,
  DateTime? now,
  DateTime? schoolYearEnd,
}) {
  final asOf = calendarDate(now ?? appClock.now);
  final schoolYearStart = appClock.isDemoMode
      ? AppClock.demoSchoolYearStart
      : (asOf.month >= 8 ? DateTime(asOf.year, 9) : DateTime(asOf.year - 1, 9));
  final end = schoolYearEnd ??
      (appClock.isDemoMode ? AppClock.demoSchoolYearEnd : _schoolYearEnd(asOf));
  final ignored = ignoredSubjects.map((s) => s.toLowerCase()).toSet();
  final subjectGrades = <List<GradeAll>>[];
  for (final subject in subjects) {
    if (ignored.contains(subject.name.toLowerCase())) continue;
    final grades = <GradeAll>[];
    for (final grade in subject.basicGrades(semester) ?? const <GradeAll>[]) {
      if (grade.grade != null &&
          !grade.cancelled &&
          grade.weightPercentage > 0 &&
          !calendarDate(grade.date).isBefore(calendarDate(schoolYearStart)) &&
          !calendarDate(grade.date).isAfter(asOf)) {
        grades.add(grade);
      }
    }
    if (grades.isNotEmpty) {
      grades
          .sort((a, b) => calendarDate(a.date).compareTo(calendarDate(b.date)));
      subjectGrades.add(grades);
    }
  }
  final grades = subjectGrades.expand((grades) => grades).toList();
  if (grades.isEmpty) return null;
  final byDay = grades.map((grade) => calendarDate(grade.date)).toSet();
  if (grades.length < 4 || byDay.length < 3) return null;

  final remainingDays = math.max(0, calendarDaysBetween(end, asOf));
  var currentTotal = 0.0;
  var predictedTotal = 0.0;
  for (final grades in subjectGrades) {
    var sum = 0;
    var weight = 0;
    var recentSum = 0.0;
    var recentWeight = 0.0;
    for (final grade in grades) {
      sum += grade.grade! * grade.weightPercentage;
      weight += grade.weightPercentage;
      final age = calendarDaysBetween(grades.last.date, grade.date);
      final recencyWeight = grade.weightPercentage * math.pow(0.5, age / 30);
      recentSum += grade.grade! * recencyWeight;
      recentWeight += recencyWeight;
    }
    final current = roundedGradeAverage(sum, weight)!.toDouble();
    currentTotal += current;
    if (remainingDays == 0) {
      predictedTotal += current;
      continue;
    }
    final observedDays = calendarDaysBetween(asOf, grades.first.date) + 1;
    final futureWeight = weight * remainingDays / observedDays;
    predictedTotal += (sum + futureWeight * (recentSum / recentWeight)) /
        (weight + futureWeight);
  }
  final current = currentTotal / subjectGrades.length;
  final prediction = predictedTotal / subjectGrades.length;
  final slope =
      remainingDays == 0 ? 0.0 : (prediction - current) / remainingDays;
  return GradeForecast(
    currentAverage: current,
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

DateTime _schoolYearEnd(DateTime date) => date.month >= 8
    ? DateTime(date.year + 1, 6, 30)
    : DateTime(date.year, 6, 30);
