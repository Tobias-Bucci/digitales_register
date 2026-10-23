// Opt-in layout regression using local exports; no personal fixture is checked in.
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
  test('render a local, private export for visual comparison', () async {
    final data =
        jsonDecode(await File(input).readAsString()) as Map<String, dynamic>;
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
      await File('build/export_review/revised_private_$language.pdf')
          .writeAsBytes(file.bytes);
      final zip = await const ExportService().create(
          sections: sections, format: ExportFormat.csv, l10n: l10n, scope: '');
      await File('build/export_review/revised_private_$language.zip')
          .writeAsBytes(zip.bytes);
      await Directory('build/export_review/revised_csv_$language')
          .create(recursive: true);
      for (final entry in ZipDecoder().decodeBytes(zip.bytes)) {
        await File('build/export_review/revised_csv_$language/${entry.name}')
            .writeAsBytes(entry.content);
      }
    }
  }, skip: input.isEmpty);
}
