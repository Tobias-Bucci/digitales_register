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

import 'package:dr/dashboard_events.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';

/// The colours of one banner. All of them are roles of the theme.
class EventBannerColors {
  const EventBannerColors({
    required this.background,
    required this.foreground,
    required this.edge,
  });

  final Color background, foreground, edge;
}

/// The colours of [event], see issue #100: grades follow [gradeCategory], the
/// other kinds have a colour of their own. Grades without a value stay neutral,
/// and so do grades with [colorGrades] off, which the user has to have chosen.
EventBannerColors eventBannerColors(
  ColorScheme scheme,
  DashboardEvent event, {
  required bool colorGrades,
}) {
  final neutral = EventBannerColors(
    background: scheme.surfaceContainerHigh,
    foreground: scheme.onSurface,
    edge: scheme.outline,
  );
  return switch (event.kind) {
    DashboardEventKind.grade => !colorGrades
        ? neutral
        : switch (gradeCategory(event.gradeHundredths)) {
            GradeCategory.failing => EventBannerColors(
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
                edge: scheme.error,
              ),
            GradeCategory.satisfactory => EventBannerColors(
                background: scheme.warningContainer,
                foreground: scheme.onWarningContainer,
                edge: scheme.warning,
              ),
            GradeCategory.good => EventBannerColors(
                background: scheme.successContainer,
                foreground: scheme.onSuccessContainer,
                edge: scheme.success,
              ),
            null => neutral,
          },
    DashboardEventKind.message => EventBannerColors(
        background: scheme.infoContainer,
        foreground: scheme.onInfoContainer,
        edge: scheme.info,
      ),
    DashboardEventKind.absence => EventBannerColors(
        background: scheme.noticeContainer,
        foreground: scheme.onNoticeContainer,
        edge: scheme.notice,
      ),
    DashboardEventKind.observation => EventBannerColors(
        background: scheme.observationContainer,
        foreground: scheme.onObservationContainer,
        edge: scheme.observation,
      ),
    DashboardEventKind.general => neutral,
  };
}

/// The first letter of a subject, as in the sketch: "D" for "Deutsch".
String subjectLetter(String subject) {
  final name = subject.trim();
  return name.isEmpty ? '' : name.characters.first.toUpperCase();
}

/// [percent] in the notation of the language, such as "82,5 %" in German.
String formatPercent(AppLocalizations l10n, double percent) {
  final format = NumberFormat.percentPattern(l10n.locale.toLanguageTag())
    ..maximumFractionDigits = 1;
  return format.format(percent / 100);
}

String _eventTitle(AppLocalizations l10n, DashboardEvent event) {
  final title = l10n.text(switch (event.kind) {
    DashboardEventKind.grade => 'dashboard.banner.grade',
    DashboardEventKind.message => 'dashboard.banner.message',
    DashboardEventKind.absence => 'dashboard.banner.absence',
    DashboardEventKind.observation => 'dashboard.banner.observation',
    DashboardEventKind.general => 'dashboard.banner.general',
  });
  final subject = event.subject;
  if (subject == null || subject.isEmpty) return title;
  return '$title • ${subjectLetter(l10n.translateSubjectName(subject))}';
}

IconData _eventIcon(DashboardEventKind kind) => switch (kind) {
      DashboardEventKind.grade => Icons.auto_graph_rounded,
      DashboardEventKind.message => Icons.mail_outline_rounded,
      DashboardEventKind.absence => Icons.event_busy_outlined,
      DashboardEventKind.observation => Icons.visibility_outlined,
      DashboardEventKind.general => Icons.campaign_outlined,
    };

/// The line of facts below the description of an event: its value in percent,
/// the new average and exactly when it was entered.
String _eventFacts(AppLocalizations l10n, DashboardEvent event) {
  final tag = l10n.locale.toLanguageTag();
  final before = event.averageBefore;
  final after = event.averageAfter;
  String average(int hundredths) => gradeAverageFormat.format(hundredths / 100);
  return [
    if (event.gradePercent != null) formatPercent(l10n, event.gradePercent!),
    if (after != null && (before == null || before == after))
      l10n.text('dashboard.banner.average', args: {'average': average(after)})
    else if (after != null)
      l10n.text('dashboard.banner.averageChange',
          args: {'before': average(before!), 'after': average(after)}),
    DateFormat.yMd(tag).add_Hm().format(event.time),
  ].join(' · ');
}

/// One event: compact, in the density of the dashboard cards.
class EventBanner extends StatelessWidget {
  const EventBanner({
    super.key,
    required this.event,
    required this.colorGrades,
    required this.onOpen,
    this.onDismiss,
    this.moreCount = 0,
    this.onShowMore,
  });

  final DashboardEvent event;
  final bool colorGrades;
  final VoidCallback onOpen;

  /// Null while dismissing is not possible, as offline.
  final VoidCallback? onDismiss;

  /// How many further events wait behind this one.
  final int moreCount;
  final VoidCallback? onShowMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors =
        eventBannerColors(theme.colorScheme, event, colorGrades: colorGrades);
    final foreground = colors.foreground;
    final title = _eventTitle(l10n, event);
    final facts = _eventFacts(l10n, event);
    final subject = event.subject;
    final grade = event.gradeText;
    final detail = event.detail;
    final more = moreCount > 0
        ? l10n.text('dashboard.banner.more', args: {'count': '$moreCount'})
        : null;
    return Semantics(
      container: true,
      button: true,
      liveRegion: true,
      onTap: onOpen,
      label: [
        title,
        if (subject != null) l10n.translateSubjectName(subject),
        if (grade != null) grade,
        event.description,
        if (detail != null) detail,
        facts,
        if (more != null) more,
      ].join(', '),
      customSemanticsActions: {
        if (onDismiss != null)
          CustomSemanticsAction(label: l10n.text('dashboard.banner.dismiss')):
              onDismiss!,
        if (more != null && onShowMore != null)
          CustomSemanticsAction(label: more): onShowMore!,
      },
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: colors.background.withValues(alpha: 0.92),
            borderRadius: DesignTokens.cardBorderRadius,
          ),
          child: InkWell(
            key: ValueKey('event-banner-${event.id}'),
            borderRadius: DesignTokens.cardBorderRadius,
            onTap: onOpen,
            child: GlassEdge(
              shape: const RoundedRectangleBorder(
                borderRadius: DesignTokens.cardBorderRadius,
              ),
              child: AnimatedEventEdge(
                color: colors.edge,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 7, 4, 9),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: foreground),
                    child: IconTheme.merge(
                      data: IconThemeData(color: foreground),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (more != null)
                                TextButton(
                                  key: const Key('event-banner-more'),
                                  onPressed: onShowMore,
                                  style: TextButton.styleFrom(
                                    foregroundColor: foreground,
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    minimumSize: const Size(0, 28),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    textStyle: theme.textTheme.labelMedium,
                                  ),
                                  child: Text(more),
                                ),
                              if (onDismiss != null)
                                SizedBox.square(
                                  dimension: 28,
                                  child: IconButton(
                                    key: ValueKey(
                                        'event-banner-close-${event.id}'),
                                    tooltip:
                                        l10n.text('dashboard.banner.dismiss'),
                                    onPressed: onDismiss,
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    color: foreground,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              children: [
                                if (grade != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Text(
                                      grade,
                                      key: const Key('event-banner-grade'),
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                        color: foreground,
                                        fontWeight: FontWeight.w700,
                                        height: 1.1,
                                      ),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child:
                                        Icon(_eventIcon(event.kind), size: 26),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        l10n.translateDashboardServerText(
                                            event.description),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: foreground,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        [if (detail != null) detail, facts]
                                            .join(' · '),
                                        key: const Key('event-banner-facts'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: foreground),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// The edge of a banner. A soft band of light falls down both sides twice when
/// the banner appears, then the edge rests; with reduced motion it never moves.
class AnimatedEventEdge extends StatefulWidget {
  const AnimatedEventEdge({
    super.key,
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  State<AnimatedEventEdge> createState() => _AnimatedEventEdgeState();
}

class _AnimatedEventEdgeState extends State<AnimatedEventEdge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(count: 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: EventEdgePainter(
          color: widget.color,
          animation: _controller,
        ),
        child: widget.child,
      ),
    );
  }
}

class EventEdgePainter extends CustomPainter {
  EventEdgePainter({required this.color, required this.animation})
      : super(repaint: animation);

  static const _bandHalf = 0.3;

  final Color color;
  final Animation<double> animation;

  /// The band at [progress] on its way from above the banner to below it, the
  /// same on both sides like all light of the new design.
  LinearGradient bandGradient(double progress) {
    final centre = -_bandHalf + progress * (1 + 2 * _bandHalf);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [centre - _bandHalf, centre, centre + _bandHalf],
      colors: [
        color.withValues(alpha: 0),
        color,
        color.withValues(alpha: 0),
      ],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.75);
    final edge = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(DesignTokens.cardRadius),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    canvas.drawRRect(edge, stroke);
    if (animation.isAnimating) {
      stroke
        ..strokeWidth = 2.5
        ..shader = bandGradient(animation.value).createShader(rect);
      canvas.drawRRect(edge, stroke);
    }
  }

  @override
  bool shouldRepaint(EventEdgePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The newest event and how many more there are. The stack never grows: a
/// single banner is always all the height it takes from the day list.
class EventBannerStack extends StatefulWidget {
  const EventBannerStack({
    super.key,
    required this.events,
    required this.colorGrades,
    required this.onOpen,
    required this.onDismiss,
    required this.onShowAll,
    required this.canDismiss,
  });

  final List<DashboardEvent> events;
  final bool colorGrades;
  final bool canDismiss;
  final ValueChanged<DashboardEvent> onOpen, onDismiss;
  final VoidCallback onShowAll;

  @override
  State<EventBannerStack> createState() => _EventBannerStackState();
}

class _EventBannerStackState extends State<EventBannerStack> {
  // Marking an event as seen is asynchronous, but a dismissed Dismissible has
  // to leave the tree right away.
  final Set<String> _dismissed = {};

  void _dismiss(DashboardEvent event) {
    setState(() => _dismissed.add(event.id));
    widget.onDismiss(event);
  }

  @override
  void didUpdateWidget(EventBannerStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.events.map((event) => event.id).toSet();
    _dismissed.retainWhere(current.contains);
  }

  @override
  Widget build(BuildContext context) {
    final events =
        widget.events.where((event) => !_dismissed.contains(event.id)).toList();
    final first = events.firstOrNull;
    final more = events.length - 1;
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: first == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.gutter,
                0,
                DesignTokens.gutter,
                8,
              ),
              child: Dismissible(
                key: ValueKey(first.id),
                direction: widget.canDismiss
                    ? DismissDirection.horizontal
                    : DismissDirection.none,
                onDismissed: (_) => _dismiss(first),
                child: EventBanner(
                  event: first,
                  colorGrades: widget.colorGrades,
                  onOpen: () => widget.onOpen(first),
                  onDismiss: widget.canDismiss ? () => _dismiss(first) : null,
                  moreCount: more,
                  onShowMore: widget.onShowAll,
                ),
              ),
            ),
    );
  }
}

/// All unseen events at once, behind the "+2 weitere" of [EventBannerStack].
class EventListSheet extends StatelessWidget {
  const EventListSheet({
    super.key,
    required this.events,
    required this.colorGrades,
    required this.canDismiss,
    required this.onOpen,
    required this.onDismiss,
    required this.onDismissAll,
  });

  final List<DashboardEvent> events;
  final bool colorGrades, canDismiss;
  final ValueChanged<DashboardEvent> onOpen, onDismiss;
  final VoidCallback onDismissAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          0,
          DesignTokens.gutter,
          DesignTokens.gutter,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.text('dashboard.banner.allTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (canDismiss)
                TextButton.icon(
                  onPressed: onDismissAll,
                  icon: const Icon(Icons.done_all),
                  label: Text(l10n.text('notifications.markAllRead')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EventBanner(
                event: event,
                colorGrades: colorGrades,
                onOpen: () => onOpen(event),
                onDismiss: canDismiss ? () => onDismiss(event) : null,
              ),
            ),
        ],
      ),
    );
  }
}
