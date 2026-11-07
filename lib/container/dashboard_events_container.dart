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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Rebuilds only when something an event is made of has changed.
class _EventSource {
  _EventSource(this.state);

  final AppState state;

  NotificationState get _notifications => state.notificationState;
  GradesState get _grades => state.gradesState;
  DashboardState get _dashboard => state.dashboardState;

  /// Grade banners are coloured unless the user has turned grade colours off.
  bool get colorGrades => !state.settingsState.gradeColorsTurnedOff;

  @override
  bool operator ==(Object other) =>
      other is _EventSource &&
      other._notifications == _notifications &&
      other._grades == _grades &&
      other._dashboard.allDays == _dashboard.allDays &&
      other.colorGrades == colorGrades &&
      other.state.noInternet == state.noInternet;

  @override
  int get hashCode => Object.hash(
        _notifications,
        _grades,
        _dashboard.allDays,
        colorGrades,
        state.noInternet,
      );
}

/// Reports [event] as seen, the same way the bell does.
void markDashboardEventSeen(AppActions actions, DashboardEvent event) {
  final notification = event.notification;
  if (notification != null) {
    actions.notificationsActions.delete(notification);
    final message = notification.objectId;
    if (event.kind == DashboardEventKind.message && message != null) {
      actions.messagesActions.markAsRead(message);
    }
  }
  final homework = event.homework;
  if (homework != null) {
    actions.dashboardActions.markAsSeen(homework);
  }
}

/// Opens what [event] is about.
void openDashboardEvent(AppActions actions, DashboardEvent event) {
  final message = event.notification?.objectId;
  switch (event.kind) {
    case DashboardEventKind.grade || DashboardEventKind.observation:
      gradesPageFocusSubject.value = event.subject;
      actions.routingActions.showGrades();
    case DashboardEventKind.message:
      if (message != null) {
        actions.routingActions.showMessage(message);
      } else {
        actions.routingActions.showMessages();
      }
    case DashboardEventKind.absence:
      actions.routingActions.showAbsences();
    case DashboardEventKind.general:
      // The banner only has room for the start: open the whole text.
      notificationCenterFocus.value = event.notification?.id;
      actions.routingActions.showNotifications();
  }
}

class DashboardEventsContainer extends StatelessWidget {
  const DashboardEventsContainer({super.key});

  void _open(AppActions actions, DashboardEvent event, bool offline) {
    openDashboardEvent(actions, event);
    // The general feed entries are handled on the page that was just opened.
    if (!offline && event.kind != DashboardEventKind.general) {
      markDashboardEventSeen(actions, event);
    }
  }

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, _EventSource>(
        connect: _EventSource.new,
        builder: (context, source, actions) {
          final state = source.state;
          final offline = state.noInternet;
          final events = dashboardEvents(state);
          return EventBannerStack(
            events: events,
            colorGrades: source.colorGrades,
            canDismiss: !offline,
            onOpen: (event) => _open(actions, event, offline),
            onDismiss: (event) => markDashboardEventSeen(actions, event),
            onShowAll: () => showGlassSheet<void>(
              context: context,
              builder: (sheetContext) =>
                  StoreConnection<AppState, AppActions, _EventSource>(
                connect: _EventSource.new,
                builder: (sheetContext, source, actions) {
                  final events = dashboardEvents(source.state);
                  void close() => Navigator.of(sheetContext).pop();
                  return EventListSheet(
                    events: events,
                    colorGrades: source.colorGrades,
                    canDismiss: !source.state.noInternet,
                    onOpen: (event) {
                      close();
                      _open(actions, event, source.state.noInternet);
                    },
                    onDismiss: (event) {
                      if (events.length == 1) close();
                      markDashboardEventSeen(actions, event);
                    },
                    onDismissAll: () {
                      close();
                      for (final event in events) {
                        markDashboardEventSeen(actions, event);
                      }
                    },
                  );
                },
              ),
            ),
          );
        },
      );
}
