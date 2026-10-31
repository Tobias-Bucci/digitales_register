import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = <AppLanguage, AppLocalizations>{};

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final language in AppLanguage.values) {
      l10n[language] = await AppLocalizations.load(language.locale);
    }
  });

  // The settings row for the older learning data with [count] exams, notes
  // and files.
  String legacyRow(AppLanguage language, int count) {
    final texts = l10n[language]!;
    return texts.text('studyData.legacy.setting.subtitle',
        args: texts.legacyStudyCounts(
            exams: count, notes: count, files: count));
  }

  test('the older learning data use singular and plural forms', () {
    const expected = <AppLanguage, List<String>>{
      AppLanguage.de: [
        '0 Prüfungen (0 Notizen, 0 Dateien).',
        '1 Prüfung (1 Notiz, 1 Datei).',
        '2 Prüfungen (2 Notizen, 2 Dateien).',
      ],
      AppLanguage.en: [
        '0 exams (0 notes, 0 files).',
        '1 exam (1 note, 1 file).',
        '2 exams (2 notes, 2 files).',
      ],
      AppLanguage.it: [
        '0 verifiche (0 note, 0 file).',
        '1 verifica (1 nota, 1 file).',
        '2 verifiche (2 note, 2 file).',
      ],
      AppLanguage.lld: [
        '0 verifiches (0 notes, 0 files).',
        '1 verifica (1 nota, 1 file).',
        '2 verifiches (2 notes, 2 files).',
      ],
    };
    for (final language in AppLanguage.values) {
      for (final count in [0, 1, 2]) {
        expect(legacyRow(language, count),
            startsWith(expected[language]![count]),
            reason: '${language.code}, $count');
      }
    }
  });

  test('the older learning data dialog and messages count in German', () {
    final de = l10n[AppLanguage.de]!;
    final one = de.legacyStudyCounts(exams: 1, notes: 1, files: 1);
    expect(de.text('studyData.legacy.body', args: one),
        contains('für 1 Prüfung (1 Notiz, 1 Datei),'));
    expect(de.text('studyData.legacy.discardConfirm.body', args: one),
        contains('(1 Notiz, 1 Datei)'));
    expect(de.text('studyData.legacy.assigned', args: one),
        'Ältere Lerndaten zugeordnet: 1 Notiz, 1 Datei.');
    expect(de.text('studyData.legacy.assignedPartly', args: one),
        startsWith('Zugeordnet: 1 Notiz, 1 Datei. Für 1 Prüfung hat'));
  });

  test('skipped grades and hidden subjects use singular and plural forms',
      () {
    const expected = <AppLanguage, List<String>>{
      AppLanguage.de: [
        '1 Eintrag ohne Zahlenwert wurde nicht importiert',
        '2 Einträge ohne Zahlenwert wurden nicht importiert',
        '1 ausgeblendet',
        '2 ausgeblendet',
      ],
      AppLanguage.en: [
        '1 entry without a numeric grade was not imported',
        '2 entries without a numeric grade were not imported',
        '1 hidden',
        '2 hidden',
      ],
      AppLanguage.it: [
        '1 voce senza un voto numerico non è stata importata',
        '2 voci senza un voto numerico non sono state importate',
        '1 nascosta',
        '2 nascoste',
      ],
      AppLanguage.lld: [
        "1 entrada zënza valur numerica n'é nia gnüda importada",
        "2 entries zënza valur numerica n'é nia gnüdes importades",
        '1 ascognüda',
        '2 ascognüdes',
      ],
    };
    for (final language in AppLanguage.values) {
      final texts = l10n[language]!;
      expect(
        [
          texts.skippedGradesLabel(1),
          texts.skippedGradesLabel(2),
          texts.hiddenSubjectsLabel(1),
          texts.hiddenSubjectsLabel(2),
        ],
        expected[language],
        reason: language.code,
      );
    }
  });
}
