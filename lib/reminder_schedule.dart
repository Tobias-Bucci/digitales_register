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

enum ReminderChannel {
  daily('reminder_daily'),
  assessment('reminder_assessment');

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

/// One notification the app wants the system to show.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.channel,
    required this.channelName,
    required this.at,
    required this.title,
    required this.body,
    this.repeatsDaily = false,
    this.payload,
  });

  final int id;
  final ReminderChannel channel;
  final String channelName;

  /// Local time. For a daily reminder only the time of day is relevant.
  final DateTime at;
  final String title;
  final String body;
  final bool repeatsDaily;
  final String? payload;

  /// Changes exactly when the system has to be told about this reminder again.
  /// [timeZone] matters for a daily reminder, which follows the wall clock.
  String fingerprint([String? timeZone]) => notificationDigest([
        if (repeatsDaily) ...[at.hour, at.minute, timeZone] else at.toUtc().toIso8601String(),
        title,
        body,
        channelName,
        payload,
      ]);

  /// This daily reminder as separate one-time reminders, for platforms that
  /// cannot repeat a notification. Ids depend on the date, so an occurrence
  /// keeps its id while the planned window moves forward.
  List<PlannedReminder> occurrences(DateTime now, int count) {
    final first = nextDailyOccurrence(now, at.hour, at.minute);
    return [
      for (var day = 0; day < count; day++)
        _occurrence(
          DateTime(first.year, first.month, first.day + day, at.hour, at.minute),
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
