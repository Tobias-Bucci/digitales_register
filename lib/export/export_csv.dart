// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:typed_data';
import 'package:dr/export/export_data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:intl/intl.dart';

/// BOM + semicolon + CRLF for German/Italian Excel. Quote every cell and
/// neutralize spreadsheet formulas supplied by register users.
Uint8List createExportCsv(ExportSection section, AppLocalizations l10n) {
  final keys = <String>{for (final row in section.records) ...row.fields.keys};
  if (section.category == ExportCategory.grades) {
    keys.addAll(['average', 'overallAverage']);
  }
  String cell(String value) {
    final safe = RegExp(r'^[\s\u0000-\u001f]*[=+@-]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String fieldValue(ExportRecord row, String key) {
    final format = NumberFormat('0.00', l10n.locale.languageCode);
    if (key == 'average') {
      final average = section.averages[row.subject];
      return average == null ? '' : format.format(average / 100);
    }
    if (key == 'overallAverage') {
      return section.overallAverage == null
          ? ''
          : format.format(section.overallAverage);
    }
    return localizedField(key, row.fields[key] ?? '', l10n);
  }

  final lines = <List<String>>[
    ['id', 'date', 'title', ...keys, 'content']
        .map((k) => l10n.text('export.field.$k'))
        .toList(),
    for (final row in section.records)
      [
        row.id,
        if (row.date == null)
          ''
        else
          row.date!.toIso8601String().substring(0, 16).replaceFirst('T', ' '),
        row.title,
        for (final key in keys) fieldValue(row, key),
        [
          row.body,
          for (final table in row.tables)
            for (final cells in table) cells.join(' | ')
        ].where((s) => s.isNotEmpty).join('\n')
      ],
  ];
  return Uint8List.fromList(utf8.encode(
      '\uFEFF${lines.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n'));
}

String localizedField(String key, String value, AppLocalizations l10n) {
  if (value.isEmpty) return value;
  if (key == 'grade') {
    return NumberFormat('0.##', l10n.locale.languageCode)
        .format(double.parse(value));
  }
  if (key == 'cancelled') {
    return l10n.text('export.${value == 'true' ? 'yes' : 'no'}');
  }
  if (key == 'status') {
    const statuses = {
      'justified': 'yes',
      'notJustified': 'no',
      'notYetJustified': 'pending',
      'forSchool': 'school'
    };
    return l10n.text('export.status.${statuses[value] ?? 'unknown'}');
  }
  return value;
}
