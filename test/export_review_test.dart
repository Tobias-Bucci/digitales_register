// Layout regression for the export renderer. By default it renders a small
// synthetic export; pass --dart-define=EXPORT_REVIEW_INPUT=<file> to render a
// local, private export into build/export_review for visual comparison
// instead (no personal fixture is checked in).
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dr/app_state.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const input = String.fromEnvironment('EXPORT_REVIEW_INPUT');
  test('renders every category in all languages as PDF and CSV', () async {
    final data = input.isEmpty
        ? _syntheticExport()
        : jsonDecode(await File(input).readAsString()) as Map<String, dynamic>;
    final out = input.isEmpty
        ? await Directory.systemTemp.createTemp('export-review-')
        : await Directory('build/export_review').create(recursive: true);
    addTearDown(() async {
      if (input.isEmpty) await out.delete(recursive: true);
    });
    final sections = <ExportSection>[];
    for (final c in ExportCategory.values) {
      final records = <ExportRecord>[];
      final averages = <String, int?>{};
      double? overall;
      for (final item in data[c.name] as List) {
        final fields = Map<String, String>.from(item as Map);
        final id = fields.remove('id') ?? '';
        final title = fields.remove('title') ?? '';
        final body = fields.remove('content') ?? '';
        final date = DateTime.tryParse(fields.remove('date') ?? '');
        final subject = fields['subject'] ??
            (c == ExportCategory.grades || c == ExportCategory.timetable
                ? title
                : null);
        if (c == ExportCategory.grades) {
          averages[subject!] =
              (double.parse(fields.remove('average')!.replaceAll(',', '.')) *
                      100)
                  .round();
          overall = double.parse(
              fields.remove('overallAverage')!.replaceAll(',', '.'));
          fields['grade'] = fields['grade']!.replaceAll(',', '.');
          fields['cancelled'] = fields['cancelled'] == 'Ja' ? 'true' : 'false';
        }
        if (c == ExportCategory.absences) {
          fields['status'] = {
                'Schulisch bedingt': 'forSchool',
                'Entschuldigt': 'justified',
                'Noch zu entschuldigen': 'notYetJustified',
                'Nicht entschuldigt': 'notJustified'
              }[fields['status']] ??
              '';
        }
        records.add(ExportRecord(
            id: id,
            title: title,
            date: date,
            subject: subject,
            body: body,
            fields: fields));
      }
      var chosen = records;
      if (c == ExportCategory.timetable) {
        final days = <DateTime, List<ExportRecord>>{};
        for (final r in records) {
          (days[r.date!] ??= []).add(r);
        }
        final week = representativeTimetableWeek(days.entries.map((e) =>
            buildCalendarDay(
                date: UtcDateTime.makeUtc(e.key),
                hours: e.value
                    .map((r) => buildCalendarHour(
                        subject: r.subject!, rooms: [r.fields['room']!]))
                    .toList())));
        final dates =
            week.map((d) => d.date.toIso8601String().substring(0, 10)).toSet();
        chosen = records
            .where((r) =>
                dates.contains(r.date!.toIso8601String().substring(0, 10)))
            .toList();
        expect(chosen, isNotEmpty);
        expect(chosen.length, lessThan(100));
      }
      if (c == ExportCategory.certificates &&
          records.any((r) => r.body.contains('Report card not available')))
        continue;
      sections.add(ExportSection(c, chosen,
          averages: averages,
          overallAverage: overall,
          semester: c == ExportCategory.grades ? Semester.all : null));
    }
    for (final language in ['de', 'it', 'en', 'lld']) {
      final l10n =
          await AppLocalizations.load(AppLanguage.fromCode(language).locale);
      final file = await const ExportService().create(
          sections: sections,
          format: ExportFormat.pdf,
          l10n: l10n,
          scope: l10n.text('export.allYears'));
      expect(ascii.decode(file.bytes.take(4).toList()), '%PDF');
      await File('${out.path}/revised_private_$language.pdf')
          .writeAsBytes(file.bytes);
      final zip = await const ExportService().create(
          sections: sections, format: ExportFormat.csv, l10n: l10n, scope: '');
      await File('${out.path}/revised_private_$language.zip')
          .writeAsBytes(zip.bytes);
      final csvDirectory =
          await Directory('${out.path}/revised_csv_$language').create();
      final entries = ZipDecoder().decodeBytes(zip.bytes);
      expect(entries, hasLength(sections.length));
      for (final entry in entries) {
        expect(entry.content, isNotEmpty);
        await File('${csvDirectory.path}/${entry.name}')
            .writeAsBytes(entry.content);
      }
    }
  });
}

/// A small export in the same shape as a real local review input.
Map<String, dynamic> _syntheticExport() {
  Map<String, String> record(String id, String title, String date,
          [Map<String, String> fields = const {}]) =>
      {
        'id': id,
        'title': title,
        'content': 'Inhalt $id',
        'date': date,
        ...fields
      };
  return {
    'certificates': [record('c1', 'Zeugnis 1. Semester', '2026-02-10')],
    'grades': [
      record('g1', 'Mathematik', '2026-03-02', {
        'grade': '7,5',
        'average': '7,25',
        'overallAverage': '7,40',
        'cancelled': 'Nein',
        'type': 'Schularbeit',
        'weight': '100',
      }),
      record('g2', 'Deutsch', '2026-03-04', {
        'grade': '8',
        'average': '8,00',
        'overallAverage': '7,40',
        'cancelled': 'Ja',
        'type': 'Test',
        'weight': '50',
      }),
    ],
    'messages': [record('m1', 'Elternsprechtag', '2026-03-05')],
    'timetable': [
      for (var day = 2; day <= 6; day++)
        record('t$day', 'Mathematik', '2026-03-0$day',
            {'room': 'R$day', 'hour': '1-2', 'time': '07:50-09:30'}),
    ],
    'exams': [
      record('e1', 'Schularbeit', '2026-03-10', {'subject': 'Mathematik'}),
    ],
    'tasks': [
      record('h1', 'Hausaufgabe', '2026-03-03', {'subject': 'Deutsch'}),
    ],
    'absences': [
      record('a1', 'Abwesenheit', '2026-03-06',
          {'status': 'Entschuldigt', 'hour': '1-2', 'minutes': '100'}),
      record(
          'a2', 'Verspätung', '2026-03-09', {'status': 'Nicht entschuldigt'}),
    ],
    'lessons': [
      record('l1', 'Bruchrechnen', '2026-03-02', {'subject': 'Mathematik'}),
    ],
  };
}
