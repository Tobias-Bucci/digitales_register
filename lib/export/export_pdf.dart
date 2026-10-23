// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:typed_data';

import 'package:dr/export/export_csv.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportPdfRequest {
  const ExportPdfRequest(this.sections, this.l10n, this.created, this.scope,
      this.regular, this.bold);
  final List<ExportSection> sections;
  final AppLocalizations l10n;
  final DateTime created;
  final String scope;
  final ByteData regular;
  final ByteData bold;
}

/// Runs on the export worker isolate. All fonts are bundled; no network calls.
Future<Uint8List> createExportPdf(ExportPdfRequest request) async {
  final l10n = request.l10n;
  String t(String key) => l10n.text('export.$key');
  final locale = l10n.locale.languageCode;
  await initializeDateFormatting(locale);
  final date = DateFormat.yMMMd(locale);
  final number = NumberFormat('0.00', locale);
  const ink = PdfColor.fromInt(0xff17394a);
  const accent = PdfColor.fromInt(0xff327c83);
  const pale = PdfColor.fromInt(0xffedf5f5);
  const muted = PdfColor.fromInt(0xff576873);
  final document = pw.Document(
      title: t('title'),
      author: 'Digitales Register',
      creator: 'Digitales Register',
      theme: pw.ThemeData.withFont(
          base: pw.Font.ttf(request.regular), bold: pw.Font.ttf(request.bold)));
  const bodyStyle = pw.TextStyle(fontSize: 10, lineSpacing: 3, color: ink);
  pw.Widget line(String text,
          {bool bold = false, double size = 10, PdfColor color = ink}) =>
      pw.Text(text,
          style: pw.TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              lineSpacing: 3));
  List<pw.Widget> paragraphs(String value) => [
        for (final part in exportTextChunks(value))
          pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(part, style: bodyStyle)),
      ];
  for (final section in request.sections) {
    final name = t('category.${section.category.name}');
    document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 32, 42, 36),
        maxPages: 1000,
        header: (_) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: pale, width: 2))),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  line('DIGITALES REGISTER',
                      bold: true, size: 9, color: accent),
                  line(name, size: 9, color: muted)
                ])),
        footer: (context) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  line(date.format(request.created), size: 8, color: muted),
                  line(
                      '${t('page')} ${context.pageNumber} / ${context.pagesCount}',
                      size: 8,
                      color: muted)
                ])),
        build: (_) => [
              pw.SizedBox(height: 22),
              line(name, bold: true, size: 26),
              pw.SizedBox(height: 10),
              ...paragraphs(request.scope),
              pw.Container(
                  margin: const pw.EdgeInsets.symmetric(vertical: 14),
                  padding: const pw.EdgeInsets.all(12),
                  color: pale,
                  child: line(
                      t(section.category == ExportCategory.certificates
                          ? 'certificateNotice'
                          : 'scopeNotice'),
                      color: muted,
                      size: 9)),
              if (section.lastFetched != null) ...[
                line(
                    '${t('lastFetched')}: ${DateFormat.yMMMd(locale).add_Hm().format(section.lastFetched!)}',
                    size: 9,
                    color: muted),
                pw.SizedBox(height: 12),
              ],
              if (section.category == ExportCategory.messages ||
                  section.category == ExportCategory.lessons)
                ...paragraphs(t('attachmentNotice')),
              if (section.semester != null) ...[
                line(l10n.semesterLabel(section.semester!),
                    bold: true, size: 12),
                pw.SizedBox(height: 12),
                line(
                    '${t('overallAverage')}: ${section.overallAverage == null ? '/' : number.format(section.overallAverage)}',
                    bold: true,
                    size: 16,
                    color: accent),
                pw.SizedBox(height: 10),
                ...paragraphs(t('averageNotice')),
                pw.TableHelper.fromTextArray(
                    headers: [t('field.subject'), t('average')],
                    data: [
                      for (final a in section.averages.entries)
                        for (final chunk
                            in exportTextChunks(a.key, length: 180).indexed)
                          [
                            chunk.$2,
                            if (chunk.$1 == 0 && a.value != null)
                              number.format(a.value! / 100)
                            else
                              ''
                          ]
                    ],
                    headerStyle: const pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        fontSize: 9),
                    headerDecoration: const pw.BoxDecoration(color: ink),
                    cellStyle: bodyStyle,
                    cellPadding: const pw.EdgeInsets.all(8),
                    oddRowDecoration: const pw.BoxDecoration(color: pale),
                    border: null,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(4),
                      1: const pw.FlexColumnWidth()
                    }),
                pw.SizedBox(height: 20),
              ],
              if (section.records.isEmpty) ...paragraphs(t('empty')),
              if (section.category == ExportCategory.grades)
                pw.TableHelper.fromTextArray(
                    headers: [
                      t('field.subject'),
                      t('field.date'),
                      t('field.grade'),
                      t('field.weight'),
                      t('field.type')
                    ],
                    data: [
                      for (final r in section.records)
                        for (final fragment in _gradeFragments(r, l10n, date))
                          fragment
                    ],
                    headerStyle: const pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                        fontSize: 8),
                    headerDecoration: const pw.BoxDecoration(color: ink),
                    cellStyle: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
                    cellPadding: const pw.EdgeInsets.all(7),
                    border: null,
                    oddRowDecoration: const pw.BoxDecoration(color: pale),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2.5),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(),
                      3: const pw.FlexColumnWidth(1.65),
                      4: const pw.FlexColumnWidth(2)
                    })
              else
                for (final r in section.records) ...[
                  pw.NewPage(freeSpace: 110),
                  pw.Container(
                      height: 3,
                      width: 28,
                      color: accent,
                      margin: const pw.EdgeInsets.only(top: 12, bottom: 10)),
                  for (final chunk in exportTextChunks(
                      r.title.isEmpty ? name : r.title,
                      length: 180))
                    line(chunk, bold: true, size: 13),
                  if (r.date != null)
                    pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6),
                        child: line(
                            (section.category == ExportCategory.messages
                                    ? DateFormat.yMMMd(locale).add_Hm()
                                    : DateFormat.yMMMd(locale))
                                .format(r.date!),
                            color: muted,
                            size: 9)),
                  for (final field
                      in r.fields.entries.where((f) => f.value.isNotEmpty))
                    ...paragraphs(
                        '${t('field.${field.key}')}: ${localizedField(field.key, field.value, l10n)}'),
                  ...paragraphs(r.body),
                  for (final table in r.tables) ...[
                    pw.SizedBox(height: 14),
                    pw.TableHelper.fromTextArray(
                        headerCount: 0,
                        data: _tableFragments(table),
                        cellStyle: bodyStyle,
                        cellPadding: const pw.EdgeInsets.all(9),
                        oddRowDecoration: const pw.BoxDecoration(color: pale),
                        border: const pw.TableBorder(
                            horizontalInside: pw.BorderSide(color: pale))),
                  ],
                  pw.SizedBox(height: 10),
                ],
            ]));
  }
  return document.save();
}

List<List<String>> _gradeFragments(
    ExportRecord r, AppLocalizations l10n, DateFormat date) {
  final subjects = exportTextChunks(r.subject ?? '', length: 90).toList();
  final types = exportTextChunks(
          '${r.fields['type'] ?? ''}${r.fields['cancelled'] == 'true' ? ' (${l10n.text('export.field.cancelled')})' : ''}',
          length: 70)
      .toList();
  final count = subjects.length > types.length ? subjects.length : types.length;
  return [
    for (var i = 0; i < count; i++)
      [
        if (i < subjects.length) subjects[i] else '',
        if (i == 0 && r.date != null) date.format(r.date!) else '',
        if (i == 0)
          localizedField('grade', r.fields['grade'] ?? '', l10n)
        else
          '',
        if (i == 0) '${r.fields['weight']} %' else '',
        if (i < types.length) types[i] else '',
      ]
  ];
}

/// Bound every indivisible PDF text widget, including unbroken URLs. Never
/// truncate content; rows and message paragraphs can span arbitrarily many pages.
Iterable<String> exportTextChunks(String value, {int length = 450}) sync* {
  for (final paragraph in value.split('\n')) {
    final runes = paragraph.runes.toList();
    for (var offset = 0; offset < runes.length;) {
      var end = (offset + length).clamp(0, runes.length);
      if (end < runes.length) {
        // Prefer word boundaries; split only truly unbroken words/URLs.
        for (var i = end - 1; i > offset + length ~/ 2; i--) {
          if (runes[i] == 32 || runes[i] == 9) {
            end = i + 1;
            break;
          }
        }
      }
      yield String.fromCharCodes(runes.sublist(offset, end));
      offset = end;
    }
  }
}

List<List<String>> _tableFragments(List<List<String>> table) {
  final columns =
      table.fold<int>(0, (n, row) => row.length > n ? row.length : n);
  final length = (360 ~/ columns.clamp(1, 12)).clamp(20, 120);
  final result = <List<String>>[];
  for (final row in table) {
    final cells = [
      for (final cell in row) exportTextChunks(cell, length: length).toList()
    ];
    final height =
        cells.fold<int>(1, (n, parts) => parts.length > n ? parts.length : n);
    for (var i = 0; i < height; i++) {
      result.add([
        for (var c = 0; c < columns; c++)
          if (c < cells.length && i < cells[c].length) cells[c][i] else ''
      ]);
    }
  }
  return result;
}
