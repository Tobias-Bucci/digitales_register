import 'package:dr/data.dart';

/// Whether [grade] contributes to a weighted average.
///
/// Only uncancelled grades with a numeric value and a positive weight count.
/// A weight of 0 % marks an assessment that does not count toward the
/// average; negative weights are invalid and are rejected the same way
/// instead of lowering the total weight.
bool countsTowardAverage(GradeAll grade) =>
    !grade.cancelled && grade.grade != null && grade.weightPercentage > 0;

/// The weighted average of [grades] in hundredths, or null when none of them
/// [countsTowardAverage].
///
/// The subject average, statistics, history and forecast all use this so they
/// apply one weight policy and one rounding.
int? weightedGradeAverage(Iterable<GradeAll> grades) {
  var sum = 0;
  var weight = 0;
  for (final grade in grades.where(countsTowardAverage)) {
    sum += grade.grade! * grade.weightPercentage;
    weight += grade.weightPercentage;
  }
  return roundedGradeAverage(sum, weight);
}

/// Rounds a weighted sum of grades in hundredths to the nearest hundredth.
///
/// Grades and percentage weights stay integers until display formatting. Ties
/// round away from zero, matching Dart round(), without a floating point divide.
int? roundedGradeAverage(int weightedSum, int totalWeight) {
  if (totalWeight == 0) return null;
  final numerator = weightedSum.abs();
  final denominator = totalWeight.abs();
  final rounded = numerator ~/ denominator +
      ((numerator % denominator) * 2 >= denominator ? 1 : 0);
  return weightedSum.isNegative != totalWeight.isNegative ? -rounded : rounded;
}
