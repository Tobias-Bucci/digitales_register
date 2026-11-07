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

import 'package:dr/data.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/foundation.dart';

/// One entry of the notification center, from either source.
@immutable
sealed class NotificationFeedEntry {
  const NotificationFeedEntry();

  /// Wall-clock time, the form the school's timestamps come in.
  UtcDateTime get time;
}

class SchoolFeedEntry extends NotificationFeedEntry {
  const SchoolFeedEntry(this.notification);

  final Notification notification;

  @override
  UtcDateTime get time => notification.timeSent;
}

class AppFeedEntry extends NotificationFeedEntry {
  const AppFeedEntry(this.notification);

  final ServerNotification notification;

  @override
  UtcDateTime get time =>
      UtcDateTime.makeUtc(notification.publishedAt.toLocal());
}

/// Both sources in one list, newest first. Each source keeps its own order
/// among entries of the same moment.
List<NotificationFeedEntry> combinedNotificationFeed({
  required Iterable<Notification> school,
  required Iterable<ServerNotification> app,
}) {
  final entries = <NotificationFeedEntry>[
    ...school.map(SchoolFeedEntry.new),
    ...app.map(AppFeedEntry.new),
  ];
  // List.sort is not stable, and the order of equal times has to be.
  final order = {
    for (var i = 0; i < entries.length; i++) entries[i]: i,
  };
  return entries
    ..sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
    });
}

/// The school notification the next notification center opens, as when an
/// inline notification on the dashboard is tapped. Read once, then cleared.
final ValueNotifier<int?> notificationCenterFocus = ValueNotifier(null);

/// Reads [notificationCenterFocus] and clears it.
int? takeNotificationCenterFocus() {
  final id = notificationCenterFocus.value;
  notificationCenterFocus.value = null;
  return id;
}

/// What the notification center needs from the school's feed. Every entry of
/// that feed is unread: reading one removes it.
class SchoolNotificationFeed {
  const SchoolNotificationFeed({
    required this.notifications,
    required this.noInternet,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onOpenMessage,
    this.lastFetched,
  });

  final List<Notification> notifications;
  final bool noInternet;
  final ValueChanged<Notification> onMarkRead;
  final VoidCallback onMarkAllRead;
  final ValueChanged<int> onOpenMessage;
  final UtcDateTime? lastFetched;
}
