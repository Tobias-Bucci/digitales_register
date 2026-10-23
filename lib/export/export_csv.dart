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
  final keys = switch (section.category) {
    ExportCategory.grades => [
        'date',
        'subject',
        'semester',
        'grade',
        'weight',
        'type',
        'cancelled',
        'average',
        'overallAverage'
      ],
    ExportCategory.messages => [
        'date',
        'title',
        'sender',
        'recipient',
        'content',
        'attachments'
      ],
    ExportCategory.timetable => [
        'date',
        'weekday',
        'hour',
        'time',
        'subject',
        'teacher',
        'room',
        'class'
      ],
    ExportCategory.exams || ExportCategory.tasks => [
        'date',
        'subject',
        'type',
        'content'
      ],
    ExportCategory.lessons => [
        'date',
        'subject',
        'type',
        'content',
        'attachments'
      ],
    ExportCategory.absences => [
        'date',
        'hour',
        'minutes',
        'late',
        'early',
        'status',
        'reason',
        'content'
      ],
    ExportCategory.certificates => ['title', 'content'],
  };
  String cell(String value) {
    final safe = RegExp(r'^[\s\u0000-\u001f]*[=+@-]').hasMatch(value)
        ? "'$value"
        : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  String fieldValue(ExportRecord row, String key) {
    if (key == 'date') {
      if (row.date == null) return '';
      final iso = row.date!.toIso8601String();
      return [
        ExportCategory.messages,
        ExportCategory.exams,
        ExportCategory.tasks
      ].contains(section.category)
          ? iso.substring(0, 16).replaceFirst('T', ' ')
          : iso.substring(0, 10);
    }
    if (key == 'subject') return row.subject ?? row.title;
    if (key == 'title') return row.title;
    if (key == 'content') return row.body;
    if (key == 'type') return row.fields[key] ?? row.title;
    if (key == 'hour') return row.fields[key] ?? row.fields['hours'] ?? '';
    if (key == 'weekday') {
      const names = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday'
      ];
      return row.date == null
          ? ''
          : l10n.text('weekday.${names[row.date!.weekday - 1]}');
    }
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
    keys.map((k) => l10n.text('export.field.$k')).toList(),
    for (final row in section.records)
      if (section.category == ExportCategory.certificates) ...[
        if (row.body.isNotEmpty)
          [l10n.text('export.category.certificates'), row.body],
        for (final table in row.tables)
          for (final cells in table) [cells.first, cells.skip(1).join(' / ')],
      ] else
        [for (final key in keys) fieldValue(row, key)],
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
