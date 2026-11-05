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

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';

enum DashboardEventKind { grade, message, absence, observation, general }

/// The kind of an unseen feed entry. The portal's types are compared without
/// case sensitivity, as in SchoolNotificationEvent. Everything without a kind
/// of its own stays visible as a general event.
DashboardEventKind dashboardEventKindOf(String? type) =>
    switch (type?.toLowerCase()) {
      'grade' => DashboardEventKind.grade,
      'message' || 'messageshared' => DashboardEventKind.message,
      'absence' => DashboardEventKind.absence,
      'observation' => DashboardEventKind.observation,
      _ => DashboardEventKind.general,
    };

/// How many unread messages the feed reports, for the navigation badge.
int unreadMessageCount(AppState state) =>
    (state.notificationState.notifications ?? const <Notification>[])
        .where((notification) =>
            dashboardEventKindOf(notification.type) ==
            DashboardEventKind.message)
        .length;
