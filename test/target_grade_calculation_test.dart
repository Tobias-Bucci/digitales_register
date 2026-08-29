import 'package:dr/target_grade_calculation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TargetGradeEntry grade(int value, [int weight = 100]) =>
      TargetGradeEntry(grade: value * 100, weightPercentage: weight);

  test('suggests balanced grades for an exactly reachable target', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(6), grade(7)],
      targetGrade: 800,
      futureWeights: [100, 100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [950, 950]);
    expect(result.resultingAverage, 800);
  });

  test('reports the best possible outcome when the target is unreachable', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(6), grade(7)],
      targetGrade: 900,
      futureWeights: [100, 100],
    );

    expect(result.isReachable, isFalse);
    expect(result.suggestedGrades, [1000, 1000]);
    expect(result.resultingAverage, 825);
  });

  test('finds the lowest grades which preserve an already exceeded target', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(10), grade(10)],
      targetGrade: 900,
      futureWeights: [100, 100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [800, 800]);
    expect(result.resultingAverage, 900);
  });

  test('balances several future grades', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(8), grade(8), grade(8)],
      targetGrade: 900,
      futureWeights: [100, 100, 100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [1000, 1000, 1000]);
    expect(result.resultingAverage, 900);
  });

  test('supports a single grade and quarter-grade increments', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(8)],
      targetGrade: 825,
      futureWeights: [100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [850]);
    expect(result.resultingAverage, 825);
  });

  test('uses future weights when calculating the recommendation', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(7, 50), grade(8, 100)],
      targetGrade: 800,
      futureWeights: [50, 100],
    );

    expect(result.isReachable, isTrue);
    expect(result.resultingAverage, greaterThanOrEqualTo(800));
    expect(
      result.suggestedGrades
          .every((value) => value >= minimumGrade && value <= maximumGrade),
      isTrue,
    );
  });

  test('accepts relative existing weights above 100 from the school API', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(7, 250), grade(9, 100)],
      targetGrade: 800,
      futureWeights: [100],
    );

    expect(result.isReachable, isTrue);
    expect(result.resultingAverage, greaterThanOrEqualTo(800));
  });

  test('rounds a non-exact target up to a permitted quarter-grade', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(8)],
      targetGrade: 801,
      futureWeights: [100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [825]);
    expect(result.resultingAverage, greaterThanOrEqualTo(801));
  });

  test('supports more than four future grades', () {
    final result = calculateTargetGrades(
      existingGrades: [grade(8)],
      targetGrade: 800,
      futureWeights: List<int>.filled(6, 100),
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, List<int>.filled(6, 800));
    expect(result.resultingAverage, 800);
  });

  test('never recommends a grade below the lower edge of the grading scale',
      () {
    final result = calculateTargetGrades(
      existingGrades: [grade(10), grade(10)],
      targetGrade: 400,
      futureWeights: [100, 100],
    );

    expect(result.isReachable, isTrue);
    expect(result.suggestedGrades, [400, 400]);
    expect(result.resultingAverage, 700);
  });

  test('rejects invalid target grades and weights', () {
    expect(
      () => calculateTargetGrades(
        existingGrades: [grade(8)],
        targetGrade: 399,
        futureWeights: [100],
      ),
      throwsArgumentError,
    );
    expect(
      () => calculateTargetGrades(
        existingGrades: [grade(2)],
        targetGrade: 800,
        futureWeights: [100],
      ),
      throwsArgumentError,
    );
    expect(
      () => calculateTargetGrades(
        existingGrades: [grade(8)],
        targetGrade: 800,
        futureWeights: [0],
      ),
      throwsArgumentError,
    );
  });
}
