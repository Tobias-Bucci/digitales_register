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

import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:dr/ui/server_notifications/server_notification_popup.dart'
    show ServerNotificationPopupClearance;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// The slim header of the new design: app logo, school and app name. A long
/// school name is cut off instead of changing the height. Only the strip for new
/// entries adds to it, and the content below moves down with it, so that the
/// strip never lies over the list.
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
    this.onShowNewEntries,
    this.onDismissNewEntries,
  });

  static const double height = GlassHeaderMetrics.height;
  static const double newEntriesHeight = 48;

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

  /// Jumps to the next new entry. Null once it is in view.
  final VoidCallback? onShowNewEntries;

  /// Null without new entries, which leaves out their strip.
  final VoidCallback? onDismissNewEntries;

  @override
  Size get preferredSize => Size.fromHeight(
        height +
            (floatingMaxWidth == null ? 0 : DesignTokens.gutter) +
            (onDismissNewEntries == null ? 0 : newEntriesHeight),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appName = l10n.text('login.appTitle');
    final floating = floatingMaxWidth != null;
    final content = SizedBox(
      height: height,
      child: Padding(
        // The notification button is always last.
        padding: EdgeInsetsDirectional.only(
          start: floating
              ? GlassHeaderMetrics.floatingContentInset
              : GlassHeaderMetrics.contentInset,
          end: floating
              ? GlassHeaderMetrics.floatingButtonInset
              : GlassHeaderMetrics.buttonInset,
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
                    ? HeaderDiscButton(
                        key: const Key('dashboard-scroll-up'),
                        tooltip: l10n.text('dashboard.scrollToTop'),
                        icon: Icons.arrow_upward_rounded,
                        onPressed: onScrollUp!,
                      )
                    : const SizedBox.shrink(),
              ),
            // Last, so that it stays in place when the buttons before it come
            // and go.
            NotificationIconContainer(
              style: HeaderDiscButton.styleOf(scheme),
              iconSize: HeaderDiscButton.iconSize,
            ),
          ],
        ),
      ),
    );
    final dismiss = onDismissNewEntries;
    final band = dismiss == null
        ? content
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              content,
              _NewEntriesStrip(
                horizontalPadding: floating
                    ? GlassHeaderMetrics.floatingRowInset
                    : GlassHeaderMetrics.rowInset,
                onShow: onShowNewEntries,
                onDismiss: dismiss,
              ),
            ],
          );
    return GlassHeaderShell(
      surfaceKey: const Key('dashboard-app-header'),
      floatingMaxWidth: floatingMaxWidth,
      child: band,
    );
  }
}

/// The metrics every header of the new design shares: the one of the
/// dashboard and [GlassPageHeader] of every other page, so that the top bar
/// does not change between pages (#140).
abstract final class GlassHeaderMetrics {
  /// The height of the row with the title, the logo and the buttons.
  static const double height = 56;

  /// From the edge of the header to its first text or logo, in a band from
  /// edge to edge and in a floating header.
  static const double contentInset = 16;
  static const double floatingContentInset = 20;

  /// From the edge of the header to a button at either end: the back button
  /// at the start, the last action at the end.
  static const double buttonInset = 4;
  static const double floatingButtonInset = 8;

  /// From the edge of the header to a second row below the title row.
  static const double rowInset = DesignTokens.gutter;
  static const double floatingRowInset = 14;
}

/// The glass of a page header: a band from edge to edge, or with
/// [floatingMaxWidth], as in wide windows, a bar that floats like the navigation
/// and lines up with the content below it.
class GlassHeaderShell extends StatelessWidget {
  const GlassHeaderShell({
    super.key,
    required this.surfaceKey,
    required this.floatingMaxWidth,
    required this.child,
  });

  final Key surfaceKey;
  final double? floatingMaxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxWidth = floatingMaxWidth;
    // Keeps the popup for new app announcements below the header (#111).
    final content = ServerNotificationPopupClearance(child: child);
    // Two lines have to fit the fixed height, whatever the text size.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: maxWidth == null
          ? GlassSurface(
              key: surfaceKey,
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
                      surfaceKey: surfaceKey,
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

/// The way to the new entries, and to dismiss them.
class _NewEntriesStrip extends StatelessWidget {
  const _NewEntriesStrip({
    required this.horizontalPadding,
    required this.onShow,
    required this.onDismiss,
  });

  final double horizontalPadding;
  final VoidCallback? onShow;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      key: const Key('dashboard-new-entries'),
      height: DashboardAppHeader.newEntriesHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: FilledButton.icon(
                key: const Key('dashboard-show-new-entries'),
                onPressed: onShow,
                style: glassControlStyle(Theme.of(context).colorScheme),
                icon: const Icon(
                  Icons.keyboard_double_arrow_down_rounded,
                  size: 20,
                ),
                label: Text(
                  l10n.text('dashboard.newEntries'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            HeaderDiscButton(
              key: const Key('dashboard-dismiss-new-entries'),
              tooltip: l10n.text('dashboard.banner.dismiss'),
              icon: Icons.close_rounded,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// A disc as big as the logo, in a full-sized touch target.
class HeaderDiscButton extends StatelessWidget {
  const HeaderDiscButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  static const double _discSize = 36;
  static const double iconSize = 20;

  /// The disc, for icon buttons that cannot be a [HeaderDiscButton].
  static ButtonStyle styleOf(ColorScheme scheme) => IconButton.styleFrom(
        fixedSize: const Size.square(_discSize),
        minimumSize: const Size.square(_discSize),
        padding: EdgeInsets.zero,
        // The compact density of desktops would shrink the target to 40.
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).merge(glassControlStyle(scheme, shape: const CircleBorder()));

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        style: styleOf(Theme.of(context).colorScheme),
      );
}

/// The quiet accent wash of the new design, so that its translucent surfaces
/// have something to show. Pure black stays pure black on AMOLED.
///
/// It is one wash across the whole window: the dashboard, every `GlassPage`
/// and the navigation rail beside them each paint their part of it. So that
/// the parts meet without an edge (#139), each starts at the top of the
/// window and the wash fades out over the height of the window, not over
/// the height of the part. A page that the keyboard makes shorter keeps
/// the same wash as the rail beside it.
class DashboardBackdrop extends StatelessWidget {
  const DashboardBackdrop({super.key, required this.child});

  final Widget child;

  /// Where the wash has faded out, as a share of the height of the window.
  static const double fadedAt = 0.55;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (scheme.surface == const Color(0xFF000000)) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, fadedAt],
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.42),
            scheme.primaryContainer.withValues(alpha: 0),
          ],
          transform: _OverHeight(MediaQuery.sizeOf(context).height),
        ),
      ),
      child: child,
    );
  }
}

/// Stretches a vertical gradient from the top of its box over [height]
/// instead of over the height of the box.
class _OverHeight extends GradientTransform {
  const _OverHeight(this.height);

  final double height;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.height <= 0 || height <= 0) return null;
    return Matrix4.translationValues(0, bounds.top, 0)
      ..scaleByDouble(1, height / bounds.height, 1, 1)
      ..translateByDouble(0, -bounds.top, 0, 1);
  }

  @override
  bool operator ==(Object other) =>
      other is _OverHeight && other.height == height;

  @override
  int get hashCode => height.hashCode;
}
