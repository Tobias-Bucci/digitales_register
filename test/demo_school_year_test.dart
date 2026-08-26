import 'dart:convert';

import 'package:dr/demo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

bool _isVenetoClosure(DateTime date) =>
    _isWithin(date, DateTime(2025, 12, 24), DateTime(2026, 1, 5)) ||
    _isWithin(date, DateTime(2026, 2, 16), DateTime(2026, 2, 18)) ||
    _isWithin(date, DateTime(2026, 4, 2), DateTime(2026, 4, 7)) ||
    _isDay(date, DateTime(2025, 11)) ||
    _isDay(date, DateTime(2025, 12, 8)) ||
    _isDay(date, DateTime(2026, 4, 25)) ||
    _isWithin(date, DateTime(2026, 5), DateTime(2026, 5, 2)) ||
    _isWithin(date, DateTime(2026, 6), DateTime(2026, 6, 2));

bool _isWithin(DateTime date, DateTime first, DateTime last) =>
    !date.isBefore(first) && !date.isAfter(last);

bool _isDay(DateTime date, DateTime other) =>
    date.year == other.year &&
    date.month == other.month &&
    date.day == other.day;

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    await resetDemoStoreForTest();
  });

  tearDown(() async {
    await resetDemoStoreForTest();
    await resetTestState();
  });

  test('the Veneto 2025/26 demo contains a full, consistent grade record',
      () async {
    await getDemoResponse('?semesterWechsel=1', const <String, Object?>{});
    final response = await getDemoResponse(
      'api/student/all_subjects',
      const <String, Object?>{},
    ) as Map<String, Object?>;
    final subjects =
        (response['subjects']! as List<dynamic>).cast<Map<String, Object?>>();

    expect(subjects.length, 10);
    expect(
      subjects
          .map((entry) => (entry['subject']! as Map<String, Object?>)['name'])
          .toSet(),
      containsAll(<String>{
        'Italiano',
        'Matematica',
        'Inglese',
        'Informatica',
        'Sistemi e reti',
        'TPSIT',
      }),
    );

    var grades = 0;
    for (final semester in <int>[1, 2]) {
      await getDemoResponse(
        '?semesterWechsel=$semester',
        const <String, Object?>{},
      );
      final semesterResponse = await getDemoResponse(
        'api/student/all_subjects',
        const <String, Object?>{},
      ) as Map<String, Object?>;
      for (final subject in (semesterResponse['subjects']! as List<dynamic>)
          .cast<Map<String, Object?>>()) {
        for (final grade in (subject['grades']! as List<dynamic>)
            .cast<Map<String, Object?>>()) {
          grades++;
          final date = DateTime.parse(grade['date']! as String);
          expect(date.isBefore(DateTime(2025, 9, 10)), isFalse);
          expect(date.isAfter(DateTime(2026, 6, 6)), isFalse);
          expect(date.weekday, lessThanOrEqualTo(DateTime.friday));
          expect(_isVenetoClosure(date), isFalse);
        }
      }
    }
    expect(grades, greaterThanOrEqualTo(75));

    final detail = json.decode(
      await getDemoResponse(
        'api/student/subject_detail',
        const <String, Object?>{'subjectId': 2},
      ) as String,
    ) as Map<String, dynamic>;
    expect(detail['averageSemester'], greaterThan(0));
    expect(detail['averageYear'], greaterThan(0));
  });

  test('the calendar has no lessons during Veneto holiday closures', () async {
    final calendar = await getDemoResponse(
      'api/calendar/student',
      const <String, Object?>{'startDate': '2025-12-22'},
    ) as Map<String, dynamic>;

    final christmasDay = calendar['2025-12-24']! as Map<String, Object?>;
    final hours = (christmasDay['1']! as Map<String, Object?>)['1']!
        as Map<String, Object?>;
    expect(hours, isEmpty);

    final normalDay = calendar['2025-12-22']! as Map<String, Object?>;
    final normalHours =
        (normalDay['1']! as Map<String, Object?>)['1']! as Map<String, Object?>;
    expect(normalHours, isNotEmpty);

    final assessmentWeek = await getDemoResponse(
      'api/calendar/student',
      const <String, Object?>{'startDate': '2025-09-29'},
    );
    expect(json.encode(assessmentWeek), contains('Vocabulary: technology'));
  });
}
