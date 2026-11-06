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
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// The slim header of the new design: app logo, school and app name. The
/// height never changes, a long school name is cut off instead.
///
/// With [floatingMaxWidth], as in wide windows, it is not a band from edge to
/// edge but floats like the navigation and lines up with the content below it.
class DashboardAppHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const DashboardAppHeader({
    super.key,
    required this.schoolName,
    required this.noInternet,
    required this.onRetry,
    this.floatingMaxWidth,
    this.showScrollUp,
    this.onScrollUp,
  });

  static const double height = 56;

  final double? floatingMaxWidth;

  /// Null for an unknown school, which leaves only the app name.
  final String? schoolName;
  final bool noInternet;
  final VoidCallback onRetry;

  /// Whether the button back to the start of the list shows. It belongs here
  /// and not over the list, where the controls of the days would pass under it.
  final ValueListenable<bool>? showScrollUp;

  /// Null while there is no list to scroll, which leaves out the button.
  final VoidCallback? onScrollUp;

  @override
  Size get preferredSize => Size.fromHeight(
        floatingMaxWidth == null ? height : height + DesignTokens.gutter,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appName = l10n.text('login.appTitle');
    final content = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: floatingMaxWidth == null ? DesignTokens.gutter : 14,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: NotepadMark(
                checked: true,
                size: 36,
                fill: scheme.surfaceContainerLowest,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (schoolName != null)
                      Text(
                        schoolName!,
                        key: const Key('dashboard-header-school'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    Text(
                      appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: schoolName == null
                          ? theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)
                          : theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.2,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            if (noInternet)
              IconButton(
                tooltip: l10n.text('dashboard.noConnectionReload'),
                onPressed: onRetry,
                icon: const Icon(Icons.wifi_off_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                ),
              ),
            if (showScrollUp != null && onScrollUp != null)
              ValueListenableBuilder(
                valueListenable: showScrollUp!,
                builder: (context, show, _) => show
                    ? _ScrollUpButton(onPressed: onScrollUp!)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
    final maxWidth = floatingMaxWidth;
    // Two lines have to fit the fixed height, whatever the text size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: maxWidth == null
          ? GlassSurface(
              key: const Key('dashboard-app-header'),
              tint: scheme.surface,
              rim: GlassRim.bottom,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: SafeArea(bottom: false, child: content),
            )
          : SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.gutter,
                      DesignTokens.gutter,
                      DesignTokens.gutter,
                      0,
                    ),
                    child: FloatingGlass(
                      surfaceKey: const Key('dashboard-app-header'),
                      tint: scheme.surface,
                      opacity: DesignTokens.headerOpacity,
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Back to the start of the list: a disc as big as the logo, in a full-sized
/// touch target.
class _ScrollUpButton extends StatelessWidget {
  const _ScrollUpButton({required this.onPressed});

  static const double _discSize = 36;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const Key('dashboard-scroll-up'),
      tooltip: context.t('dashboard.scrollToTop'),
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_discSize),
        minimumSize: const Size.square(_discSize),
        padding: EdgeInsets.zero,
        // The compact density of desktops would shrink the target to 40.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).merge(glassControlStyle(scheme, shape: const CircleBorder())),
    );
  }
}

/// A quiet accent wash behind the dashboard, so that its translucent surfaces
/// have something to show. Pure black stays pure black on AMOLED.
class DashboardBackdrop extends StatelessWidget {
  const DashboardBackdrop(
      {super.key, required this.child, this.visible = true});

  /// Without it [child] stays where it is in the tree and keeps its state.
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.surface == const Color(0xFF000000)) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: !visible
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.55],
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.42),
                  scheme.primaryContainer.withValues(alpha: 0),
                ],
              ),
      ),
      child: child,
    );
  }
}
