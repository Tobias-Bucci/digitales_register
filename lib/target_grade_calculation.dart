import 'dart:typed_data';

/// The school's valid grade range: 4.00 through 10.00.
const minimumGrade = 400;
const maximumGrade = 1000;
const gradeIncrement = 25;

/// A grade as used by the school API: 400 to 1000 represents 4.00 to 10.00.
class TargetGradeEntry {
  const TargetGradeEntry({required this.grade, required this.weightPercentage});

  final int grade;
  final int weightPercentage;
}

/// The outcome of a target-grade calculation.
class TargetGradeCalculation {
  const TargetGradeCalculation._({
    required this.isReachable,
    required this.suggestedGrades,
    required this.currentAverage,
    required this.resultingAverage,
    required this.requiredFutureScore,
  });

  /// Whether the requested target can be reached with the selected future
  /// assessments. When it is false, [suggestedGrades] contains the best
  /// possible grades instead.
  final bool isReachable;
  final List<int> suggestedGrades;
  final double currentAverage;
  final double resultingAverage;

  /// The weighted score which is required from the future assessments. This
  /// uses the same internal scale as [TargetGradeEntry].
  final int requiredFutureScore;
}

/// Calculates the lowest feasible, evenly distributed future grades needed to
/// maintain at least [targetGrade].
///
/// Grades support the quarter-grade steps accepted by the existing grade
/// calculator (4, 4.25, ..., 10). Future weights belong one-to-one to the
/// future assessments and use the existing percentage-based weighting model.
/// Existing weights are relative values supplied by the school API and may be
/// greater than 100.
TargetGradeCalculation calculateTargetGrades({
  required List<TargetGradeEntry> existingGrades,
  required int targetGrade,
  required List<int> futureWeights,
}) {
  if (targetGrade < minimumGrade || targetGrade > maximumGrade) {
    throw ArgumentError.value(
        targetGrade, 'targetGrade', 'must be between 400 and 1000');
  }
  if (futureWeights.isEmpty ||
      futureWeights.any((weight) => weight <= 0 || weight > 100)) {
    throw ArgumentError.value(
        futureWeights, 'futureWeights', 'must contain weights from 1 to 100');
  }
  if (existingGrades.any(
    (grade) =>
        grade.grade < minimumGrade ||
        grade.grade > maximumGrade ||
        grade.weightPercentage < 0,
  )) {
    throw ArgumentError.value(existingGrades, 'existingGrades',
        'contains an invalid grade or weight');
  }

  final existingWeight = existingGrades.fold<int>(
    0,
    (sum, grade) => sum + grade.weightPercentage,
  );
  final existingScore = existingGrades.fold<int>(
    0,
    (sum, grade) => sum + grade.grade * grade.weightPercentage,
  );
  final futureWeight =
      futureWeights.fold<int>(0, (sum, weight) => sum + weight);
  final totalWeight = existingWeight + futureWeight;
  final requiredFutureScore = targetGrade * totalWeight - existingScore;
  final currentAverage =
      existingWeight == 0 ? 0.0 : existingScore / existingWeight;
  final maximumFutureScore = maximumGrade * futureWeight;

  if (requiredFutureScore > maximumFutureScore) {
    final bestGrades = List<int>.filled(futureWeights.length, maximumGrade);
    return TargetGradeCalculation._(
      isReachable: false,
      suggestedGrades: bestGrades,
      currentAverage: currentAverage,
      resultingAverage: (existingScore + maximumFutureScore) / totalWeight,
      requiredFutureScore: requiredFutureScore,
    );
  }

  // One unit represents 0.25. Dynamic programming finds the smallest
  // attainable weighted score at or above the target. For equal scores it
  // minimizes the distance from the required weighted average, which favours
  // balanced combinations such as 9 + 9 + 10 over extreme alternatives.
  const minGradeUnits = minimumGrade ~/ gradeIncrement;
  const maxGradeUnits = maximumGrade ~/ gradeIncrement;
  final requiredUnits = requiredFutureScore <= 0
      ? 0
      : (requiredFutureScore + gradeIncrement - 1) ~/ gradeIncrement;
  final maxUnits = futureWeight * maxGradeUnits;
  const infinity = 0x3fffffff;
  final costs = List<Int32List>.generate(
    futureWeights.length + 1,
    (_) => Int32List(maxUnits + 1)..fillRange(0, maxUnits + 1, infinity),
  );
  final previousScores = List<Int32List>.generate(
    futureWeights.length + 1,
    (_) => Int32List(maxUnits + 1)..fillRange(0, maxUnits + 1, -1),
  );
  final selectedUnits = List<Int32List>.generate(
    futureWeights.length + 1,
    (_) => Int32List(maxUnits + 1)..fillRange(0, maxUnits + 1, -1),
  );
  costs[0][0] = 0;
  final desiredUnits = requiredUnits / futureWeight;

  for (var index = 0; index < futureWeights.length; index++) {
    final weight = futureWeights[index];
    final previous = costs[index];
    final next = costs[index + 1];
    for (var score = 0; score <= maxUnits; score++) {
      final previousCost = previous[score];
      if (previousCost == infinity) continue;
      for (var gradeUnit = minGradeUnits;
          gradeUnit <= maxGradeUnits;
          gradeUnit++) {
        final nextScore = score + gradeUnit * weight;
        if (nextScore > maxUnits) continue;
        final distance = gradeUnit - desiredUnits;
        final candidateCost =
            previousCost + (distance * distance * 1000).round();
        if (candidateCost < next[nextScore]) {
          next[nextScore] = candidateCost;
          previousScores[index + 1][nextScore] = score;
          selectedUnits[index + 1][nextScore] = gradeUnit;
        }
      }
    }
  }

  var selectedScore = requiredUnits > minGradeUnits * futureWeight
      ? requiredUnits
      : minGradeUnits * futureWeight;
  while (selectedScore <= maxUnits &&
      costs[futureWeights.length][selectedScore] == infinity) {
    selectedScore++;
  }
  // Reaching the maximum is always possible, therefore this assertion also
  // guards against accidental changes to the range above.
  assert(selectedScore <= maxUnits);

  final suggestedGrades = List<int>.filled(futureWeights.length, minimumGrade);
  var score = selectedScore;
  for (var index = futureWeights.length; index > 0; index--) {
    suggestedGrades[index - 1] = selectedUnits[index][score] * gradeIncrement;
    score = previousScores[index][score];
  }
  final actualFutureScore = selectedScore * gradeIncrement;
  return TargetGradeCalculation._(
    isReachable: true,
    suggestedGrades: suggestedGrades,
    currentAverage: currentAverage,
    resultingAverage: (existingScore + actualFutureScore) / totalWeight,
    requiredFutureScore: requiredFutureScore,
  );
}
