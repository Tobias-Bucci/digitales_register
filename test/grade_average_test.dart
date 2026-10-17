import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_average.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final cases = <String, (List<(int, int)>, int?)>{
    '6.9375 rounds to 6.94 rather than 6.93': ([(600, 1), (700, 15)], 694),
    'standard equal weights': ([(600, 100), (800, 100)], 700),
    'decimal grades and unequal weights': ([(625, 25), (875, 75)], 813),
    'exact half rounds up': ([(693, 50), (694, 50)], 694),
    'just below half': ([(693, 51), (694, 49)], 693),
    'just above half': ([(693, 49), (694, 51)], 694),
    'many weighted entries': ([(500, 20), (725, 30), (900, 50)], 768),
    'zero weight ignored': ([(1000, 0), (625, 50)], 625),
    'all weights zero': ([(600, 0), (700, 0)], null),
    'no grades': (<(int, int)>[], null),
    'single decimal grade': ([(694, 100)], 694),
  };

  for (final entry in cases.entries) {
    test(entry.key, () {
      final (grades, expected) = entry.value;
      final sum = grades.fold(0, (sum, g) => sum + g.$1 * g.$2);
      final weight = grades.fold(0, (sum, g) => sum + g.$2);
      expect(roundedGradeAverage(sum, weight), expected);
      final subject = buildSubject(
        name: 'Test',
        gradesAll: {
          Semester.first: BuiltList([
            for (final (value, percentage) in grades)
              buildGradeAll(
                date: UtcDateTime(2026, 10, 17),
                grade: value,
                weightPercentage: percentage,
              ),
          ]),
        },
      );
      expect(subject.average(Semester.first), expected);
    });
  }
}
