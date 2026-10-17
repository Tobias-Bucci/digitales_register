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
