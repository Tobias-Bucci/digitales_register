import 'package:dr/data.dart';
import 'package:dr/school_notification_grade.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Subject, kind, text and value of [text], or null.
(String, String, String, int?)? _parse(String? text) {
  final grade = parseSchoolNotificationGrade(text);
  return grade == null
      ? null
      : (grade.subject, grade.kind, grade.text, grade.hundredths);
}

void main() {
  group('parseSchoolNotificationGrade (#153)', () {
    test('reads subject, kind and grade of the feed text', () {
      expect(_parse('Neue Bewertung "Mathematik" "Schularbeit" "7½"'),
          ('Mathematik', 'Schularbeit', '7½', 750));
    });

    test('does not depend on the wording before the quotes', () {
      for (final (text, expected) in [
        (
          'Nuova valutazione "Matematica" "Verifica scritta" "5½"',
          ('Matematica', 'Verifica scritta', '5½', 550)
        ),
        ('New assessment "English" "Test" "8"', ('English', 'Test', '8', 800)),
        (
          'Nöia valutaziun "Ladin" "Interogaziun" "9+"',
          ('Ladin', 'Interogaziun', '9+', 925)
        ),
        ('"Deutsch" "Test" "6"', ('Deutsch', 'Test', '6', 600)),
      ]) {
        expect(_parse(text), expected, reason: text);
      }
    });

    test('accepts straight, typographic and angle quotes', () {
      for (final text in [
        'Neue Bewertung "Physik" "Test" "8-"',
        'Neue Bewertung „Physik“ „Test“ „8-“',
        'Neue Bewertung “Physik” “Test” “8-”',
        'Neue Bewertung «Physik» «Test» «8-»',
        'Neue Bewertung »Physik« »Test« »8-«',
        'Neue Bewertung „Physik” "Test" «8-»',
      ]) {
        expect(_parse(text), ('Physik', 'Test', '8-', 775), reason: text);
      }
    });

    test('reads every notation of the grades page', () {
      for (final (grade, hundredths) in [
        ('10', 1000),
        ('7½', 750),
        ('7 ½', 750),
        ('7/8', 750),
        ('8-', 775),
        ('8−', 775),
        ('8+', 825),
        ('7,5', 750),
        ('7.25', 725),
        ('4', 400),
        ('0', 0),
      ]) {
        expect(
            parseSchoolNotificationGrade('"Fach" "Test" "$grade"')?.hundredths,
            hundredths,
            reason: grade);
      }
    });

    test('is tolerant of whitespace, text around the quotes and entities', () {
      expect(
        _parse(
            '  Neue   Bewertung\n "  Deutsch  "  "Test"   " 7+ " (Klasse 3A)'),
        ('Deutsch', 'Test', '7+', 725),
      );
      expect(
        _parse('Neue Bewertung &quot;Deutsch&quot; &quot;Test&quot; '
            '&quot;6&quot;'),
        ('Deutsch', 'Test', '6', 600),
      );
      expect(
        _parse('Neue Bewertung &bdquo;Englisch&ldquo; &#8222;Test&#8220; '
            '&laquo;9&raquo;'),
        ('Englisch', 'Test', '9', 900),
      );
    });

    test('with more than three parts, the last one is the grade', () {
      expect(_parse('Neue Bewertung "Deutsch" "Test" "Teil 2" "6/7"'),
          ('Deutsch', 'Test Teil 2', '6/7', 650));
    });

    test('does not guess with fewer than three parts', () {
      for (final text in [
        null,
        '',
        '   ',
        'Neue Bewertung',
        'Neue Bewertung "Deutsch" "8"',
        'Neue Bewertung "8"',
        // The texts the app builds for its own push notifications.
        'Mathematik: 8,5',
        'A new assessment has been published.',
        'Neue Bewertung "Deutsch" "Test" "8',
      ]) {
        expect(parseSchoolNotificationGrade(text), isNull, reason: '$text');
      }
    });

    test('keeps a short grade it cannot read, without a value', () {
      expect(_parse('Neue Bewertung "Religion" "Mündlich" "gut"'),
          ('Religion', 'Mündlich', 'gut', null));
      expect(_parse('Neue Bewertung "Sport" "Test" "12"'),
          ('Sport', 'Test', '12', null));
    });

    test('drops a grade that is empty or no grade at all', () {
      expect(_parse('Neue Bewertung "Deutsch" "Test" ""'), isNull);
      expect(_parse('Neue Bewertung "Deutsch" "Test" "   "'), isNull);
      expect(_parse('Neue Bewertung "Religion" "Mündlich" "sehr gut"'), isNull);
      expect(_parse('Neue Bewertung "Deutsch" "Test" "abgegeben am 3.4."'),
          isNull);
    });
  });

  group('schoolNotificationGradeOf', () {
    Notification entry(String? type, String title, {String? subTitle}) =>
        buildNotification(type: type, title: title, subTitle: subTitle);

    test('reads the text whatever the type; callers check it', () {
      const text = 'Neue Bewertung "Deutsch" "Test" "8"';
      for (final type in ['grade', 'GRADE', null, 'message']) {
        expect(schoolNotificationGradeOf(entry(type, text))?.hundredths, 800,
            reason: '$type');
      }
    });

    test('shows the grade as the grades page writes it', () {
      for (final (value, display) in [
        ('7½', '7/8'),
        ('8-', '8-'),
        ('10', '10'),
        ('gut', 'gut'),
      ]) {
        expect(parseSchoolNotificationGrade('"Fach" "Test" "$value"')?.display,
            display);
      }
    });

    test('takes the title, else the second line', () {
      expect(
        schoolNotificationGradeOf(entry('grade', 'Neue Bewertung',
                subTitle: '"Deutsch" "Test" "5"'))
            ?.hundredths,
        500,
      );
      expect(
        schoolNotificationGradeOf(entry('grade', '"Deutsch" "Test" "9"',
                subTitle: '"Latein" "Test" "4"'))
            ?.hundredths,
        900,
      );
      expect(
          schoolNotificationGradeOf(entry('grade', 'Neue Bewertung')), isNull);
    });

    test('parses each entry once', () {
      final item = entry('grade', 'Neue Bewertung "Deutsch" "Test" "8"');
      expect(
          identical(
              schoolNotificationGradeOf(item), schoolNotificationGradeOf(item)),
          isTrue);
    });
  });
}
