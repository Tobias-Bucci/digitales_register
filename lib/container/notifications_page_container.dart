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
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:tuple/tuple.dart';

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
    return StoreConnection<AppState, AppActions,
        Tuple3<BuiltList<Notification>, UtcDateTime?, bool>>(
      builder: (context, vm, actions) {
        return ServerNotificationCenterPage(
          initialSchoolId: focusSchoolId,
          initialId: focusAppId,
          school: SchoolNotificationFeed(
            notifications: vm.item1.toList(),
            noInternet: vm.item3,
            onMarkRead: actions.notificationsActions.delete.call,
            onMarkAllRead: actions.notificationsActions.deleteAll.call,
            onOpenMessage: (id) {
              AnalyticsService.product.event(
                  'notification_opened', {'notification_type': 'general'});
              actions.routingActions.showMessage(id);
            },
            lastFetched: vm.item2,
          ),
          onRefresh: () => Future.wait([
            serverNotifications.refresh(),
            refreshSchoolNotificationFeed(actions),
          ]),
        );
      },
      connect: (state) {
        return Tuple3(
          state.notificationState.notifications ?? BuiltList<Notification>(),
          state.notificationState.lastFetched,
          state.noInternet,
        );
      },
    );
  }
}
