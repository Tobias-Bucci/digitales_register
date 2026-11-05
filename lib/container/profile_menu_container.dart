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

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Opens the profile menu: a sheet on phones, a panel next to the rail in wide
/// windows.
Future<void> showProfileMenu(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= tabletLayoutBreakpoint;
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SingleChildScrollView(
        child: ProfileMenuContainer(),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(96, 24, 24, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            clipBehavior: Clip.antiAlias,
            elevation: 6,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: DesignTokens.cardBorderRadius,
            child: const SingleChildScrollView(
              padding: EdgeInsets.only(top: 8),
              child: ProfileMenuContainer(),
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfileMenuContainer extends StatelessWidget {
  const ProfileMenuContainer({super.key});

  @override
  Widget build(BuildContext context) => StoreConnection<AppState, AppActions,
          (String?, String?, String?, BuiltList<String>)>(
        connect: (state) {
          final username = state.loginState.username;
          final school = schoolNameForUrl(state.url);
          return (
            state.config?.fullName ?? username,
            [if (username != null) username, if (school != null) school]
                .join(' · '),
            buildProfilePictureUrl(
              baseUrl: state.url,
              picture: state.profileState.picture,
            ),
            state.loginState.otherAccounts,
          );
        },
        builder: (context, vm, actions) => ProfileMenu(
          name: vm.$1,
          account: vm.$2?.isEmpty ?? true ? null : vm.$2,
          userIcon: vm.$3,
          otherAccounts: vm.$4.toList(),
          showProfile: actions.routingActions.showProfile.call,
          showSettings: actions.routingActions.showSettings.call,
          selectAccount: actions.loginActions.selectAccount.call,
          addAccount: actions.loginActions.addAccount.call,
          removeCurrentAccount: actions.loginActions.removeCurrentAccount.call,
          logout: () => actions.loginActions.logout(
            LogoutPayload(
              (b) => b
                ..hard = true
                ..forced = false,
            ),
          ),
        ),
      );
}
