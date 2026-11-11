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

import 'package:dr/school_notification_engine.dart';

/// iOS keeps only 64 pending notifications per app; stay safely below that.
const maxPendingReminders = 60;

/// How many days ahead a daily reminder is planned where the platform cannot
/// repeat it by itself. Every app start moves this window forward.
const dailyReminderOccurrences = 14;

/// By default, reminders of an assessment appear in the evening, when there
/// still is time to study and school is over.
const defaultAssessmentReminderMinuteOfDay = 18 * 60;

const defaultAssessmentReminderDays = [3, 2, 1];
const maxAssessmentReminderDay = 30;
const maxAssessmentReminderDayCount = 10;

/// The weekdays of the Mensa reminder unless the user picks others: the days
/// with school lunch, Monday to Friday ([DateTime.monday] = 1).
const defaultMensaReminderWeekdays = [1, 2, 3, 4, 5];

/// The valid ISO weekdays of [weekdays] without duplicates, Monday first. An
/// empty result falls back to [defaultMensaReminderWeekdays], because the
/// reminder always has at least one day.
List<int> normalizeReminderWeekdays(Iterable<int> weekdays) {
  final valid = weekdays
      .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
      .toSet()
      .toList()
    ..sort();
  return valid.isEmpty ? List.of(defaultMensaReminderWeekdays) : valid;
}

/// Which switch decides about the reminders of an assessment.
enum AssessmentReminderKind { exam, test }

/// Whether the assessment type [typeName] (the server's type name or the type
/// of a local `/test`, `/cw` or `/exam` reminder) is a test. A name that says
/// "test" in one of the app's languages (Test, Testarbeit, Praktischer Test,
/// Verifica, Tesć) is a test; everything else, including unknown and missing
/// names, is an exam, the more important group.
AssessmentReminderKind assessmentReminderKind(String? typeName) {
  final words =
      (typeName ?? '').toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true));
  final isTest = words.any(
    (word) =>
        word.startsWith('test') ||
        word.startsWith('tesć') ||
        word.startsWith('verific'),
  );
  return isTest ? AssessmentReminderKind.test : AssessmentReminderKind.exam;
}

enum ReminderDayError { invalid, tooLarge, duplicate }

/// Why [input] cannot be added to the [existing] reminder days, if at all.
ReminderDayError? validateReminderDay(String input, Iterable<int> existing) {
  final text = input.trim();
  if (!RegExp(r'^[0-9]+$').hasMatch(text)) return ReminderDayError.invalid;
  final day = int.tryParse(text);
  if (day == null) return ReminderDayError.tooLarge;
  if (day < 1) return ReminderDayError.invalid;
  if (day > maxAssessmentReminderDay) return ReminderDayError.tooLarge;
  return existing.contains(day) ? ReminderDayError.duplicate : null;
}

/// The valid days of [days] without duplicates, the furthest one first.
List<int> normalizeReminderDays(Iterable<int> days) => days
    .where((day) => day >= 1 && day <= maxAssessmentReminderDay)
    .toSet()
    .toList()
  ..sort((a, b) => b.compareTo(a));

/// When to remind of an assessment on [date], [daysBefore] days ahead, at
/// [minuteOfDay] minutes after midnight. Counts calendar days, so the time
/// stays the same across daylight saving changes.
DateTime assessmentReminderTime(
  DateTime date,
  int daysBefore,
  int minuteOfDay,
) =>
    DateTime(
      date.year,
      date.month,
      date.day - daysBefore,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );

enum ReminderChannel {
  daily('reminder_daily'),
  assessment('reminder_assessment'),
  homework('reminder_homework');

  const ReminderChannel(this.id);
  final String id;
}

/// A stable notification id, so that planning the same reminder twice replaces
/// it instead of showing a duplicate.
int reminderNotificationId(Object key) => int.parse(
      notificationDigest(['reminder', key]).substring(0, 7),
      radix: 16,
    );

/// The first time [hour]:[minute] happens after [now], in local time.
DateTime nextDailyOccurrence(DateTime now, int hour, int minute) {
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  return today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, hour, minute);
}

/// The first time [hour]:[minute] on the ISO [weekday] happens after [now], in
/// local time.
DateTime nextWeeklyOccurrence(
  DateTime now,
  int weekday,
  int hour,
  int minute,
) {
  final next = nextDailyOccurrence(now, hour, minute);
  return DateTime(
    next.year,
    next.month,
    next.day + (weekday - next.weekday) % 7,
    hour,
    minute,
  );
}

/// One notification the app wants the system to show.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.channel,
    required this.channelName,
    required this.at,
    required this.title,
    required this.body,
    this.repeats = false,
    this.weekday,
    this.payload,
  });

  final int id;
  final ReminderChannel channel;
  final String channelName;

  /// Local time. For a repeating reminder only the time of day is relevant.
  final DateTime at;
  final String title;
  final String body;

  /// Whether the reminder repeats: every day, or weekly on [weekday].
  final bool repeats;

  /// For a repeating reminder, the ISO weekday it repeats on; null for every
  /// day.
  final int? weekday;
  final String? payload;

  /// The next time this reminder is due after [now].
  DateTime nextAt(DateTime now) {
    if (!repeats) return at;
    final weekday = this.weekday;
    return weekday == null
        ? nextDailyOccurrence(now, at.hour, at.minute)
        : nextWeeklyOccurrence(now, weekday, at.hour, at.minute);
  }

  /// Changes exactly when the system has to be told about this reminder again.
  /// [timeZone] matters for a repeating reminder, which follows the wall clock.
  String fingerprint([String? timeZone]) => notificationDigest([
        if (repeats) ...[
          at.hour,
          at.minute,
          if (weekday != null) 'weekday:$weekday',
          timeZone,
        ] else
          at.toUtc().toIso8601String(),
        title,
        body,
        channelName,
        payload,
      ]);

  /// The occurrences of this repeating reminder within the next [days] days as
  /// separate one-time reminders, for platforms that cannot repeat a
  /// notification. Ids depend on the date, so an occurrence keeps its id while
  /// the planned window moves forward.
  List<PlannedReminder> occurrences(DateTime now, int days) {
    final first = nextDailyOccurrence(now, at.hour, at.minute);
    return [
      for (var day = 0; day < days; day++)
        if (DateTime(first.year, first.month, first.day + day) case final date
            when weekday == null || date.weekday == weekday)
          _occurrence(
            DateTime(date.year, date.month, date.day, at.hour, at.minute),
          ),
    ];
  }

  PlannedReminder _occurrence(DateTime date) => PlannedReminder(
        id: reminderNotificationId(
          [id, date.year, date.month, date.day],
        ),
        channel: channel,
        channelName: channelName,
        at: date,
        title: title,
        body: body,
        payload: payload,
      );
}
