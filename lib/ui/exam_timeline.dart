import 'dart:math' as math;

import 'package:dr/calendar_date.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Seven equally spaced calendar days keep distances meaningful at any range.
class ExamTimeline extends StatefulWidget {
  const ExamTimeline({
    super.key,
    required this.assessments,
    required this.now,
    required this.assessmentBuilder,
  });

  final List<ExamAssessment> assessments;
  final DateTime now;
  final Widget Function(ExamAssessment) assessmentBuilder;

  @override
  State<ExamTimeline> createState() => _ExamTimelineState();
}

class _ExamTimelineState extends State<ExamTimeline> {
  late DateTime _start = calendarDate(widget.now);
  late DateTime _selected = _start;

  DateTime get _today => calendarDate(widget.now);

  @override
  void didUpdateWidget(ExamTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_start.isBefore(_today)) _showDay(_today);
  }

  void _showDay(DateTime day) {
    _selected = calendarDate(day);
    final offset = calendarDaysBetween(_selected, _today);
    _start = _today.add(Duration(days: (offset ~/ 7) * 7));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final upcoming = widget.assessments
        .where((exam) => exam.daysUntil(widget.now) >= 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final byDay = <DateTime, List<ExamAssessment>>{};
    for (final exam in upcoming) {
      byDay.putIfAbsent(calendarDate(exam.date), () => []).add(exam);
    }
    final last = upcoming.isEmpty ? _today : calendarDate(upcoming.last.date);
    final end = _start.add(const Duration(days: 6));
    final next =
        upcoming.where((exam) => calendarDate(exam.date).isAfter(_selected));
    final todayColor = theme.colorScheme.primary;
    final examColor = theme.colorScheme.exam;
    final normalColor = theme.colorScheme.outline;
    final dateFormat = DateFormat.yMMMd(l10n.locale.toLanguageTag());

    if (ResponsiveNavigationScope.isActive(context)) {
      return _buildNew(
        context,
        upcoming: upcoming,
        byDay: byDay,
        last: last,
        end: end,
        next: next,
        dateFormat: dateFormat,
      );
    }

    return ListView(
      key: const Key('exam-timeline'),
      padding: EdgeInsets.fromLTRB(
        12,
        16,
        12,
        32 + ResponsiveNavigationScope.bottomInsetOf(context),
      ),
      children: [
        Text(l10n.text('exam.timelineView'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _legend(todayColor, Icons.today, l10n.text('day.today')),
          _legend(
              examColor, Icons.school_outlined, l10n.text('schoolTerm.exam')),
          _legend(
              normalColor, Icons.circle_outlined, l10n.text('exam.regularDay')),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          IconButton(
            key: const Key('timeline-previous'),
            tooltip: l10n.text('exam.previousWeek'),
            onPressed: _start.isAfter(_today)
                ? () => setState(
                    () => _showDay(_start.subtract(const Duration(days: 7))))
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
                '${dateFormat.format(_start)} – ${dateFormat.format(end)}',
                textAlign: TextAlign.center),
          ),
          IconButton(
            key: const Key('timeline-next'),
            tooltip: l10n.text('exam.nextWeek'),
            onPressed: end.isBefore(last)
                ? () => setState(
                    () => _showDay(_start.add(const Duration(days: 7))))
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        LayoutBuilder(builder: (context, constraints) {
          final width = math.max(7 * 48.0, constraints.maxWidth);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var offset = 0; offset < 7; offset++)
                  Expanded(
                      child: _day(
                    _start.add(Duration(days: offset)),
                    byDay,
                    todayColor,
                    examColor,
                    normalColor,
                  )),
              ]),
            ),
          );
        }),
        Wrap(spacing: 8, children: [
          TextButton(
            key: const Key('timeline-today'),
            onPressed: () => setState(() => _showDay(_today)),
            child: Text(l10n.text('day.today')),
          ),
          TextButton.icon(
            key: const Key('timeline-next-assessment'),
            onPressed: next.isEmpty
                ? null
                : () => setState(() => _showDay(next.first.date)),
            icon: const Icon(Icons.skip_next_outlined),
            label: Text(l10n.text('exam.nextAssessment')),
          ),
        ]),
        const SizedBox(height: 16),
        Text(dateFormat.format(_selected), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          Text(l10n.text('exam.noUpcoming'))
        else if (!byDay.containsKey(_selected))
          Text(l10n.text('exam.noAssessmentsOnDay')),
        for (final exam in byDay[_selected] ?? <ExamAssessment>[])
          widget.assessmentBuilder(exam),
      ],
    );
  }

  /// The timeline in the new design: the week of days with the legend and
  /// the way through the weeks on a card, beside the assessments of the day
  /// from 1080 px and above them below.
  Widget _buildNew(
    BuildContext context, {
    required List<ExamAssessment> upcoming,
    required Map<DateTime, List<ExamAssessment>> byDay,
    required DateTime last,
    required DateTime end,
    required Iterable<ExamAssessment> next,
    required DateFormat dateFormat,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final discStyle = HeaderDiscButton.styleOf(scheme);
    final dayExams = byDay[_selected] ?? const <ExamAssessment>[];
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(child: Text(text, style: secondary)),
        );
    final strip = GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _glassLegend(
                    scheme.primary, Icons.today, l10n.text('day.today')),
                _glassLegend(scheme.exam, Icons.school_outlined,
                    l10n.text('schoolTerm.exam')),
                _glassLegend(scheme.outline, Icons.circle_outlined,
                    l10n.text('exam.regularDay')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const Key('timeline-previous'),
                tooltip: l10n.text('exam.previousWeek'),
                style: discStyle,
                iconSize: HeaderDiscButton.iconSize,
                onPressed: _start.isAfter(_today)
                    ? () => setState(() =>
                        _showDay(_start.subtract(const Duration(days: 7))))
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${dateFormat.format(_start)} – ${dateFormat.format(end)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('timeline-next'),
                tooltip: l10n.text('exam.nextWeek'),
                style: discStyle,
                iconSize: HeaderDiscButton.iconSize,
                onPressed: end.isBefore(last)
                    ? () => setState(
                        () => _showDay(_start.add(const Duration(days: 7))))
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, constraints) {
            final width = math.max(7 * 44.0, constraints.maxWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var offset = 0; offset < 7; offset++)
                      Expanded(
                        child: _glassDay(
                          _start.add(Duration(days: offset)),
                          byDay,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const Key('timeline-today'),
                style: glassControlStyle(scheme),
                onPressed: () => setState(() => _showDay(_today)),
                child: Text(l10n.text('day.today')),
              ),
              FilledButton.icon(
                key: const Key('timeline-next-assessment'),
                style: glassControlStyle(scheme),
                onPressed: next.isEmpty
                    ? null
                    : () => setState(() => _showDay(next.first.date)),
                icon: const Icon(Icons.skip_next_outlined, size: 18),
                label: Text(l10n.text('exam.nextAssessment')),
              ),
            ],
          ),
        ],
      ),
    );
    return GlassColumnsBody(
      listKey: const Key('exam-timeline'),
      side: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSectionHeading(title: l10n.text('exam.timelineView')),
          strip,
          const SizedBox(height: 8),
        ],
      ),
      main: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSectionHeading(
            title: dateFormat.format(_selected),
            count: dayExams.isEmpty ? null : dayExams.length,
          ),
          if (upcoming.isEmpty)
            note(l10n.text('exam.noUpcoming'))
          else if (dayExams.isEmpty)
            note(l10n.text('exam.noAssessmentsOnDay')),
          for (final exam in dayExams) widget.assessmentBuilder(exam),
        ],
      ),
    );
  }

  Widget _glassLegend(Color color, IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );

  /// A day of the week of the new design: a mark on the line, red where there
  /// are assessments, and the day picked as a tonal pill.
  Widget _glassDay(DateTime day, Map<DateTime, List<ExamAssessment>> byDay) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final count = byDay[day]?.length ?? 0;
    final isToday = day == _today;
    final selected = day == _selected;
    final highContrast = MediaQuery.highContrastOf(context);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    final label = [
      DateFormat.yMMMMEEEEd(l10n.locale.toLanguageTag()).format(day),
      if (isToday) l10n.text('day.today'),
      l10n.text('exam.assessmentsCount', args: {'count': '$count'}),
    ].join(', ');
    final marked = count > 0 || isToday;
    final markColor = count > 0 ? scheme.exam : scheme.primary;
    final onMark = count > 0 ? scheme.onExam : scheme.onPrimary;
    void select() => setState(() => _selected = day);
    return GlassFocusRing(
      shape: shape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Semantics(
        label: label,
        button: true,
        selected: selected,
        excludeSemantics: true,
        onTap: select,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('timeline-day-${DateFormat('yyyy-MM-dd').format(day)}'),
            onTap: select,
            customBorder: shape,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            mouseCursor: NewDesignTheme.clickCursor,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: selected && highContrast
                    ? shape.copyWith(side: BorderSide(color: scheme.outline))
                    : shape,
                color: selected
                    ? scheme.secondaryContainer.withValues(
                        alpha: highContrast ? 1 : DesignTokens.controlOpacity,
                      )
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(children: [
                  Text(
                    DateFormat('EE', l10n.locale.toLanguageTag()).format(day),
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 32,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(height: 2, color: scheme.outlineVariant),
                      if (marked)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: markColor,
                            border: isToday && count > 0
                                ? Border.all(color: scheme.primary, width: 3)
                                : null,
                          ),
                          child: Icon(
                            count > 0 ? Icons.school_outlined : Icons.today,
                            size: 18,
                            color: onMark,
                          ),
                        )
                      else
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.outline,
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('dd.MM.').format(day),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    count > 0 ? '$count' : '–',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: count > 0 ? scheme.exam : scheme.onSurfaceVariant,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(Color color, IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(label)),
      ]);

  Widget _day(DateTime day, Map<DateTime, List<ExamAssessment>> byDay,
      Color todayColor, Color examColor, Color normalColor) {
    final count = byDay[day]?.length ?? 0;
    final isToday = day == _today;
    final selected = day == _selected;
    final l10n = context.l10n;
    final color = count > 0
        ? examColor
        : isToday
            ? todayColor
            : normalColor;
    final label = [
      DateFormat.yMMMMEEEEd(l10n.locale.toLanguageTag()).format(day),
      if (isToday) l10n.text('day.today'),
      l10n.text('exam.assessmentsCount', args: {'count': '$count'}),
    ].join(', ');
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      onTap: () => setState(() => _selected = day),
      child: InkWell(
        key: Key('timeline-day-${DateFormat('yyyy-MM-dd').format(day)}'),
        onTap: () => setState(() => _selected = day),
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(DateFormat('EE', l10n.locale.toLanguageTag()).format(day)),
              const SizedBox(height: 8),
              Stack(alignment: Alignment.center, children: [
                Container(height: 2, color: normalColor),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: isToday
                        ? Border.all(color: todayColor, width: 4)
                        : null,
                  ),
                  child: Icon(
                      count > 0
                          ? Icons.school_outlined
                          : isToday
                              ? Icons.today
                              : Icons.circle,
                      size: count > 0 || isToday ? 18 : 8,
                      color: Theme.of(context).colorScheme.surface),
                ),
              ]),
              const SizedBox(height: 8),
              Text(DateFormat('dd.MM.').format(day)),
              Text(count > 0 ? '$count' : '–'),
            ]),
          ),
        ),
      ),
    );
  }
}
