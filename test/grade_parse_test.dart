import 'package:dr/ui/grade_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tryParseFormattedGrade', () {
    test('parses precise values', () {
      expect(tryParseFormattedGrade('0'), 0);
      expect(tryParseFormattedGrade('000'), 0);
      expect(tryParseFormattedGrade('10'), 1000);
      expect(tryParseFormattedGrade('8,5'), 850);
      expect(tryParseFormattedGrade('08,5'), 850);
      expect(tryParseFormattedGrade('8.50'), 850);
      expect(tryParseFormattedGrade('8.0'), 800);
      expect(tryParseFormattedGrade('8.00'), 800);
    });

    test('rejects malformed precise values', () {
      expect(tryParseFormattedGrade('8.'), isNull);
      expect(tryParseFormattedGrade('8.000'), isNull);
      expect(tryParseFormattedGrade('80.50'), isNull);
      expect(tryParseFormattedGrade('asdf'), isNull);
      expect(tryParseFormattedGrade('-10'), isNull);
    });

    test('parses plus and minus suffixes', () {
      expect(tryParseFormattedGrade('5-'), 475);
      expect(tryParseFormattedGrade('10-'), 975);
      expect(tryParseFormattedGrade('0+'), 25);
      expect(tryParseFormattedGrade('5+'), 525);
    });

    test('rejects invalid plus and minus suffixes', () {
      expect(tryParseFormattedGrade('0-'), isNull);
      expect(tryParseFormattedGrade('11-'), isNull);
      expect(tryParseFormattedGrade('10+'), isNull);
      expect(tryParseFormattedGrade('+8+'), isNull);
    });

    test('parses adjacent grade ranges', () {
      expect(tryParseFormattedGrade('0-1'), 50);
      expect(tryParseFormattedGrade('0/1'), 50);
      expect(tryParseFormattedGrade('9/10'), 950);
      expect(tryParseFormattedGrade('9-10'), 950);
    });

    test('rejects invalid grade ranges', () {
      expect(tryParseFormattedGrade('-1-0'), isNull);
      expect(tryParseFormattedGrade('10/11'), isNull);
      expect(tryParseFormattedGrade('10/9'), isNull);
      expect(tryParseFormattedGrade('9/9.5'), isNull);
    });
  });
}
