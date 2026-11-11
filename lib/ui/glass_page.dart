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

/// The parts every page of the new design is built from, so that the pages
/// look the same and none of them repeats the frame of another.
///
/// A page is a [GlassPage] with a [GlassPageHeader] on top and one of three
/// bodies: a [GlassListBody] for a list in readable width, a
/// [GlassColumnsBody] for a list with a side column on wide windows, or any
/// widget with `scrolls: false` for a body that does not scroll as a whole.
/// Inside, [GlassTile], [GlassSectionHeading], [GlassStateCard] and
/// [GlassOfflineHint] are the rows and messages, and [GlassPanel] is the frame
/// of whatever the page opens with `showGlassSheet`.
library;

import 'dart:math' as math;

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart' show Pages;
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/app_navigation.dart' show isTopLevelPage;
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// The width of the floating header in a window [windowWidth] wide, or null
/// below 720 px, where the header is a band from edge to edge.
///
/// The header lines up with the content below it: [twoColumns] is for a page
/// with a [GlassColumnsBody] (or the dashboard), which is 1220 px wide from
/// 1080 px on. Every other page keeps the readable width of 840 px.
double? glassHeaderFloatingWidth(
  double windowWidth, {
  bool twoColumns = false,
}) {
  if (windowWidth < tabletLayoutBreakpoint) return null;
  if (twoColumns && DashboardColumns.forWindow(windowWidth) != null) {
    return DashboardColumns.maxWidth;
  }
  return DesignTokens.contentMaxWidth;
}

/// The header of a page of the new design, on the glass of
/// [GlassHeaderShell]: the only blur of the page.
///
/// It shows a back button unless the page is a destination of the navigation
/// of its own (see [showsBackButton]), then the [title], an optional
/// [control] beside it, the [actions] and, below that row, an optional
/// [bottom] row.
///
/// Pass [floatingMaxWidth] from [glassHeaderFloatingWidth], so that the header
/// floats on wide windows and lines up with the body.
class GlassPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const GlassPageHeader({
    super.key,
    required this.title,
    required this.floatingMaxWidth,
    this.titleWidget,
    this.control,
    this.actions = const [],
    this.bottom,
    this.showBackButton,
    this.surfaceKey = const Key('glass-page-header'),
    this.titleKey,
  });

  /// The height of the title row.
  static const double height = 56;

  /// What [control] leaves to the title, for very large text.
  static const double minTitleWidth = 56;

  /// The width of a [HeaderDiscButton] with its touch target.
  static const double _actionWidth = 48;

  /// The height of the header, as [preferredSize] gives it.
  static double heightFor({
    required double? floatingMaxWidth,
    double bottomHeight = 0,
  }) =>
      height +
      (floatingMaxWidth == null ? 0 : DesignTokens.gutter) +
      bottomHeight;

  /// Whether a header in [context] has a back button: everywhere but on the
  /// destinations of the navigation (dashboard, grades, calendar, exam
  /// calendar, messages and Extras), and only where there is a page to go back
  /// to.
  ///
  /// The navigation pushes its destinations above the dashboard, so whether
  /// the route can pop does not tell them apart; their route arguments do.
  static bool showsBackButton(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null || !route.canPop) return false;
    final arguments = route.settings.arguments;
    return !(arguments is Pages && isTopLevelPage(arguments));
  }

  /// The title of the page, read out as its heading. It gets smaller rather
  /// than cut off when it does not fit.
  final String title;

  /// Shown in place of the text of [title], for pages whose title is a
  /// switch, such as the calendars with their `GlassSegmentedControl`. Put it
  /// in a `FittedBox(fit: BoxFit.scaleDown)`. [title] stays the name of the
  /// heading for screen readers.
  final Widget? titleWidget;

  /// A control beside the title, such as a `GlassSegmentedControl`. It is
  /// scaled down so that the title keeps [minTitleWidth].
  final Widget? control;

  /// [HeaderDiscButton]s, or icon buttons with [HeaderDiscButton.styleOf].
  final List<Widget> actions;

  /// A second row below the title row, such as folders or a switch of views.
  /// Its preferred height is added to that of the header; 48 suits a row of
  /// controls.
  final PreferredSizeWidget? bottom;

  /// Null follows [showsBackButton]. Only for pages that are shown in an
  /// unusual place, such as a detail beside a list.
  final bool? showBackButton;

  /// Null for a band from edge to edge.
  final double? floatingMaxWidth;

  /// The key of the glass, for tests that look for the header of a page.
  final Key surfaceKey;

  /// The key of the text of [title].
  final Key? titleKey;

  bool get _floating => floatingMaxWidth != null;

  @override
  Size get preferredSize => Size.fromHeight(
        heightFor(
          floatingMaxWidth: floatingMaxWidth,
          bottomHeight: bottom?.preferredSize.height ?? 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final back = showBackButton ?? showsBackButton(context);
    final control = this.control;
    final titleWidget = this.titleWidget;
    final trailing = actions.isNotEmpty || control != null;
    final start = back ? (_floating ? 8.0 : 4.0) : (_floating ? 20.0 : 16.0);
    final end = trailing ? (_floating ? 8.0 : 4.0) : (_floating ? 20.0 : 16.0);
    final titleRow = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: start, end: end),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (back) ...[
                BackButton(
                  style: HeaderDiscButton.styleOf(scheme).merge(
                    const ButtonStyle(
                      iconSize:
                          WidgetStatePropertyAll(HeaderDiscButton.iconSize),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: titleWidget != null
                    ? Semantics(
                        header: true,
                        container: true,
                        label: title,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: titleWidget,
                        ),
                      )
                    : Semantics(
                        header: true,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          // A long word gets smaller, it is the only word
                          // there is.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              title,
                              key: titleKey,
                              maxLines: 1,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (control != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      0,
                      constraints.maxWidth -
                          minTitleWidth -
                          8 -
                          _actionWidth * actions.length -
                          (back ? _actionWidth + 4 : 0),
                    ),
                  ),
                  child: FittedBox(fit: BoxFit.scaleDown, child: control),
                ),
              ],
              ...actions,
            ],
          ),
        ),
      ),
    );
    final bottom = this.bottom;
    return GlassHeaderShell(
      surfaceKey: surfaceKey,
      floatingMaxWidth: floatingMaxWidth,
      child: bottom == null
          ? titleRow
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                titleRow,
                SizedBox(
                  height: bottom.preferredSize.height,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _floating ? 14 : DesignTokens.gutter,
                    ),
                    child: bottom,
                  ),
                ),
              ],
            ),
    );
  }
}

/// The frame of a page of the new design: the [header] above a [body] that
/// scrolls below its glass, the accent wash behind both, text limited to
/// 200 % and the bar that shows [loading] right below the header.
///
/// Give it a [GlassListBody] or a [GlassColumnsBody], whose lists start below
/// the header and end above the floating navigation bar. A body that does not
/// scroll as a whole, such as a week grid, takes `scrolls: false`: the frame
/// then keeps it below the header and above the navigation bar.
class GlassPage extends StatelessWidget {
  const GlassPage({
    super.key,
    required this.header,
    required this.body,
    this.loading = false,
    this.scrolls = true,
  });

  /// Usually a [GlassPageHeader].
  final PreferredSizeWidget header;
  final Widget body;
  final bool loading;

  /// False for a body that does not scroll as a whole.
  final bool scrolls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: header,
      bottomNavigationBar:
          scrolls ? null : ResponsiveNavigationScope.spacerOf(context),
      body: DashboardBackdrop(
        child: Builder(
          builder: (context) {
            final top = MediaQuery.paddingOf(context).top;
            return Stack(
              children: [
                // Above this, slim rows would no longer be slim, and no system
                // setting of the phones in use asks for more.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 2,
                  child: scrolls
                      ? body
                      : Padding(
                          padding: EdgeInsets.only(top: top),
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: body,
                          ),
                        ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: AnimatedLinearProgressIndicator(show: loading),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The gap around the content of a list of the new design.
const EdgeInsets _gutter = EdgeInsets.fromLTRB(
  DesignTokens.gutter,
  8,
  DesignTokens.gutter,
  DesignTokens.gutter,
);

/// A list in readable width (840 px), the body of most pages. It scrolls below
/// the header and ends above the floating navigation bar.
///
/// [GlassListBody.new] builds all of [children] in one column, which keeps a
/// jump target in the tree; space them yourself (8 px between cards). For long
/// lists, such as messages, use [GlassListBody.builder], which builds only
/// what is in view.
class GlassListBody extends StatelessWidget {
  const GlassListBody({
    super.key,
    this.listKey,
    this.controller,
    required List<Widget> this.children,
  })  : itemCount = null,
        itemBuilder = null;

  const GlassListBody.builder({
    super.key,
    this.listKey,
    this.controller,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
  }) : children = null;

  /// The key of the [ListView], for tests that scroll it.
  final Key? listKey;
  final ScrollController? controller;
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final children = this.children;
    return ReadableContent(
      maxWidth: DesignTokens.contentMaxWidth,
      child: children != null
          ? ListView(
              key: listKey,
              controller: controller,
              padding:
                  EdgeInsets.only(top: padding.top, bottom: padding.bottom),
              children: [
                Padding(
                  padding: _gutter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ],
            )
          : ListView.builder(
              key: listKey,
              controller: controller,
              padding: _gutter +
                  EdgeInsets.only(top: padding.top, bottom: padding.bottom),
              itemCount: itemCount,
              itemBuilder: itemBuilder!,
            ),
    );
  }
}

/// A [side] column beside the [main] list from 1080 px on, as on the
/// dashboard and the grades page. The side column keeps the width it has on a
/// phone and stays in place; the list scrolls up to the edge of the window.
/// Below 1080 px [side] comes first in one [GlassListBody].
///
/// Give its header `glassHeaderFloatingWidth(width, twoColumns: true)`.
class GlassColumnsBody extends StatelessWidget {
  const GlassColumnsBody({
    super.key,
    this.listKey,
    required this.side,
    required this.main,
  })  : itemCount = null,
        itemBuilder = null;

  /// The main list built lazily, item by item, for long lists such as the
  /// absences. Below 1080 px [side] is its first item. Space the items
  /// yourself.
  const GlassColumnsBody.builder({
    super.key,
    this.listKey,
    required this.side,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
  }) : main = const SizedBox.shrink();

  /// The key of the list that holds [main].
  final Key? listKey;
  final Widget side, main;

  /// Set by [GlassColumnsBody.builder], in place of [main].
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final columns =
        DashboardColumns.forWindow(MediaQuery.sizeOf(context).width);
    final itemBuilder = this.itemBuilder;
    if (columns == null) {
      if (itemBuilder == null) {
        return GlassListBody(listKey: listKey, children: [side, main]);
      }
      return GlassListBody.builder(
        listKey: listKey,
        itemCount: itemCount! + 1,
        itemBuilder: (context, index) =>
            index == 0 ? side : itemBuilder(context, index - 1),
      );
    }
    return DashboardColumnsView(
      columns: columns,
      side: Padding(padding: _gutter, child: side),
      main: Builder(
        builder: (context) => itemBuilder == null
            ? ListView(
                key: listKey,
                padding: columns.listPadding(MediaQuery.paddingOf(context)),
                children: [Padding(padding: _gutter, child: main)],
              )
            : ListView.builder(
                key: listKey,
                padding: columns.listPadding(MediaQuery.paddingOf(context)) +
                    _gutter,
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
      ),
    );
  }
}

/// A message in place of the content, in the middle of the page: nothing
/// there yet, offline without data, an error. With [actionLabel], a button
/// below it, such as "Try again".
///
/// Use it as the whole body of a [GlassPage], in place of `NoInternet`, a
/// spinner or a bare text.
class GlassStateCard extends StatelessWidget {
  const GlassStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.refresh_rounded,
  });

  final IconData icon;

  /// [body] may be empty, for a message that needs no explanation.
  final String title, body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final actionLabel = this.actionLabel;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          padding.top + 8,
          DesignTokens.gutter,
          padding.bottom + 8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: scheme.primaryContainer,
                    shape: const CircleBorder(),
                  ),
                  child: SizedBox.square(
                    dimension: 56,
                    child: Icon(icon, color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // An empty [body] leaves the title alone.
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (actionLabel != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAction,
                    style: glassControlStyle(scheme),
                    icon: Icon(actionIcon, size: 20),
                    label: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// That the content is from an earlier visit, and how to try again: a slim
/// card at the top of the list, in place of the black `LastFetchedOverlay`.
/// It brings no margin of its own.
class GlassOfflineHint extends StatelessWidget {
  const GlassOfflineHint({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  final String message;
  final VoidCallback onRetry;

  /// What went wrong; offline by default. A page whose refresh failed for
  /// another reason shows that instead, such as `Icons.sync_problem_rounded`.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.only(left: 12, right: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.t('common.retry'),
            onPressed: onRetry,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// The frame of everything a page opens with `showGlassSheet`: a sheet on
/// phones, a centred panel in wide windows, with a title and what scrolls
/// below it.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

/// A card that leads somewhere: an icon, a [title], an optional [subtitle] and
/// an optional [trailing] widget, such as a chevron for a page. The whole card
/// is one button for screen readers, the mouse gets the hand, and the
/// keyboard a ring.
///
/// It is light only, without blur, so it may stand in a scrolling list.
class GlassTile extends StatelessWidget {
  const GlassTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    this.enabled = true,
  });

  static const _shape = RoundedRectangleBorder(
    borderRadius: DesignTokens.cardBorderRadius,
  );

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  /// False shows the card faded, and it does not react: for an action that is
  /// not possible right now, such as one that needs the internet.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return GlassFocusRing(
      shape: _shape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Semantics(
        button: true,
        label: subtitle == null ? title : '$title, $subtitle',
        enabled: enabled,
        onTap: enabled ? onTap : null,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: _shape,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            mouseCursor: NewDesignTheme.clickCursor,
            onTap: enabled ? onTap : null,
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: enabled
                  ? _content(theme, scheme, subtitle, trailing)
                  : Opacity(
                      opacity: 0.5,
                      child: _content(theme, scheme, subtitle, trailing),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    ThemeData theme,
    ColorScheme scheme,
    String? subtitle,
    Widget? trailing,
  ) =>
      ConstrainedBox(
        // Room for a full touch target, whatever the text.
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              IconTheme.merge(
                data: IconThemeData(
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                child: trailing,
              ),
            ],
          ],
        ),
      );
}

/// The heading of a section of a list: its [title], an optional [count] after
/// it, and an optional [trailing] action, usually a [HeaderDiscButton].
class GlassSectionHeading extends StatelessWidget {
  const GlassSectionHeading({
    super.key,
    required this.title,
    this.count,
    this.trailing,
    this.titleKey,
  });

  final String title;
  final int? count;
  final Widget? trailing;

  /// The key of the text.
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = this.count;
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ConstrainedBox(
        // As high as a row with an action, with or without one.
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                // Its own node, so that it is not read as one with the text
                // around it.
                container: true,
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (count != null)
                        TextSpan(
                          text: '  $count',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  key: titleKey,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

/// The way through the weeks of a page with a week, such as the calendars:
/// arrows as discs on both sides and the [range] of the week in between, as a
/// glass control that opens [onPickWeek], usually a date picker.
///
/// [chevronOpacity] and [rangeOpacity] let a page fade the parts while the
/// week is dragged.
class GlassWeekBar extends StatelessWidget {
  const GlassWeekBar({
    super.key,
    required this.range,
    required this.onPrevious,
    required this.onNext,
    required this.onPickWeek,
    this.previousKey,
    this.nextKey,
    this.rangeKey,
    this.chevronOpacity = kAlwaysCompleteAnimation,
    this.rangeOpacity = kAlwaysCompleteAnimation,
  });

  final String range;
  final VoidCallback? onPrevious, onNext;
  final VoidCallback onPickWeek;
  final Key? previousKey, nextKey, rangeKey;
  final Animation<double> chevronOpacity, rangeOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final discStyle = HeaderDiscButton.styleOf(scheme);
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          FadeTransition(
            opacity: chevronOpacity,
            child: IconButton(
              key: previousKey,
              tooltip: context.t('exam.previousWeek'),
              style: discStyle,
              iconSize: HeaderDiscButton.iconSize,
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: FadeTransition(
              opacity: rangeOpacity,
              child: Center(
                child: FilledButton.icon(
                  key: rangeKey,
                  style: glassControlStyle(scheme),
                  onPressed: onPickWeek,
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      range,
                      maxLines: 1,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          FadeTransition(
            opacity: chevronOpacity,
            child: IconButton(
              key: nextKey,
              tooltip: context.t('exam.nextWeek'),
              style: discStyle,
              iconSize: HeaderDiscButton.iconSize,
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ),
        ],
      ),
    );
  }
}
