// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:built_collection/built_collection.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/data.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

enum ExportCategory {
  certificates,
  grades,
  messages,
  timetable,
  exams,
  tasks,
  absences,
  lessons
}

enum ExportFormat { pdf, csv }

/// Only calendar coordinates are compared: register timestamps deliberately
/// retain school wall time in UtcDateTime, just like the existing UI.
class ExportFilter {
  const ExportFilter(
      {this.schoolYear,
      this.semester,
      this.subject,
      this.from,
      this.until,
      this.ids});
  final int? schoolYear;
  final Semester? semester;
  final String? subject;
  final DateTime? from;
  final DateTime? until;
  final Set<String>? ids;

  bool accepts(DateTime? date, {String? subjectName, String? id}) {
    if (subject != null && subject != subjectName) return false;
    if (ids != null && !ids!.contains(id)) return false;
    if (date == null) {
      return schoolYear == null && from == null && until == null;
    }
    final day = calendarDate(date);
    return (schoolYear == null || exportSchoolYear(day) == schoolYear) &&
        (from == null || !day.isBefore(calendarDate(from!))) &&
        (until == null || !day.isAfter(calendarDate(until!)));
  }
}

int exportSchoolYear(DateTime date) =>
    date.month >= 7 ? date.year : date.year - 1;

class ExportRecord {
  const ExportRecord(
      {required this.id,
      required this.title,
      required this.fields,
      this.date,
      this.subject,
      this.tables = const [],
      this.body = ''});
  final String id;
  final String title;
  final DateTime? date;
  final String? subject;

  /// Keys are localization suffixes, values are actual register data.
  final Map<String, String> fields;
  final String body;
  final List<List<List<String>>> tables;
}

class ExportSection {
  const ExportSection(this.category, this.records,
      {this.averages = const {},
      this.overallAverage,
      this.semester,
      this.lastFetched});
  final ExportCategory category;
  final List<ExportRecord> records;
  final Map<String, int?> averages;
  final double? overallAverage;
  final Semester? semester;
  final DateTime? lastFetched;
}

/// Pure projection of an immutable store snapshot. Never queries a second API,
/// changes the selected semester, or combines data from different accounts.
class ExportDataSource {
  const ExportDataSource(this.state);
  final AppState state;

  List<ExportRecord> records(ExportCategory category) {
    final rows = <ExportRecord>[];
    switch (category) {
      case ExportCategory.certificates:
        final certificate = html.parse(state.certificateState.html ?? '');
        final tables = <List<List<String>>>[];
        for (final table in certificate.querySelectorAll('table')) {
          final rows = [
            for (final row in table.querySelectorAll('tr'))
              [
                for (final cell in row.children
                    .where((c) => c.localName == 'td' || c.localName == 'th'))
                  readableHtml(cell.innerHtml)
              ]
          ];
          if (rows.any((r) => r.isNotEmpty)) {
            tables.add(rows.where((r) => r.isNotEmpty).toList());
          }
          table.remove();
        }
        final text = readableHtml(certificate.outerHtml);
        if (text.isNotEmpty || tables.isNotEmpty) {
          rows.add(ExportRecord(
              id: 'certificate',
              title: '',
              fields: const {},
              body: text,
              tables: tables));
        }
      case ExportCategory.grades:
        for (final subject in state.gradesState.subjects) {
          for (final semester in [Semester.first, Semester.second]) {
            final grades = subject.gradesAll[semester];
            if (grades == null) continue;
            for (var i = 0; i < grades.length; i++) {
              final grade = grades[i];
              rows.add(ExportRecord(
                  id: '${subject.name}:${semester.n}:$i',
                  title: subject.name,
                  date: grade.date,
                  subject: subject.name,
                  fields: {
                    'grade': grade.grade == null ? '' : '${grade.grade! / 100}',
                    'weight': '${grade.weightPercentage}',
                    'type': grade.type,
                    'semester': '${semester.n}',
                    'cancelled': '${grade.cancelled}'
                  }));
            }
          }
        }
      case ExportCategory.messages:
        for (final message in state.messagesState.messages) {
          rows.add(ExportRecord(
              id: '${message.id}',
              title: message.subject,
              date: message.timeSent,
              fields: {
                'sender': message.fromName,
                'recipient': message.recipientString,
                'attachments':
                    message.attachments.map((a) => a.originalName).join('\n')
              },
              body: readableMessage(message.text)));
        }
      case ExportCategory.absences:
        for (var i = 0; i < state.absencesState.absences.length; i++) {
          final group = state.absencesState.absences[i];
          // Individual entries retain dates even for multi-day groups.
          if (group.absences.isEmpty) {
            rows.add(ExportRecord(
                id: 'group:$i',
                title: '',
                date: group.date,
                fields: {
                  'hours': '${group.hours}',
                  'minutes': '${group.minutes}',
                  'status': group.justified.name,
                  'reason': group.reason ?? ''
                },
                body: group.note ?? ''));
          } else {
            for (var j = 0; j < group.absences.length; j++) {
              final absence = group.absences[j];
              rows.add(ExportRecord(
                  id: 'group:$i:$j',
                  title: '',
                  date: absence.date,
                  fields: {
                    'hour': '${absence.hour}',
                    'minutes': '${absence.minutes}',
                    'late': '${absence.minutesCameTooLate}',
                    'early': '${absence.minutesLeftTooEarly}',
                    'status': (absence.justified ?? group.justified).name,
                    'reason': absence.reason ?? group.reason ?? ''
                  },
                  body: absence.note ?? group.note ?? ''));
            }
          }
        }
      case ExportCategory.timetable:
      case ExportCategory.exams:
      case ExportCategory.tasks:
      case ExportCategory.lessons:
        final seen = <int>{};
        for (final day in state.calendarState.days.values) {
          for (var i = 0; i < day.hours.length; i++) {
            final hour = day.hours[i];
            final id = '${day.date.toIso8601String()}:$i';
            if (category == ExportCategory.timetable) {
              rows.add(ExportRecord(
                  id: id,
                  title: hour.subject,
                  subject: hour.subject,
                  date: day.date,
                  fields: {
                    'hour': '${hour.fromHour}-${hour.toHour}',
                    'time': hour.timeSpans
                        .map((t) => '${_time(t.from)}-${_time(t.to)}')
                        .join(', '),
                    'teacher': hour.teachers.map((t) => t.fullName).join(', '),
                    'room': hour.rooms.join(', '),
                    'class': hour.className ?? ''
                  }));
            } else if (category == ExportCategory.lessons) {
              for (var j = 0; j < hour.lessonContents.length; j++) {
                final content = hour.lessonContents[j];
                rows.add(ExportRecord(
                    id: '$id:$j',
                    title: content.typeName,
                    subject: hour.subject,
                    date: day.date,
                    fields: {
                      'subject': hour.subject,
                      'attachments': content.submissions
                          .map((s) => s.originalName)
                          .join('\n')
                    },
                    body: readableHtml(content.name)));
              }
            } else {
              for (final task in hour.homeworkExams) {
                if (task.homework != (category == ExportCategory.tasks) ||
                    !seen.add(task.id)) {
                  continue;
                }
                rows.add(ExportRecord(
                    id: '${task.id}',
                    title: task.typeName,
                    subject: hour.subject,
                    date: task.deadline,
                    fields: {'subject': hour.subject, 'type': task.typeName},
                    body: readableHtml(task.name)));
              }
            }
          }
        }
    }
    rows.sort((a, b) {
      final date = (a.date ?? DateTime(1)).compareTo(b.date ?? DateTime(1));
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    return rows;
  }

  ExportSection section(ExportCategory category, ExportFilter filter) {
    // Certificates have no reliable machine-readable school-year metadata.
    // The UI therefore offers the loaded document without date/semester filters.
    final selected = records(category)
        .where((r) => filter.accepts(r.date, subjectName: r.subject, id: r.id))
        .where((r) =>
            category != ExportCategory.grades ||
            filter.semester == null ||
            filter.semester == Semester.all ||
            r.fields['semester'] == '${filter.semester!.n}')
        .toList();
    if (category != ExportCategory.grades) {
      return ExportSection(category, selected,
          lastFetched: switch (category) {
            ExportCategory.certificates => state.certificateState.lastFetched,
            ExportCategory.messages => state.messagesState.lastFetched,
            ExportCategory.absences => state.absencesState.lastFetched,
            _ => null,
          });
    }
    final semester = filter.semester ?? Semester.all;
    final selectedIds = selected.map((r) => r.id).toSet();
    final subjects = state.gradesState.subjects
        .map((s) => s.rebuild((b) {
              b.gradesAll = MapBuilder({
                for (final period in [Semester.first, Semester.second])
                  period: BuiltList<GradeAll>([
                    for (var i = 0; i < (s.gradesAll[period]?.length ?? 0); i++)
                      if (selectedIds.contains('${s.name}:${period.n}:$i'))
                        s.gradesAll[period]![i],
                  ]),
              });
            }))
        .where((s) => selected.any((r) => r.subject == s.name))
        .toList();
    final filteredState = state.rebuild((b) => b.gradesState
      ..semester.replace(semester)
      ..subjects.replace(subjects));
    return ExportSection(category, selected,
        semester: semester,
        averages: {
          for (final subject in subjects)
            subject.name: subject.average(semester)
        },
        overallAverage: overallGradeAverage(filteredState));
  }

  List<int> schoolYears(Iterable<ExportCategory> categories) => ({
        for (final c in categories)
          for (final r in records(c))
            if (r.date != null) exportSchoolYear(r.date!),
      }.toList()
        ..sort((a, b) => b.compareTo(a)));

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Extract structural text, never execute HTML or fetch images/tracking URLs.
/// Keep table cells and line breaks, discard script/style and hidden content.
String readableHtml(String input) {
  if (!input.contains('<')) return input.trim();
  final document = html.parse(input);
  for (final node
      in document.querySelectorAll('script, style, noscript, head, [hidden]')) {
    node.remove();
  }
  final buffer = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName;
    if (tag == 'br') buffer.write('\n');
    for (final child in node.nodes) {
      walk(child);
    }
    if (tag == 'td' || tag == 'th') buffer.write(' | ');
    if (['p', 'div', 'tr', 'li', 'h1', 'h2', 'h3', 'section', 'table']
        .contains(tag)) {
      buffer.write('\n');
    }
  }

  walk(document.body!);
  return buffer
      .toString()
      .split('\n')
      .map((line) => line.trim().replaceFirst(RegExp(r'\s*\|$'), ''))
      .where((s) => s.isNotEmpty)
      .join('\n');
}

/// Register messages primarily use Quill Delta JSON, with HTML on older
/// servers. Embedded media is intentionally not downloaded.
String readableMessage(String input) {
  try {
    final decoded = jsonDecode(input);
    if (decoded is Map && decoded['ops'] is List) {
      final result = StringBuffer();
      for (final op in decoded['ops'] as List) {
        if (op is Map && op['insert'] is String) result.write(op['insert']);
      }
      return result.toString().trim();
    }
  } on FormatException {
    // Not Delta JSON; use the legacy HTML/plain-text representation.
  }
  return readableHtml(input);
}
