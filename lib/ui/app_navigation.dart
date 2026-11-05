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
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
const appNavigationBarHeight = FloatingGlass.thickness;

/// The space between the bar and the bottom safe area.
const _barBottomGap = 8.0;

/// The touch target of an item of the bar.
const _barItemExtent = 48.0;

/// The free space around the items of the rail, whose length is not given by
/// the window as the width of the bar is.
const _railItemGap = 8.0;

/// The width that the rail takes from the page, including its margins.
const appNavigationRailExtent =
    appNavigationBarHeight + 2 * DesignTokens.gutter;

const _lensHeight = 44.0;
const _lensMaxWidth = 60.0;

/// How close a stretched lens gets to the end of the bar.
const _lensEdgeGap = 2.0;

/// The tint of the bar: a little deeper than the cards, so that it can stay
/// translucent and icons keep their contrast.
Color navigationBarTint(ColorScheme scheme) => Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.08),
      scheme.surfaceContainer,
    );

/// The fill of the lens over the selected item.
Color navigationLensFill(ColorScheme scheme) =>
    scheme.primaryContainer.withValues(alpha: 0.86);

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

/// The glass that the bar and the rail have in common.
class _NavigationGlass extends StatelessWidget {
  const _NavigationGlass({required this.surfaceKey, required this.child});

  final Key surfaceKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => FloatingGlass(
        surfaceKey: surfaceKey,
        tint: navigationBarTint(Theme.of(context).colorScheme),
        opacity: DesignTokens.navigationBarOpacity,
        child: FocusTraversalGroup(child: child),
      );
}

/// The destinations on a track of [axis], the same in the bar and the rail.
class _DestinationTrack extends StatelessWidget {
  const _DestinationTrack({
    required this.axis,
    required this.selected,
    required this.onSelected,
    required this.unreadMessages,
    required this.userIcon,
  });

  final Axis axis;
  final AppDestination selected;
  final DestinationCallback onSelected;
  final int unreadMessages;
  final String? userIcon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _LensTrack(
      axis: axis,
      selectedIndex: selected.index,
      itemCount: AppDestination.values.length,
      itemBuilder: (context, index, nearness) {
        final destination = AppDestination.values[index];
        return _BarItem(
          destination: destination,
          selected: destination == selected,
          nearness: nearness,
          label: _destinationLabel(l10n, destination, unreadMessages),
          unreadMessages: unreadMessages,
          userIcon: userIcon,
          onPressed: () => onSelected(destination),
        );
      },
    );
  }
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
    final media = MediaQuery.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.text('sidebar.navigationLabel'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          0,
          DesignTokens.gutter,
          media.padding.bottom + _barBottomGap,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _NavigationGlass(
            surfaceKey: const Key('app-navigation-bar'),
            child: SizedBox(
              height: appNavigationBarHeight,
              child: _DestinationTrack(
                axis: Axis.horizontal,
                selected: selected,
                onSelected: onSelected,
                unreadMessages: unreadMessages,
                userIcon: userIcon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The items of the bar with a lens that marks the selected one. The lens slides
/// over on a spring, stretches with its speed, and what it passes grows a little
/// as under real glass. With reduced motion it simply is at the new place.
class _LensTrack extends StatefulWidget {
  const _LensTrack({
    required this.axis,
    required this.selectedIndex,
    required this.itemCount,
    required this.itemBuilder,
  });

  final Axis axis;
  final int selectedIndex, itemCount;

  /// [nearness] is 1 below the centre of the lens and 0 clear of it.
  final Widget Function(BuildContext context, int index, double nearness)
      itemBuilder;

  @override
  State<_LensTrack> createState() => _LensTrackState();
}

class _LensTrackState extends State<_LensTrack>
    with SingleTickerProviderStateMixin {
  // Slightly underdamped, so that the lens settles with a small overshoot.
  static const _spring =
      SpringDescription(mass: 1, stiffness: 300, damping: 26);

  /// The speed, in items per second, at which the lens is stretched the most.
  static const _fullStretchSpeed = 14.0;

  /// The position of the lens, in items.
  late final AnimationController _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );

  @override
  void didUpdateWidget(_LensTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    final target = widget.selectedIndex.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = target;
    } else {
      _position.animateWith(SpringSimulation(
        _spring,
        _position.value,
        target,
        _position.velocity,
      ));
    }
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final length =
            horizontal ? constraints.maxWidth : constraints.maxHeight;
        final count = widget.itemCount;
        // The same places as the free space of spaceEvenly gives the items.
        final gap = (length - count * _barItemExtent) / (count + 1);
        final pitch = _barItemExtent + gap;
        final lensLength = (pitch - 6).clamp(_lensHeight, _lensMaxWidth);
        return AnimatedBuilder(
          animation: _position,
          builder: (context, _) {
            final position = _position.value;
            final speed = _position.isAnimating ? _position.velocity.abs() : 0;
            final stretch = (speed / _fullStretchSpeed).clamp(0.0, 1.0);
            final along = lensLength * (1 + 0.32 * stretch);
            final across = _lensHeight * (1 - 0.1 * stretch);
            final center = gap + _barItemExtent / 2 + position * pitch;
            final start = (center - along / 2).clamp(
              _lensEdgeGap,
              length - along - _lensEdgeGap,
            );
            final side = (appNavigationBarHeight - across) / 2;
            return Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  key: const Key('app-navigation-lens'),
                  left: horizontal ? start : side,
                  top: horizontal ? side : start,
                  width: horizontal ? along : across,
                  height: horizontal ? across : along,
                  child: const _GlassLens(),
                ),
                Flex(
                  direction: widget.axis,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var index = 0; index < count; index++)
                      widget.itemBuilder(
                        context,
                        index,
                        (1 - (position - index).abs()).clamp(0.0, 1.0),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _GlassLens extends StatelessWidget {
  const _GlassLens();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: highContrast
              ? scheme.primaryContainer
              : navigationLensFill(scheme),
          shape: StadiumBorder(
            side: highContrast
                ? BorderSide(color: scheme.onPrimaryContainer)
                : BorderSide.none,
          ),
          shadows: [
            if (!highContrast)
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: const GlassEdge(
          shape: StadiumBorder(),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.destination,
    required this.selected,
    required this.nearness,
    required this.label,
    required this.unreadMessages,
    required this.userIcon,
    required this.onPressed,
  });

  final AppDestination destination;
  final bool selected;
  final double nearness;
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
        icon: Transform.scale(scale: 1 + 0.08 * nearness, child: icon),
        isSelected: selected,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(44),
          minimumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          // Always the same target, the lens depends on it.
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          hoverColor: scheme.onSurface.withValues(alpha: 0.08),
          backgroundColor: Colors.transparent,
          foregroundColor: Color.lerp(
            scheme.onSurfaceVariant,
            scheme.onPrimaryContainer,
            nearness,
          ),
        ),
      ),
    );
  }
}

/// [FloatingNavigationBar] turned upright for wide windows, where height is
/// scarcer than width. It keeps a margin of its own and floats in the middle of
/// it. The wash of the dashboard continues below it, so that the page has no
/// edge there.
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
    final count = AppDestination.values.length;
    final rail = Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.text('sidebar.navigationLabel'),
      child: Center(
        // Only a very low window has to scroll it.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.all(DesignTokens.gutter),
            child: _NavigationGlass(
              surfaceKey: const Key('app-navigation-rail'),
              child: SizedBox(
                width: appNavigationBarHeight,
                height: count * _barItemExtent + (count + 1) * _railItemGap,
                child: _DestinationTrack(
                  axis: Axis.vertical,
                  selected: selected,
                  onSelected: onSelected,
                  unreadMessages: unreadMessages,
                  userIcon: userIcon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: appNavigationRailExtent,
      height: double.infinity,
      child: DashboardBackdrop(
        visible: selected == AppDestination.dashboard,
        child: rail,
      ),
    );
  }
}
