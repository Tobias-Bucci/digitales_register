// Copyright (C) 2021 Michael Debertol
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

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/app_state.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// The notification center of the signed-in app, with both sources.
class NotificationPageContainer extends StatelessWidget {
  const NotificationPageContainer({
    super.key,
    this.focusSchoolId,
    this.focusAppId,
  });

  /// The school notification to open right away.
  final int? focusSchoolId;

  /// The app announcement to open right away, as from its popup.
  final String? focusAppId;

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, _SchoolFeedState>(
      builder: (context, vm, actions) {
        // Each entry is looked up once per build, also for an entry that
        // reading has taken out of the feed.
        final grades = <int, int?>{};
        return ServerNotificationCenterPage(
          initialSchoolId: focusSchoolId,
          initialId: focusAppId,
          school: SchoolNotificationFeed(
            notifications: vm.notifications.toList(),
            noInternet: vm.noInternet,
            onMarkRead: actions.notificationsActions.delete.call,
            onMarkAllRead: actions.notificationsActions.deleteAll.call,
            onOpenMessage: (id) {
              AnalyticsService.product.event(
                  'notification_opened', {'notification_type': 'general'});
              actions.routingActions.showMessage(id);
            },
            lastFetched: vm.lastFetched,
            gradeOf: (item) => grades.putIfAbsent(
              item.id,
              () => notificationGradeHundredths(item,
                  grades: vm.grades, days: vm.days),
            ),
            // Each design follows its own setting, as its grade lists do.
            colorGrades: ResponsiveNavigationScope.isActive(context)
                ? vm.colorGradesNew
                : vm.colorGradesLegacy,
          ),
          onRefresh: () => Future.wait([
            serverNotifications.refresh(),
            refreshSchoolNotificationFeed(actions),
          ]),
        );
      },
      connect: (state) => (
        notifications:
            state.notificationState.notifications ?? BuiltList<Notification>(),
        lastFetched: state.notificationState.lastFetched,
        noInternet: state.noInternet,
        grades: state.gradesState,
        days: state.dashboardState.allDays,
        colorGradesNew: !state.settingsState.gradeColorsTurnedOff,
        colorGradesLegacy: state.settingsState.colorGrades,
      ),
    );
  }
}

/// What the notification center reads from the state. The grades and the
/// dashboard give the values of announced grades; both are immutable, so an
/// unchanged state compares equal at once.
typedef _SchoolFeedState = ({
  BuiltList<Notification> notifications,
  UtcDateTime? lastFetched,
  bool noInternet,
  GradesState grades,
  BuiltList<Day>? days,
  bool colorGradesNew,
  bool colorGradesLegacy,
});
