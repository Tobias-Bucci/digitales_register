import 'package:dr/app_subject_translation_controller.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_notification_content.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _grade = SchoolNotificationKind.gradeNew;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalogs = <AppLanguage, AppLocalizations>{};

  setUpAll(() async {
    for (final language in AppLanguage.values) {
      catalogs[language] = await AppLocalizations.load(language.locale);
    }
  });

  SchoolNotificationText build(
    List<SchoolNotificationItem> items, {
    AppLanguage language = AppLanguage.en,
    bool details = true,
    bool showCount = false,
    bool translate = false,
  }) {
    final l10n = catalogs[language]!;
    return buildSchoolNotificationText(
      group: items.first.group,
      items: items,
      details: details,
      showCount: showCount,
      language: language,
      text: (key, {args = const {}}) => l10n.text(key, args: args),
      subjectName: translate ? l10n.translateSubjectName : null,
    );
  }

  group('grade formatting', () {
    test('uses the decimal comma in de, it and lld and the point in en', () {
      const expected = {
        AppLanguage.de: '8,5',
        AppLanguage.it: '8,5',
        AppLanguage.lld: '8,5',
        AppLanguage.en: '8.5',
      };
      for (final entry in expected.entries) {
        expect(formatNotificationGrade(850, entry.key), entry.value);
      }
      expect(formatNotificationGrade(633, AppLanguage.de), '6,33');
      expect(formatNotificationGrade(610, AppLanguage.it), '6,1');
      expect(formatNotificationGrade(610, AppLanguage.en), '6.1');
    });

    test('keeps whole and quarter grades as the register writes them', () {
      for (final language in AppLanguage.values) {
        expect(formatNotificationGrade(800, language), '8');
        expect(formatNotificationGrade(825, language), '8+');
        expect(formatNotificationGrade(875, language), '9-');
        expect(formatNotificationGrade(1000, language), '10');
      }
    });
  });

  group('text per event type and language', () {
    const grade = SchoolNotificationItem(_grade,
        subject: 'Mathematik', grade: 850, objectId: 1);
    test('a new grade shows subject and grade (issue example)', () {
      expect([
        for (final language in AppLanguage.values)
          (
            build([grade], language: language).title,
            build([grade], language: language).body
          )
      ], [
        ('Neue Note', 'Mathematik: 8,5'),
        ('Nuovo voto', 'Mathematik: 8,5'),
        ('Nota nueva', 'Mathematik: 8,5'),
        ('New grade', 'Mathematik: 8.5'),
      ]);
    });

    test('the subject follows the app language when translation is on',
        () async {
      SharedPreferences.setMockInitialValues(
          {'subjectTranslationEnabled': true});
      await appSubjectTranslationController.load();
      addTearDown(() async {
        SharedPreferences.setMockInitialValues({});
        await appSubjectTranslationController.load();
      });
      expect(build([grade], translate: true).body, 'Mathematics: 8.5');
      expect(build([grade], language: AppLanguage.it, translate: true).body,
          'Matematica: 8,5');
      expect(build([grade], language: AppLanguage.de, translate: true).body,
          'Mathematik: 8,5');
    });

    test('changed and removed grades show old and new value', () {
      const changed = SchoolNotificationItem(
          SchoolNotificationKind.gradeChanged,
          subject: 'Englisch',
          oldGrade: 700,
          grade: 750);
      const removed = SchoolNotificationItem(
          SchoolNotificationKind.gradeDeleted,
          subject: 'Englisch',
          grade: 625);
      final texts = {
        for (final language in AppLanguage.values)
          language: (
            build([changed], language: language).title,
            build([changed], language: language).body,
            build([removed], language: language).title,
            build([removed], language: language).body,
          )
      };
      expect(texts[AppLanguage.en], (
        'Grade changed',
        'Englisch: 7 → 7.5',
        'Grade removed',
        'Englisch: 6+ removed'
      ));
      expect(texts[AppLanguage.de], (
        'Note geändert',
        'Englisch: 7 → 7,5',
        'Note entfernt',
        'Englisch: 6+ entfernt'
      ));
      expect(texts[AppLanguage.it], (
        'Voto modificato',
        'Englisch: 7 → 7,5',
        'Voto eliminato',
        'Englisch: 6+ eliminato'
      ));
      expect(texts[AppLanguage.lld], (
        'Nota mudada',
        'Englisch: 7 → 7,5',
        'Nota sodeda',
        'Englisch: 6+ sodeda'
      ));
    });

    test('homework, tests, absences and messages show a short description', () {
      const homework = SchoolNotificationItem(SchoolNotificationKind.homework,
          subject: 'Deutsch', description: 'Seite 12, Nr. 3');
      const test = SchoolNotificationItem(SchoolNotificationKind.test,
          subject: 'Physik', description: 'Schularbeit');
      const absence = SchoolNotificationItem(SchoolNotificationKind.absence,
          description: 'Absenz – 2 Stunden');
      const message = SchoolNotificationItem(SchoolNotificationKind.message,
          sender: 'Direktion', description: 'Elternsprechtag');
      for (final (item, titles, body) in [
        (
          homework,
          ['Neue Hausaufgabe', 'Nuovo compito', 'Compit nuev', 'New homework'],
          'Deutsch: Seite 12, Nr. 3'
        ),
        (
          test,
          ['Neuer Test', 'Nuova verifica', 'Test nuev', 'New test'],
          'Physik: Schularbeit'
        ),
        (
          absence,
          ['Neue Absenz', 'Nuova assenza', 'Nöia assënza', 'New absence'],
          'Absenz – 2 Stunden'
        ),
        (
          message,
          [
            'Neue Schulmitteilung',
            'Nuova comunicazione scolastica',
            'Comunicazion nueva de scola',
            'New school message'
          ],
          'Direktion: Elternsprechtag'
        ),
      ]) {
        for (final (index, language) in AppLanguage.values.indexed) {
          final text = build([item], language: language);
          expect(text.title, titles[index], reason: '$language ${item.kind}');
          expect(text.body, body, reason: '$language ${item.kind}');
        }
      }
    });
  });

  group('fallback to the generic text', () {
    test('details off gives exactly the previous generic text', () {
      const grade =
          SchoolNotificationItem(_grade, subject: 'Mathe', grade: 900);
      final text = build([grade], details: false);
      expect((text.title, text.body),
          ('New grade', 'A new assessment has been published.'));
      expect(text.lines, isEmpty);
      final german = build([grade], details: false, language: AppLanguage.de);
      expect((german.title, german.body),
          ('Neue Note', 'Eine neue Bewertung wurde veröffentlicht.'));
      final plural = build([grade, grade], details: false);
      expect((plural.title, plural.body),
          ('New grades', 'New assessments are available in your register.'));
      expect(build([grade, grade], details: false, showCount: true).title,
          '2 new grades');
    });

    test('an event without data (older format, no dashboard) stays generic',
        () {
      const bare = SchoolNotificationItem(_grade, objectId: 4);
      const noValue = SchoolNotificationItem(_grade, subject: 'Mathe');
      const message = SchoolNotificationItem(SchoolNotificationKind.message);
      for (final item in [bare, noValue]) {
        final text = build([item]);
        expect((text.title, text.body),
            ('New grade', 'A new assessment has been published.'));
      }
      expect(build([message]).body, 'You have received a new school message.');
      expect(build([bare, bare]).title, 'New grades');
      for (final language in AppLanguage.values) {
        expect(build([bare], language: language).body,
            catalogs[language]!.text('schoolNotifications.grade.body'));
      }
    });

    test('a payload of an older version still opens its destination', () {
      final old = SchoolNotificationDestination.decode(
          '{"v":1,"account":"${'a' * 64}","category":"grade","id":null}');
      expect(old?.category, SchoolNotificationCategory.grade);
      final message = SchoolNotificationDestination.decode(
          '{"v":1,"account":"${'b' * 64}","category":"message","id":7}');
      expect(message?.objectId, 7);
      final homework = SchoolNotificationDestination(
              'c' * 64, SchoolNotificationCategory.homework, null)
          .encode();
      expect(SchoolNotificationDestination.decode(homework)?.category,
          SchoolNotificationCategory.homework);
      expect(SchoolNotificationDestination.decode('{"v":2}'), isNull);
      expect(SchoolNotificationDestination.decode(null), isNull);
    });
  });

  group('grouping', () {
    test('several grades become one notification with a count and lines', () {
      final items = [
        const SchoolNotificationItem(_grade, subject: 'Mathematik', grade: 850),
        const SchoolNotificationItem(_grade, subject: 'Deutsch', grade: 700),
        const SchoolNotificationItem(_grade, subject: 'Englisch', grade: 825),
      ];
      final english = build(items);
      expect(english.title, '3 new grades');
      expect(english.lines, ['Mathematik: 8.5', 'Deutsch: 7', 'Englisch: 8+']);
      expect(english.body, english.lines.join('\n'));
      expect(build(items, language: AppLanguage.de).title, '3 neue Noten');
      expect(build(items, language: AppLanguage.it).title, '3 nuovi voti');
      expect(build(items, language: AppLanguage.lld).title, '3 notes nueves');
    });

    test('mixed grade events are grade updates, not new grades', () {
      final text = build([
        const SchoolNotificationItem(_grade, subject: 'Mathematik', grade: 800),
        const SchoolNotificationItem(SchoolNotificationKind.gradeChanged,
            subject: 'Deutsch', oldGrade: 600, grade: 650),
      ]);
      expect(text.title, '2 grade updates');
      expect(text.lines, ['Mathematik: 8', 'Deutsch: 6 → 6.5']);
      expect(
          build([
            const SchoolNotificationItem(_grade),
            const SchoolNotificationItem(SchoolNotificationKind.gradeDeleted),
          ], details: false)
              .title,
          'Grade updates');
    });

    test('more than five events end with "+n more"', () {
      final items = [
        for (var i = 0; i < 8; i++)
          SchoolNotificationItem(_grade, subject: 'Fach $i', grade: 700),
      ];
      final text = build(items);
      expect(text.title, '8 new grades');
      expect(text.lines, hasLength(schoolNotificationMaxLines + 1));
      expect(text.lines.last, '+3 more');
      expect(build(items, language: AppLanguage.de).lines.last, '+3 weitere');
    });

    test('an event without data in a group keeps its generic line', () {
      final text = build([
        const SchoolNotificationItem(_grade, subject: 'Mathematik', grade: 800),
        const SchoolNotificationItem(_grade),
      ]);
      expect(text.lines,
          ['Mathematik: 8', 'A new assessment has been published.']);
    });

    test('every kind belongs to the group with its own setting', () {
      expect({
        for (final kind in SchoolNotificationKind.values)
          kind: schoolNotificationGroupOf(kind)
      }, {
        SchoolNotificationKind.gradeNew: SchoolNotificationGroup.grade,
        SchoolNotificationKind.gradeChanged: SchoolNotificationGroup.grade,
        SchoolNotificationKind.gradeDeleted: SchoolNotificationGroup.grade,
        SchoolNotificationKind.message: SchoolNotificationGroup.message,
        SchoolNotificationKind.homework: SchoolNotificationGroup.homework,
        SchoolNotificationKind.test: SchoolNotificationGroup.homework,
        SchoolNotificationKind.absence: SchoolNotificationGroup.other,
        SchoolNotificationKind.observation: SchoolNotificationGroup.other,
      });
    });
  });

  group('dashboard snapshot and deduplication', () {
    List<Map<String, Object?>> day(
            String date, List<Map<String, Object?>> items) =>
        [
          {'date': date, 'items': items}
        ];
    Map<String, Object?> grade(int id, String value, {String? subject}) => {
          'id': id,
          'type': 'grade',
          'title': 'Bewertung',
          'subtitle': 'Schularbeit',
          'label': subject ?? 'Mathematik',
          'grade': value,
        };

    test('parses grades, teacher homework and tests, ignores the rest', () {
      final entries = parseSchoolDashboard([
        {
          'date': '2026-11-16 00:00:00',
          'items': [
            grade(1, '8.5'),
            {
              'id': 2,
              'type': 'lessonHomework',
              'title': 'S. 4',
              'label': 'Deutsch'
            },
            {'id': 3, 'type': 'gradeGroup', 'title': 'Test', 'label': 'Physik'},
            {'id': 4, 'type': 'homework', 'title': 'My own reminder'},
            {'id': 5, 'type': 'observation', 'title': 'Note'},
            {'type': 'grade', 'grade': '7'},
          ]
        }
      ])!;
      expect(entries.keys, ['g:1', 'h:2', 'h:3']);
      expect(entries['g:1']!.grade, 850);
      expect(entries['g:1']!.subject, 'Mathematik');
      expect(entries['g:1']!.day, '2026-11-16');
      expect(entries['h:3']!.kind, 'test');
      final restored = SchoolDashboardEntry.fromJson(entries['g:1']!.toJson());
      expect(restored?.key, 'g:1');
      expect(restored?.grade, 850);
    });

    test('a malformed response is no snapshot, never an empty baseline', () {
      expect(parseSchoolDashboard(null), isNull);
      expect(parseSchoolDashboard({'error': true}), isNull);
      expect(
          parseSchoolDashboard([
            {'items': []}
          ]),
          isNull);
      expect(parseSchoolDashboard(['x']), isNull);
      expect(parseSchoolDashboard([]), isEmpty);
    });

    test('the first snapshot is a quiet baseline', () {
      final current = parseSchoolDashboard(day('2026-11-16', [grade(1, '8')]))!;
      expect(diffSchoolDashboard(null, current), isEmpty);
    });

    test('changed, removed and new entries; out of window is no deletion', () {
      final before = parseSchoolDashboard([
        ...day('2026-11-10', [grade(9, '6')]),
        ...day('2026-11-16', [grade(1, '8'), grade(2, '5')]),
      ]);
      final after = parseSchoolDashboard([
        ...day('2026-11-16', [grade(1, '7.5')]),
        ...day('2026-11-20', [
          {
            'id': 7,
            'type': 'lessonHomework',
            'title': 'S. 4',
            'label': 'Deutsch'
          },
          {'id': 8, 'type': 'gradeGroup', 'title': 'Test', 'label': 'Physik'},
        ]),
      ])!;
      final changes = diffSchoolDashboard(before, after);
      expect(changes.map((change) => change.key),
          ['c:1:800:750', 'n:7', 'n:8', 'd:2']);
      expect(changes.first.item.oldGrade, 800);
      expect(changes.first.item.grade, 750);
      expect(changes[1].item.kind, SchoolNotificationKind.homework);
      expect(changes[2].item.kind, SchoolNotificationKind.test);
      expect(changes.last.item.kind, SchoolNotificationKind.gradeDeleted);
      // Grade 9 left the window with its whole day: not reported.
      expect(changes.map((change) => change.item.objectId), isNot(contains(9)));
    });

    test('a notified change is never shown twice', () {
      final before = parseSchoolDashboard(day('2026-11-16', [grade(1, '8')]));
      final after = parseSchoolDashboard(day('2026-11-16', [grade(1, '9')]))!;
      final first = diffSchoolDashboard(before, after);
      expect(first, hasLength(1));
      final notified = rememberNotified(const [], first.map((c) => c.key));
      expect(diffSchoolDashboard(before, after, notified: notified.toSet()),
          isEmpty);
      // Changing back is a new change and is shown.
      final back = parseSchoolDashboard(day('2026-11-16', [grade(1, '8')]))!;
      expect(diffSchoolDashboard(after, back, notified: notified.toSet()),
          hasLength(1));
    });

    test('remembered keys are capped and keep the newest', () {
      final keys = rememberNotified(
          [for (var i = 0; i < schoolNotificationNotifiedLimit; i++) 'k$i'],
          ['new', 'k5']);
      expect(keys, hasLength(schoolNotificationNotifiedLimit));
      expect(keys.last, 'k5');
      expect(keys[keys.length - 2], 'new');
      expect(keys, isNot(contains('k0')));
    });

    test('the feed asks for the dashboard right after a new grade', () {
      final since = DateTime.utc(2026, 11, 16, 10);
      final feed = [
        {'type': 'message', 'timeSent': '2026-11-16T11:00:00Z'},
        {'type': 'GRADE', 'timeSent': '2026-11-16T09:00:00Z'},
      ];
      expect(schoolFeedHasGradeAfter(feed, since), isFalse);
      expect(schoolFeedHasGradeAfter(feed, null), isTrue);
      expect(
          schoolFeedHasGradeAfter([
            ...feed,
            {'type': 'grade', 'timeSent': '2026-11-16T10:30:00Z'}
          ], since),
          isTrue);
    });
  });

  group('scheduling and back-off', () {
    final now = DateTime.utc(2026, 11, 16, 12);
    test('dashboards are read at most hourly', () {
      expect(schoolDashboardDue(null, now), isTrue);
      expect(schoolDashboardDue(now.subtract(const Duration(minutes: 59)), now),
          isFalse);
      expect(schoolDashboardDue(now.subtract(const Duration(minutes: 60)), now),
          isTrue);
      // A clock that went backwards must not block the schedule forever.
      expect(
          schoolDashboardDue(now.add(const Duration(hours: 1)), now), isTrue);
    });

    test('back-off grows after repeated failures and is capped', () {
      expect([
        for (var failures = 0; failures <= 7; failures++)
          schoolNotificationRetryDelay(failures).inMinutes
      ], [
        0,
        0,
        15,
        30,
        60,
        120,
        120,
        120
      ]);
    });

    test('a check is allowed again once the pause is over', () {
      final last = now.subtract(const Duration(minutes: 20));
      expect(schoolNotificationRetryAllowed(1, last, now), isTrue);
      expect(schoolNotificationRetryAllowed(2, last, now), isTrue);
      expect(schoolNotificationRetryAllowed(3, last, now), isFalse);
      expect(
          schoolNotificationRetryAllowed(
              3, now.subtract(const Duration(minutes: 30)), now),
          isTrue);
      expect(schoolNotificationRetryAllowed(9, null, now), isTrue);
      expect(
          schoolNotificationRetryAllowed(
              9, now.add(const Duration(minutes: 5)), now),
          isTrue);
    });
  });

  group('preferences', () {
    test('details and the new categories follow the setting', () {
      final preferences = SchoolNotificationPreferences(
          consent: SchoolNotificationConsent.accepted, enabled: true);
      expect(preferences.details, isTrue);
      expect(preferences.allows(SchoolNotificationCategory.homework), isTrue);
      preferences.setCategory(SchoolNotificationCategory.other, false);
      expect(preferences.allows(SchoolNotificationCategory.other), isFalse);
      expect(preferences.toJson(), containsPair('other', false));
      preferences
        ..grades = false
        ..messages = false
        ..homework = false;
      expect(preferences.anyCategory, isFalse);
    });

    test('absences and observations from the feed are other events', () {
      expect(SchoolNotificationEvent.categoryFor('Absence'),
          SchoolNotificationCategory.other);
      expect(SchoolNotificationEvent.categoryFor('observation'),
          SchoolNotificationCategory.other);
      expect(SchoolNotificationEvent.categoryFor('generic'), isNull);
      final event = SchoolNotificationEvent.parse({
        'id': 3,
        'type': 'absence',
        'title': 'Absenz',
        'subTitle': '2 Stunden',
        'timeSent': '2026-11-16T10:00:00Z',
      })!;
      expect((event.type, event.title, event.detail),
          ('absence', 'Absenz', '2 Stunden'));
    });
  });
}
