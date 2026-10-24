import 'dart:math' as math;

import 'package:dr/calendar_date.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final todayColor = theme.brightness == Brightness.dark
        ? Colors.lightBlue.shade200
        : Colors.lightBlue.shade800;
    final examColor = theme.colorScheme.error;
    final normalColor = theme.colorScheme.outline;
    final dateFormat = DateFormat.yMMMd(l10n.locale.toLanguageTag());

    return ListView(
      key: const Key('exam-timeline'),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
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
