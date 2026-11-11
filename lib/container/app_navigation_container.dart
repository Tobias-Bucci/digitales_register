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
import 'package:dr/container/profile_menu_container.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// The navigation of the new design for [ResponsiveScaffold].
ResponsiveNavigation<Pages> appNavigation() => ResponsiveNavigation<Pages>(
      barBuilder: (_, current) =>
          AppNavigationContainer(current: current, rail: false),
      railBuilder: (_, current) =>
          AppNavigationContainer(current: current, rail: true),
      barExtent: appNavigationBarExtent,
      isTopLevel: isTopLevelPage,
      keepsRouteBelow: (current, next) =>
          current == Pages.extras && isExtrasChild(next),
    );

class AppNavigationContainer extends StatelessWidget {
  const AppNavigationContainer({
    super.key,
    required this.current,
    required this.rail,
  });

  final Pages current;
  final bool rail;

  void _open(
    BuildContext context,
    AppActions actions,
    AppDestination destination,
  ) {
    final returnsToCurrent = switch (destination) {
      AppDestination.grades => current == Pages.grades,
      AppDestination.calendar => current == Pages.calendar,
      AppDestination.messages => current == Pages.messages,
      AppDestination.extras => current == Pages.extras,
      AppDestination.dashboard || AppDestination.profile => false,
    };
    if (returnsToCurrent) {
      // Closes what is open on top of the page, such as Profile or a page of
      // the settings opened from it.
      nestedNavKey.currentState?.popUntil(
        (route) => route.isFirst || route.settings.arguments == current,
      );
      return;
    }
    switch (destination) {
      case AppDestination.dashboard:
        scaffoldKey?.currentState?.goHome();
      case AppDestination.grades:
        if (current != Pages.grades) actions.routingActions.showGrades();
      case AppDestination.calendar:
        if (current != Pages.calendar) actions.routingActions.showCalendar();
      case AppDestination.messages:
        if (current != Pages.messages) actions.routingActions.showMessages();
      case AppDestination.extras:
        if (current != Pages.extras) actions.routingActions.showExtras();
      case AppDestination.profile:
        showProfileMenu(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    diagnostics.screen(current.name);
    return ValueListenableBuilder<int>(
      valueListenable: openProfileShellPages,
      builder: (context, profilePages, _) =>
          _build(context, profileOpen: profilePages > 0),
    );
  }

  Widget _build(BuildContext context, {required bool profileOpen}) {
    return StoreConnection<AppState, AppActions,
        (int, String?, ProfileIdentity)>(
      connect: (state) => (
        unreadMessageCount(state),
        buildProfilePictureUrl(
          baseUrl: state.url,
          picture: state.profileState.picture,
        ),
        ProfileIdentity(
          name: state.config?.fullName ?? state.loginState.username,
          account: state.loginState.username,
        ),
      ),
      builder: (context, vm, actions) {
        // Profile and its pages open on top of the current page.
        final selected =
            profileOpen ? AppDestination.profile : destinationOf(current);
        void onSelected(AppDestination destination) =>
            _open(context, actions, destination);
        return rail
            ? AppNavigationRail(
                selected: selected,
                onSelected: onSelected,
                unreadMessages: vm.$1,
                userIcon: vm.$2,
                user: vm.$3,
              )
            : FloatingNavigationBar(
                selected: selected,
                onSelected: onSelected,
                unreadMessages: vm.$1,
                userIcon: vm.$2,
                user: vm.$3,
              );
      },
    );
  }
}
