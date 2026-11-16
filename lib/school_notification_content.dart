// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

/// Pure building blocks of the detailed school notifications (#133): what an
/// event says, how it reads in the app language, the dashboard snapshot that
/// reveals changed grades and new homework, and the retry back-off. Nothing
/// here touches storage, the network or the notification plugin.
library;

import 'dart:math' as math;

import 'package:dr/data.dart' show parseBackendGradeHundredths;
import 'package:dr/i18n/app_language.dart';

/// Kinds of one detected event. Several kinds share one notification
/// (see [SchoolNotificationGroup]).
enum SchoolNotificationKind {
  gradeNew,
  gradeChanged,
  gradeDeleted,
  message,
  homework,
  test,
  absence,
  observation,
}

/// One system notification per group, account and check.
enum SchoolNotificationGroup { grade, message, homework, other }

SchoolNotificationGroup schoolNotificationGroupOf(
        SchoolNotificationKind kind) =>
    switch (kind) {
      SchoolNotificationKind.gradeNew ||
      SchoolNotificationKind.gradeChanged ||
      SchoolNotificationKind.gradeDeleted =>
        SchoolNotificationGroup.grade,
      SchoolNotificationKind.message => SchoolNotificationGroup.message,
      SchoolNotificationKind.homework ||
      SchoolNotificationKind.test =>
        SchoolNotificationGroup.homework,
      SchoolNotificationKind.absence ||
      SchoolNotificationKind.observation =>
        SchoolNotificationGroup.other,
    };

/// What a notification may say about one event. Every field but [kind] is
/// optional: an event without data is shown with the generic text.
class SchoolNotificationItem {
  const SchoolNotificationItem(
    this.kind, {
    this.subject,
    this.grade,
    this.oldGrade,
    this.description,
    this.sender,
    this.objectId,
  });

  final SchoolNotificationKind kind;
  final String? subject;

  /// Hundredths, as the app stores grades: 850 is 8.5.
  final int? grade;
  final int? oldGrade;

  /// A short text, such as a message subject or the homework title.
  final String? description;

  /// The sender of a message.
  final String? sender;
  final int? objectId;

  SchoolNotificationGroup get group => schoolNotificationGroupOf(kind);

  bool get hasDetails => switch (kind) {
        SchoolNotificationKind.gradeNew ||
        SchoolNotificationKind.gradeDeleted =>
          _filled(subject) && grade != null,
        SchoolNotificationKind.gradeChanged =>
          _filled(subject) && grade != null && oldGrade != null,
        SchoolNotificationKind.message => _filled(description),
        _ => _filled(subject) || _filled(description),
      };
}

bool _filled(String? value) => value != null && value.trim().isNotEmpty;

/// The grade as a notification shows it in [language]: whole grades as they
/// are, quarter grades as the register writes them (8+, 9-), every other value
/// as a decimal number with the language's separator (8,5 in de/it/lld, 8.5
/// in en).
String formatNotificationGrade(int hundredths, AppLanguage language) {
  final whole = hundredths ~/ 100;
  final rest = hundredths % 100;
  if (hundredths >= 0) {
    if (rest == 0) return '$whole';
    if (rest == 25) return '$whole+';
    if (rest == 75) return '${whole + 1}-';
  }
  var text = (hundredths / 100).toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return language == AppLanguage.en ? text : text.replaceAll('.', ',');
}

/// The finished text of one notification.
class SchoolNotificationText {
  const SchoolNotificationText(this.title, this.body, this.lines);
  final String title;
  final String body;

  /// One line per event when details are shown and there are several events;
  /// empty otherwise. Android shows them in inbox style.
  final List<String> lines;
}

/// Maximum event lines in one notification; the rest is "+n more".
const schoolNotificationMaxLines = 5;

/// Builds the text of one grouped notification.
///
/// [text] looks up a localization key, as `AppLocalizations.text` does, and
/// [subjectName] translates a subject name when the user enabled that. With
/// [details] off, or when no event carries data, the result is exactly the
/// generic text earlier versions showed.
SchoolNotificationText buildSchoolNotificationText({
  required SchoolNotificationGroup group,
  required List<SchoolNotificationItem> items,
  required bool details,
  required bool showCount,
  required AppLanguage language,
  required String Function(String key, {Map<String, String> args}) text,
  String Function(String subject)? subjectName,
}) {
  assert(items.isNotEmpty);
  final count = items.length;
  final kinds = items.map((item) => item.kind).toSet();
  final single = count == 1;
  final kind = items.first.kind;

  String singleTitle(SchoolNotificationKind kind) => text(switch (kind) {
        SchoolNotificationKind.gradeNew => 'schoolNotifications.grade.title',
        SchoolNotificationKind.message => 'schoolNotifications.message.title',
        _ => 'schoolNotifications.kind.${kind.name}.title',
      });
  String singleBody(SchoolNotificationKind kind) => text(switch (kind) {
        SchoolNotificationKind.gradeNew => 'schoolNotifications.grade.body',
        SchoolNotificationKind.message => 'schoolNotifications.message.body',
        _ => 'schoolNotifications.kind.${kind.name}.body',
      });
  // Grades mixed with changes are "grade updates", not "new grades".
  final groupKey = group == SchoolNotificationGroup.grade &&
          kinds.any((kind) => kind != SchoolNotificationKind.gradeNew)
      ? 'schoolNotifications.gradeUpdates'
      : 'schoolNotifications.${group.name}';

  final detailed = details && items.any((item) => item.hasDetails);
  if (!detailed) {
    if (single) {
      return SchoolNotificationText(singleTitle(kind), singleBody(kind), []);
    }
    return SchoolNotificationText(
        text('$groupKey.${showCount ? 'pluralTitle' : 'multipleTitle'}',
            args: {'count': '$count'}),
        text('$groupKey.pluralBody'),
        []);
  }

  String grade(int value) => formatNotificationGrade(value, language);
  String subject(SchoolNotificationItem item) =>
      subjectName?.call(item.subject!.trim()) ?? item.subject!.trim();
  String line(SchoolNotificationItem item) {
    if (!item.hasDetails) return singleBody(item.kind);
    final description = item.description?.trim() ?? '';
    return switch (item.kind) {
      SchoolNotificationKind.gradeNew => text(
          'schoolNotifications.line.gradeNew',
          args: {'subject': subject(item), 'grade': grade(item.grade!)}),
      SchoolNotificationKind.gradeChanged =>
        text('schoolNotifications.line.gradeChanged', args: {
          'subject': subject(item),
          'old': grade(item.oldGrade!),
          'new': grade(item.grade!),
        }),
      SchoolNotificationKind.gradeDeleted => text(
          'schoolNotifications.line.gradeDeleted',
          args: {'subject': subject(item), 'grade': grade(item.grade!)}),
      SchoolNotificationKind.message => _filled(item.sender)
          ? text('schoolNotifications.line.message',
              args: {'sender': item.sender!.trim(), 'subject': description})
          : description,
      _ => _filled(item.subject) && description.isNotEmpty
          ? text('schoolNotifications.line.described',
              args: {'subject': subject(item), 'description': description})
          : _filled(item.subject)
              ? subject(item)
              : description,
    };
  }

  if (single) {
    return SchoolNotificationText(singleTitle(kind), line(items.single), []);
  }
  final lines = [
    for (final item in items.take(schoolNotificationMaxLines)) line(item),
    if (count > schoolNotificationMaxLines)
      text('dashboard.banner.more',
          args: {'count': '${count - schoolNotificationMaxLines}'}),
  ];
  return SchoolNotificationText(
      text('$groupKey.pluralTitle', args: {'count': '$count'}),
      lines.join('\n'),
      lines);
}

// ---------------------------------------------------------------------------
// Dashboard snapshot

/// One dashboard entry worth comparing between two checks.
class SchoolDashboardEntry {
  const SchoolDashboardEntry({
    required this.id,
    required this.kind,
    required this.day,
    this.subject,
    this.grade,
    this.description,
  });

  final int id;

  /// `grade`, `homework` (teacher homework) or `test`.
  final String kind;
  final String day;
  final String? subject;
  final int? grade;
  final String? description;

  String get key => '${kind == 'grade' ? 'g' : 'h'}:$id';

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'day': day,
        if (subject != null) 'subject': subject,
        if (grade != null) 'grade': grade,
        if (description != null) 'description': description,
      };

  static SchoolDashboardEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = json['kind'];
    final day = json['day'];
    if (id is! int || kind is! String || day is! String) return null;
    return SchoolDashboardEntry(
      id: id,
      kind: kind,
      day: day,
      subject: json['subject'] as String?,
      grade: json['grade'] as int?,
      description: json['description'] as String?,
    );
  }
}

/// The entries of one dashboard response (`api/student/dashboard/dashboard`),
/// keyed by [SchoolDashboardEntry.key]. Returns null for a response that is not
/// a list of days, so a broken response never becomes an empty baseline.
/// Reminders the user wrote (`homework`) and observations are not school
/// events of their own here.
Map<String, SchoolDashboardEntry>? parseSchoolDashboard(Object? response) {
  if (response is! List) return null;
  final entries = <String, SchoolDashboardEntry>{};
  for (final day in response) {
    if (day is! Map) return null;
    final date = day['date'];
    final items = day['items'];
    if (date is! String || items is! List) return null;
    for (final item in items) {
      if (item is! Map) continue;
      final rawId = item['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      if (id == null) continue;
      final kind = switch (item['type']) {
        'grade' => 'grade',
        'lessonHomework' => 'homework',
        'gradeGroup' => 'test',
        _ => null,
      };
      if (kind == null) continue;
      String? text(Object? value) =>
          value is String && value.trim().isNotEmpty ? value.trim() : null;
      final entry = SchoolDashboardEntry(
        id: id,
        kind: kind,
        day: date.length >= 10 ? date.substring(0, 10) : date,
        subject: text(item['label']),
        grade: kind == 'grade'
            ? parseBackendGradeHundredths(
                item['grade'] == null ? null : '${item['grade']}')
            : null,
        description: text(item['subtitle']) ?? text(item['title']),
      );
      entries[entry.key] = entry;
    }
  }
  return entries;
}

/// An event found by comparing two snapshots, with the key that marks it as
/// notified once.
class SchoolDashboardChange {
  const SchoolDashboardChange(this.key, this.item);
  final String key;
  final SchoolNotificationItem item;
}

/// Compares the previous and the current entries of the same dashboard view.
///
/// - Without [previous] the snapshot is a quiet baseline: no events.
/// - A grade whose value changed → gradeChanged.
/// - A grade that is gone while its day is still in [current] → gradeDeleted.
///   A grade whose day left the dashboard window is not a deletion.
/// - Homework and tests that are new → homework / test.
/// - Keys in [notified] were shown before and are skipped.
List<SchoolDashboardChange> diffSchoolDashboard(
  Map<String, SchoolDashboardEntry>? previous,
  Map<String, SchoolDashboardEntry> current, {
  Set<String> notified = const {},
}) {
  if (previous == null) return const [];
  final changes = <SchoolDashboardChange>[];
  final days = current.values.map((entry) => entry.day).toSet();
  for (final entry in current.values) {
    final before = previous[entry.key];
    if (entry.kind == 'grade') {
      if (before != null &&
          before.grade != null &&
          entry.grade != null &&
          before.grade != entry.grade) {
        changes.add(SchoolDashboardChange(
            'c:${entry.id}:${before.grade}:${entry.grade}',
            SchoolNotificationItem(SchoolNotificationKind.gradeChanged,
                subject: entry.subject ?? before.subject,
                grade: entry.grade,
                oldGrade: before.grade,
                description: entry.description,
                objectId: entry.id)));
      }
    } else if (before == null) {
      changes.add(SchoolDashboardChange(
          'n:${entry.id}',
          SchoolNotificationItem(
              entry.kind == 'test'
                  ? SchoolNotificationKind.test
                  : SchoolNotificationKind.homework,
              subject: entry.subject,
              description: entry.description,
              objectId: entry.id)));
    }
  }
  for (final before in previous.values) {
    if (before.kind != 'grade' ||
        current.containsKey(before.key) ||
        !days.contains(before.day)) {
      continue;
    }
    changes.add(SchoolDashboardChange(
        'd:${before.id}',
        SchoolNotificationItem(SchoolNotificationKind.gradeDeleted,
            subject: before.subject,
            grade: before.grade,
            description: before.description,
            objectId: before.id)));
  }
  return [
    for (final change in changes)
      if (!notified.contains(change.key)) change
  ];
}

/// Notified snapshot keys kept per account. Old keys only matter while their
/// entries are still on the dashboard, which spans a few weeks.
const schoolNotificationNotifiedLimit = 1000;

List<String> rememberNotified(
    Iterable<String> existing, Iterable<String> added) {
  final all = [...existing.where((key) => !added.contains(key)), ...added];
  return all.length <= schoolNotificationNotifiedLimit
      ? all
      : all.sublist(all.length - schoolNotificationNotifiedLimit);
}

/// How often the dashboards are read without a new grade in the feed. The
/// unread feed stays the 15-minute signal; this keeps the extra load on the
/// school servers to two requests per hour and account.
const schoolDashboardInterval = Duration(minutes: 60);

bool schoolDashboardDue(DateTime? lastRead, DateTime now) =>
    lastRead == null ||
    now.isBefore(lastRead) ||
    now.difference(lastRead) >= schoolDashboardInterval;

// ---------------------------------------------------------------------------
// Back-off

/// The pause after [failures] consecutive failed checks of one account
/// (network, time-out, server error). The first failure retries on the next
/// run; further failures wait 15, 30, 60 and at most 120 minutes, so an
/// unreachable school is not asked every 15 minutes by every device.
Duration schoolNotificationRetryDelay(int failures) {
  if (failures <= 1) return Duration.zero;
  final minutes = 15 * math.pow(2, math.min(failures - 2, 3)).toInt();
  return Duration(minutes: math.min(minutes, 120));
}

/// Whether an account with [failures] consecutive failures, the last at
/// [lastFailure], may be checked at [now].
bool schoolNotificationRetryAllowed(
    int failures, DateTime? lastFailure, DateTime now) {
  if (failures <= 1 || lastFailure == null || now.isBefore(lastFailure)) {
    return true;
  }
  return now.difference(lastFailure) >= schoolNotificationRetryDelay(failures);
}
