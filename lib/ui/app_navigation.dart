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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';

/// The destinations of the new design, the same in the bar and in the rail.
enum AppDestination {
  dashboard(
    'sidebar.dashboard',
    Icons.dashboard_outlined,
    Icons.dashboard_rounded,
  ),
  grades('sidebar.grades', Icons.auto_graph_outlined, Icons.auto_graph_rounded),
  calendar(
    'sidebar.calendar',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
  ),
  messages(
    'sidebar.messages',
    Icons.mail_outline_rounded,
    Icons.mail_rounded,
  ),
  extras('sidebar.extras', Icons.widgets_outlined, Icons.widgets_rounded),
  profile(
    'sidebar.profile',
    Icons.account_circle_outlined,
    Icons.account_circle_rounded,
  );

  const AppDestination(this.labelKey, this.icon, this.selectedIcon);

  final String labelKey;
  final IconData icon;
  final IconData selectedIcon;
}

/// The destination that stays highlighted while [page] is open. Every page of
/// the old sidebar belongs to exactly one of them.
AppDestination destinationOf(Pages page) => switch (page) {
      Pages.homework => AppDestination.dashboard,
      Pages.grades => AppDestination.grades,
      Pages.calendar || Pages.examCalendar => AppDestination.calendar,
      Pages.messages => AppDestination.messages,
      Pages.extras ||
      Pages.absences ||
      Pages.classRegister ||
      Pages.courseMaterials ||
      Pages.homeworkSummary ||
      Pages.certificate =>
        AppDestination.extras,
      Pages.settings || Pages.debug => AppDestination.profile,
    };

/// Pages that are a destination of their own and therefore have no back button.
bool isTopLevelPage(Pages page) => switch (page) {
      Pages.homework ||
      Pages.grades ||
      Pages.calendar ||
      Pages.examCalendar ||
      Pages.messages ||
      Pages.extras =>
        true,
      _ => false,
    };

/// The pages grouped on the Extras page. Going back from them returns there.
bool isExtrasChild(Pages page) => switch (page) {
      Pages.absences ||
      Pages.classRegister ||
      Pages.courseMaterials ||
      Pages.homeworkSummary ||
      Pages.certificate =>
        true,
      _ => false,
    };

/// The height of the floating bar itself. Kept slim on purpose, see #85.
const appNavigationBarHeight = 56.0;

/// The space between the bar and the bottom safe area.
const _barBottomGap = 8.0;

/// How far the bar reaches above the bottom safe area, including the gap to the
/// content above it.
const appNavigationBarExtent = appNavigationBarHeight + _barBottomGap + 8;

typedef DestinationCallback = void Function(AppDestination destination);

Widget _withBadge(BuildContext context, Widget icon, int count) => count == 0
    ? icon
    : Badge.count(
        count: count,
        backgroundColor: Theme.of(context).colorScheme.error,
        textColor: Theme.of(context).colorScheme.onError,
        child: icon,
      );

String _destinationLabel(
  AppLocalizations l10n,
  AppDestination destination,
  int unreadMessages,
) {
  final label = l10n.text(destination.labelKey);
  return destination == AppDestination.messages && unreadMessages > 0
      ? l10n.text('sidebar.messages.unread',
          args: {'label': label, 'count': '$unreadMessages'})
      : label;
}

/// The floating, translucent bar of the new design on phones.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.unreadMessages,
    required this.userIcon,
  });

  final AppDestination selected;
  final DestinationCallback onSelected;
  final int unreadMessages;
  final String? userIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.text('sidebar.navigationLabel'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          0,
          DesignTokens.gutter,
          media.padding.bottom + _barBottomGap,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(appNavigationBarHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: GlassSurface(
              key: const Key('app-navigation-bar'),
              tint: Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.08),
                scheme.surfaceContainerHigh,
              ),
              opacity: DesignTokens.navigationBarOpacity,
              borderRadius: BorderRadius.circular(appNavigationBarHeight / 2),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
              child: SizedBox(
                height: appNavigationBarHeight,
                child: FocusTraversalGroup(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final destination in AppDestination.values)
                        _BarItem(
                          destination: destination,
                          selected: destination == selected,
                          label: _destinationLabel(
                              l10n, destination, unreadMessages),
                          unreadMessages: unreadMessages,
                          userIcon: userIcon,
                          onPressed: () => onSelected(destination),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.destination,
    required this.selected,
    required this.label,
    required this.unreadMessages,
    required this.userIcon,
    required this.onPressed,
  });

  final AppDestination destination;
  final bool selected;
  final String label;
  final int unreadMessages;
  final String? userIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = destination == AppDestination.profile
        ? ProfileAvatar(imageUrl: userIcon, size: 32)
        : _withBadge(
            context,
            Icon(selected ? destination.selectedIcon : destination.icon),
            destination == AppDestination.messages ? unreadMessages : 0,
          );
    return Semantics(
      selected: selected,
      child: IconButton(
        key: ValueKey('app-navigation-${destination.name}'),
        tooltip: label,
        onPressed: onPressed,
        icon: icon,
        isSelected: selected,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          hoverColor: scheme.onSurface.withValues(alpha: 0.08),
        ).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

/// The same destinations as [FloatingNavigationBar] for wide windows.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.unreadMessages,
    required this.userIcon,
  });

  final AppDestination selected;
  final DestinationCallback onSelected;
  final int unreadMessages;
  final String? userIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: NavigationRail(
        key: const Key('app-navigation-rail'),
        scrollable: true,
        labelType: NavigationRailLabelType.all,
        backgroundColor: scheme.surfaceContainerLow,
        selectedIndex: selected.index,
        onDestinationSelected: (index) =>
            onSelected(AppDestination.values[index]),
        destinations: [
          for (final destination in AppDestination.values)
            NavigationRailDestination(
              icon: Tooltip(
                message: _destinationLabel(l10n, destination, unreadMessages),
                child: destination == AppDestination.profile
                    ? ProfileAvatar(imageUrl: userIcon, size: 30)
                    : _withBadge(
                        context,
                        Icon(destination.icon),
                        destination == AppDestination.messages
                            ? unreadMessages
                            : 0,
                      ),
              ),
              selectedIcon: destination == AppDestination.profile
                  ? ProfileAvatar(imageUrl: userIcon, size: 30)
                  : _withBadge(
                      context,
                      Icon(destination.selectedIcon),
                      destination == AppDestination.messages
                          ? unreadMessages
                          : 0,
                    ),
              label: Text(l10n.text(destination.labelKey)),
            ),
        ],
      ),
    );
  }
}
