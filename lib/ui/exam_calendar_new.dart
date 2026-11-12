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

part of 'exam_calendar_page.dart';

/// The shape of the cards of the new design.
const _cardShape = RoundedRectangleBorder(
  borderRadius: DesignTokens.cardBorderRadius,
);

/// The gap around a list of the new design, as in [GlassListBody].
const _listGutter = EdgeInsets.fromLTRB(
  DesignTokens.gutter,
  8,
  DesignTokens.gutter,
  DesignTokens.gutter,
);

/// Whether text is so large that secondary facts go below the title.
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

Duration _motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// The exam calendar in the new design: the header of the calendar with its
/// switch, then the list of the assessments or the timeline.
class _NewExamCalendarView extends StatelessWidget {
  const _NewExamCalendarView({
    required this.upcoming,
    required this.past,
    required this.now,
    required this.timeline,
    required this.onToggleTimeline,
    required this.onOpenWeek,
    required this.cardBuilder,
  });

  final List<ExamAssessment> upcoming, past;
  final DateTime now;
  final bool timeline;
  final VoidCallback onToggleTimeline, onOpenWeek;
  final Widget Function(ExamAssessment) cardBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Measured like the calendar, so that the switch stays where it is when
    // switching between both pages.
    return LayoutBuilder(
      builder: (context, constraints) => GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('exam-calendar-app-header'),
          title: l10n.text('exam.title'),
          titleWidget: const CalendarViewSwitcher(exams: true),
          floatingMaxWidth: glassHeaderFloatingWidth(
            constraints.maxWidth,
            twoColumns: true,
          ),
          actions: [
            HeaderDiscButton(
              key: const Key('exam-timeline-view'),
              tooltip:
                  l10n.text(timeline ? 'exam.listView' : 'exam.timelineView'),
              icon: timeline ? Icons.view_list_outlined : Icons.timeline,
              onPressed: onToggleTimeline,
            ),
            HeaderDiscButton(
              key: const Key('exam-calendar-week-view'),
              tooltip: l10n.text('exam.calendarView'),
              icon: Icons.calendar_month_outlined,
              onPressed: onOpenWeek,
            ),
          ],
        ),
        body: timeline
            ? ExamTimeline(
                assessments: upcoming,
                now: now,
                assessmentBuilder: cardBuilder,
              )
            : upcoming.isEmpty && past.isEmpty
                ? GlassStateCard(
                    key: const Key('exam-calendar-empty'),
                    icon: Icons.event_available_rounded,
                    title: l10n.text('exam.empty'),
                    body: l10n.text('exam.emptyHint'),
                  )
                : _GlassExamList(
                    upcoming: upcoming,
                    past: past,
                    cardBuilder: cardBuilder,
                  ),
      ),
    );
  }
}

/// The coming assessments, built as they scroll into view, and the past ones
/// folded below them. From 1080 px the next assessment and the past ones stay
/// in a column beside the list.
class _GlassExamList extends StatelessWidget {
  const _GlassExamList({
    required this.upcoming,
    required this.past,
    required this.cardBuilder,
  });

  final List<ExamAssessment> upcoming, past;
  final Widget Function(ExamAssessment) cardBuilder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    Widget heading() => GlassSectionHeading(
          title: l10n.text('exam.upcoming'),
          count: upcoming.length,
        );
    Widget noUpcoming() => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            child: Text(
              l10n.text('exam.noUpcoming'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
    final columns =
        DashboardColumns.forWindow(MediaQuery.sizeOf(context).width);
    if (columns == null) {
      final items = <Widget Function()>[
        heading,
        if (upcoming.isEmpty) noUpcoming,
        for (final assessment in upcoming) () => cardBuilder(assessment),
        if (past.isNotEmpty) () => _PastExams(past: past),
      ];
      return GlassListBody.builder(
        listKey: const Key('exam-list'),
        itemCount: items.length,
        itemBuilder: (context, index) => items[index](),
      );
    }
    return DashboardColumnsView(
      columns: columns,
      side: Padding(
        padding: _listGutter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (upcoming.isNotEmpty) ...[
              GlassSectionHeading(title: l10n.text('exam.nextAssessment')),
              cardBuilder(upcoming.first),
            ],
            if (past.isNotEmpty) _PastExams(past: past),
          ],
        ),
      ),
      main: Builder(
        builder: (context) {
          final items = <Widget Function()>[
            heading,
            if (upcoming.isEmpty) noUpcoming,
            for (final assessment in upcoming) () => cardBuilder(assessment),
          ];
          return ListView.builder(
            key: const Key('exam-list'),
            padding: columns.listPadding(MediaQuery.paddingOf(context)) +
                _listGutter,
            itemCount: items.length,
            itemBuilder: (context, index) => items[index](),
          );
        },
      ),
    );
  }
}

/// The past assessments, folded into one card until it is opened.
class _PastExams extends StatefulWidget {
  const _PastExams({required this.past});

  final List<ExamAssessment> past;

  @override
  State<_PastExams> createState() => _PastExamsState();
}

class _PastExamsState extends State<_PastExams> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = context.l10n
        .text('exam.past', args: {'count': '${widget.past.length}'});
    final duration = _motion(context, const Duration(milliseconds: 200));
    return RepaintBoundary(
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GlassFocusRing(
              shape: _cardShape,
              activeTint: scheme.onSurface.withValues(alpha: 0.05),
              child: Semantics(
                button: true,
                expanded: _open,
                label: title,
                onTap: _toggle,
                excludeSemantics: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('exam-past-toggle'),
                    customBorder: _cardShape,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    mouseCursor: NewDesignTheme.clickCursor,
                    onTap: _toggle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _open ? 0.5 : 0,
                              duration: duration,
                              child: Icon(
                                Icons.expand_more_rounded,
                                color: scheme.onSurfaceVariant,
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
            _MaybeAnimatedSize(
              duration: duration,
              // Closed, the rows are not built.
              child: _open
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                        for (final assessment in widget.past)
                          _PastExamRow(assessment: assessment),
                        const SizedBox(height: 4),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// An [AnimatedSize], or [child] alone when motion is reduced.
class _MaybeAnimatedSize extends StatelessWidget {
  const _MaybeAnimatedSize({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          alignment: Alignment.topCenter,
          child: child,
        );
}

class _PastExamRow extends StatelessWidget {
  const _PastExamRow({required this.assessment});

  final ExamAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final date = Text(
      DateFormat('dd.MM.yyyy').format(assessment.date),
      style: secondary,
    );
    final large = _largeText(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_rounded, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assessment.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(_subtitle(context, assessment), style: secondary),
                  if (large) date,
                ],
              ),
            ),
            if (!large) ...[const SizedBox(width: 8), date],
          ],
        ),
      ),
    );
  }
}

/// An assessment on light glass: title, subject and date, how long until it,
/// and how far its study plan is.
class _GlassAssessmentCard extends StatelessWidget {
  const _GlassAssessmentCard({
    required this.assessment,
    required this.now,
    required this.completed,
    required this.customPhases,
    required this.onTap,
  });

  final ExamAssessment assessment;
  final DateTime now;
  final Set<String> completed;
  final String? customPhases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final phases = studyPhases(assessment, now, customPhases: customPhases);
    final count = phases.where((phase) => completed.contains(phase.id)).length;
    final days = assessment.daysUntil(now);
    final subtitle = _subtitle(context, assessment);
    final progress = l10n.text(
      'exam.progress',
      args: {'done': '$count', 'total': '${phases.length}'},
    );
    final large = _largeText(context);
    final titleText = Text(
      assessment.title,
      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final subtitleText = Text(
      subtitle,
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    final chip = _GlassCountdownChip(days: days);
    return GlassFocusRing(
      shape: _cardShape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Semantics(
        button: true,
        label: [
          assessment.title,
          subtitle,
          l10n.assessmentCountdown(days),
          progress,
        ].join(', '),
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('exam-card-${assessment.id}'),
            customBorder: _cardShape,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            mouseCursor: NewDesignTheme.clickCursor,
            onTap: onTap,
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (large) ...[
                    titleText,
                    const SizedBox(height: 2),
                    subtitleText,
                    const SizedBox(height: 8),
                    chip,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleText,
                              const SizedBox(height: 2),
                              subtitleText,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        chip,
                      ],
                    ),
                  const SizedBox(height: 12),
                  _StudyProgressBar(done: count, total: phases.length),
                  const SizedBox(height: 6),
                  Text(
                    progress,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many of the phases of a study plan are done, as a slim bar.
class _StudyProgressBar extends StatelessWidget {
  const _StudyProgressBar({required this.done, required this.total});

  final int done, total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = total > 0 && done == total;
    final color = finished ? scheme.success : scheme.primary;
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      child: LinearProgressIndicator(
        value: total == 0 ? 0 : done / total,
        minHeight: 6,
        color: color,
        backgroundColor: color.withValues(alpha: 0.16),
      ),
    );
  }
}

/// How long until an assessment, as a pill of glass: in the colour of an
/// exam on the day, in the warning colour in the last three days.
class _GlassCountdownChip extends StatelessWidget {
  const _GlassCountdownChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final (background, foreground) = switch (days) {
      0 => (scheme.exam, scheme.onExam),
      > 0 && <= 3 => (scheme.warningContainer, scheme.onWarningContainer),
      < 0 => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (
          scheme.secondaryContainer.withValues(
            alpha: highContrast ? 1 : DesignTokens.controlOpacity,
          ),
          scheme.onSecondaryContainer,
        ),
    };
    const shape = StadiumBorder();
    return GlassEdge(
      key: const Key('exam-countdown-chip'),
      shape: shape,
      sheen: false,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: highContrast
              ? StadiumBorder(side: BorderSide(color: scheme.outline))
              : shape,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                days == 0 ? Icons.today_rounded : Icons.hourglass_top_rounded,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  context.l10n.assessmentCountdown(days),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The details of an assessment in the new design: the assessment, its study
/// plan, the material with the notes, and the files, each on its card.
class _NewExamDetailView extends StatelessWidget {
  const _NewExamDetailView({
    required this.assessment,
    required this.days,
    required this.phases,
    required this.completed,
    required this.onPhaseDone,
    required this.onEditPhases,
    required this.noteController,
    required this.onNoteChanged,
    required this.attachments,
    required this.onAddAttachment,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
  });

  final ExamAssessment assessment;
  final int days;
  final List<StudyPhase> phases;
  final Set<String> completed;
  final void Function(String id, bool done) onPhaseDone;
  final VoidCallback onEditPhases;
  final TextEditingController noteController;
  final ValueChanged<String> onNoteChanged;
  final List<AssessmentAttachment> attachments;
  final VoidCallback onAddAttachment;
  final void Function(AssessmentAttachment) onOpenAttachment,
      onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final done =
        completed.where((id) => phases.any((phase) => phase.id == id)).length;
    final material = assessment.material;
    const rowShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    return LayoutBuilder(
      builder: (context, constraints) => GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('exam-detail-app-header'),
          title: l10n.text('exam.details'),
          floatingMaxWidth: glassHeaderFloatingWidth(constraints.maxWidth),
        ),
        body: GlassListBody(
          listKey: const Key('exam-detail-list'),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      assessment.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_subtitle(context, assessment), style: secondary),
                  const SizedBox(height: 12),
                  _GlassCountdownChip(days: days),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GlassSectionHeading(
              title: l10n.text('exam.plan'),
              trailing: HeaderDiscButton(
                key: const Key('exam-edit-phases'),
                tooltip: l10n.text('exam.edit'),
                icon: Icons.edit_outlined,
                onPressed: onEditPhases,
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StudyProgressBar(done: done, total: phases.length),
                        const SizedBox(height: 6),
                        Text(
                          l10n.text('exam.progress', args: {
                            'done': '$done',
                            'total': '${phases.length}',
                          }),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (final phase in phases)
                          CheckboxListTile(
                            key: Key('exam-phase-${phase.id}'),
                            shape: rowShape,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            value: completed.contains(phase.id),
                            title: Text(l10n.studyLabel(phase.title)),
                            subtitle: Text(_phaseSubtitle(context, phase)),
                            onChanged: (checked) =>
                                onPhaseDone(phase.id, checked == true),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GlassSectionHeading(title: l10n.text('exam.material')),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (material != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(material, style: theme.textTheme.bodyMedium),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const Key('exam-notes'),
                    controller: noteController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.text('exam.notes'),
                    ),
                    onChanged: onNoteChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GlassSectionHeading(
              title: l10n.text('exam.files'),
              count: attachments.length,
              trailing: HeaderDiscButton(
                key: const Key('exam-add-file'),
                tooltip: l10n.text('exam.addFile'),
                icon: Icons.attach_file_rounded,
                onPressed: onAddAttachment,
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      l10n.text(attachments.isEmpty
                          ? 'exam.noFiles'
                          : 'exam.localFilesHint'),
                      style: secondary,
                    ),
                  ),
                  if (attachments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Text(
                        l10n.text('exam.localFilesHint'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (final attachment in attachments)
                          ListTile(
                            shape: rowShape,
                            contentPadding:
                                const EdgeInsets.only(left: 12, right: 4),
                            leading: Icon(
                              Icons.description_outlined,
                              color: scheme.primary,
                            ),
                            title: Text(attachment.name),
                            onTap: () => onOpenAttachment(attachment),
                            trailing: IconButton(
                              tooltip: l10n.text('exam.removeFile'),
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => onRemoveAttachment(attachment),
                            ),
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
    );
  }
}

/// The editor of a study plan in the new design: a sheet of glass with the
/// phases, which opens a second one for a phase.
class _StudyPhaseSheet extends StatefulWidget {
  const _StudyPhaseSheet({required this.initial});

  final List<StudyPhase> initial;

  @override
  State<_StudyPhaseSheet> createState() => _StudyPhaseSheetState();
}

class _StudyPhaseSheetState extends State<_StudyPhaseSheet> {
  late final List<StudyPhase> _phases = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return GlassPanel(
      key: const Key('exam-phase-editor'),
      title: l10n.text('exam.editPhases'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var index = 0; index < _phases.length; index++)
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    contentPadding: const EdgeInsets.only(left: 4),
                    title: Text(l10n.studyLabel(_phases[index].title)),
                    subtitle: Text(_phaseSubtitle(context, _phases[index])),
                    onTap: () => _edit(index),
                    trailing: IconButton(
                      tooltip: l10n.text('button.delete'),
                      onPressed: () => setState(() => _phases.removeAt(index)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const Key('exam-add-phase'),
              style: glassControlStyle(scheme),
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.text('exam.addPhase')),
            ),
          ),
          const SizedBox(height: 20),
          _SheetActions(
            cancel: () => Navigator.of(context).pop(),
            confirmLabel: l10n.text('button.save'),
            confirm: () => Navigator.of(context).pop(_phases),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(int? index) async {
    final result = await showGlassSheet<StudyPhase>(
      context: context,
      builder: (_) =>
          _StudyPhaseForm(existing: index == null ? null : _phases[index]),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _phases.add(result);
      } else {
        _phases[index] = result;
      }
      _phases.sort((a, b) => a.date.compareTo(b.date));
    });
  }
}

/// Cancel and confirm at the end of a sheet.
class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.cancel,
    required this.confirmLabel,
    required this.confirm,
  });

  final VoidCallback cancel, confirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: cancel,
            child: Text(context.l10n.text('privacyConsent.cancel')),
          ),
          FilledButton(onPressed: confirm, child: Text(confirmLabel)),
        ],
      );
}

/// One phase of a study plan, new or [existing], in a sheet of its own.
class _StudyPhaseForm extends StatefulWidget {
  const _StudyPhaseForm({required this.existing});

  final StudyPhase? existing;

  @override
  State<_StudyPhaseForm> createState() => _StudyPhaseFormState();
}

class _StudyPhaseFormState extends State<_StudyPhaseForm> {
  late String _title = widget.existing?.title ?? '';
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late int _durationDays = widget.existing?.durationDays ?? 1;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _done() {
    final value = _title.trim();
    if (value.isEmpty) return;
    final existing = widget.existing;
    Navigator.pop(
      context,
      StudyPhase(
        existing?.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
        value,
        _date,
        effort: existing?.effort ?? 'Mittel',
        durationDays: _durationDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        key: const Key('exam-phase-form'),
        title: l10n.text(
          widget.existing == null ? 'exam.addPhase' : 'exam.editPhase',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            TextFormField(
              initialValue: l10n.studyLabel(_title),
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.text('exam.name'),
              ),
              onChanged: (value) => _title = value,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _durationDays,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.text('exam.duration'),
              ),
              items: [1, 2, 3, 5, 7, 14]
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(l10n.text(
                          value == 1 ? 'exam.day' : 'exam.days',
                          args: {'count': '$value'},
                        )),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _durationDays = value!),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const Key('exam-phase-date'),
                style: glassControlStyle(scheme),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('dd.MM.yyyy').format(_date)),
                onPressed: _pickDate,
              ),
            ),
            const SizedBox(height: 20),
            _SheetActions(
              cancel: () => Navigator.pop(context),
              confirmLabel: l10n.text('exam.done'),
              confirm: _done,
            ),
          ],
        ),
      ),
    );
  }
}

/// The week of the study plan in the new design: the glass header, the week
/// navigation of the calendar, and the days side by side.
class _NewExamWeekView extends StatelessWidget {
  const _NewExamWeekView({
    required this.monday,
    required this.now,
    required this.onMondayChanged,
    required this.entriesOn,
    required this.onOpen,
  });

  /// The width of a day, below which the week scrolls sideways.
  static const double minDayWidth = 145;

  final DateTime monday, now;
  final ValueChanged<DateTime> onMondayChanged;
  final _DayEntries Function(DateTime date) entriesOn;
  final ValueChanged<ExamAssessment> onOpen;

  Future<void> _pickWeek(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: monday,
    );
    if (picked != null) onMondayChanged(_mondayOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sunday = monday.add(const Duration(days: 6));
    final range = '${DateFormat('dd.MM.').format(monday)} – '
        '${DateFormat('dd.MM.yyyy').format(sunday)}';
    final currentMonday = _mondayOf(now);
    return LayoutBuilder(
      builder: (context, constraints) {
        final floatingMaxWidth = glassHeaderFloatingWidth(
          constraints.maxWidth,
          twoColumns: true,
        );
        final side = floatingMaxWidth == null ? 6.0 : DesignTokens.gutter;
        return GlassPage(
          scrolls: false,
          header: GlassPageHeader(
            surfaceKey: const Key('exam-week-app-header'),
            title: l10n.text('calendar.title'),
            floatingMaxWidth: floatingMaxWidth,
            actions: [
              if (!_sameDay(monday, currentMonday))
                HeaderDiscButton(
                  key: const Key('exam-week-current'),
                  tooltip: l10n.text('calendar.currentWeek'),
                  icon: Icons.today_outlined,
                  onPressed: () => onMondayChanged(currentMonday),
                ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: floatingMaxWidth ?? double.infinity,
              ),
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(side, 0, side, DesignTokens.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    GlassWeekBar(
                      previousKey: const Key('exam-week-previous'),
                      nextKey: const Key('exam-week-next'),
                      rangeKey: const Key('exam-week-range'),
                      range: range,
                      onPrevious: () => onMondayChanged(
                        monday.subtract(const Duration(days: 7)),
                      ),
                      onNext: () => onMondayChanged(
                        monday.add(const Duration(days: 7)),
                      ),
                      onPickWeek: () => _pickWeek(context),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = math.max(
                            constraints.maxWidth,
                            7 * minDayWidth,
                          );
                          return SingleChildScrollView(
                            key: const Key('exam-week-days'),
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: width,
                              height: constraints.maxHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var offset = 0; offset < 7; offset++)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: _buildDay(
                                          monday.add(Duration(days: offset)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDay(DateTime date) {
    final (:exams, :phases) = entriesOn(date);
    return _GlassExamDay(
      date: date,
      isToday: _sameDay(date, now),
      exams: exams,
      phases: phases,
      onOpen: onOpen,
    );
  }
}

/// One day of the week of the study plan: its name and date, then its
/// assessments and the study phases on it.
class _GlassExamDay extends StatelessWidget {
  const _GlassExamDay({
    required this.date,
    required this.isToday,
    required this.exams,
    required this.phases,
    required this.onOpen,
  });

  final DateTime date;
  final bool isToday;
  final List<ExamAssessment> exams;
  final List<({ExamAssessment assessment, StudyPhase phase})> phases;
  final ValueChanged<ExamAssessment> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final localeTag = l10n.locale.toLanguageTag();
    final headerColor =
        isToday ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            key: isToday ? const Key('exam-week-today') : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: isToday
                ? ShapeDecoration(
                    color: scheme.primaryContainer,
                    shape: const StadiumBorder(),
                  )
                : null,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.capitalize(DateFormat('EEE', localeTag).format(date)),
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isToday ? headerColor : scheme.onSurface,
                    ),
                  ),
                  Text(
                    DateFormat('dd.MM.').format(date),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: headerColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: exams.isEmpty && phases.isEmpty
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Icon(
                      Icons.remove_rounded,
                      color: scheme.outlineVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (final exam in exams)
                      _GlassWeekEntry(
                        key: Key('week-exam-${exam.id}'),
                        accent: scheme.exam,
                        kind: l10n.text('schoolTerm.exam'),
                        title: exam.title,
                        detail: exam.subject,
                        onTap: () => onOpen(exam),
                      ),
                    for (final item in phases)
                      _GlassWeekEntry(
                        accent: scheme.primary,
                        kind: l10n.text('exam.plan'),
                        title: l10n.studyLabel(item.phase.title),
                        detail: item.assessment.title,
                        onTap: () => onOpen(item.assessment),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// An assessment or a study phase in the week: a small card with a stripe in
/// its [accent] colour, one button for screen readers.
class _GlassWeekEntry extends StatelessWidget {
  const _GlassWeekEntry({
    super.key,
    required this.accent,
    required this.kind,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  static const _shape = RoundedRectangleBorder(
    borderRadius: DesignTokens.cardBorderRadius,
  );

  final Color accent;
  final String kind, title;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final detail = this.detail;
    final hasDetail = detail != null && detail.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassFocusRing(
        shape: _shape,
        activeTint: scheme.onSurface.withValues(alpha: 0.05),
        child: Semantics(
          button: true,
          label: [kind, title, if (hasDetail) detail].join(', '),
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: _shape,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              mouseCursor: NewDesignTheme.clickCursor,
              onTap: onTap,
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: DesignTokens.cardBorderRadius,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          highContrast ? null : accent.withValues(alpha: 0.08),
                      border: Border(
                        left: BorderSide(color: accent, width: 4),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kind,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hasDetail)
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
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
