import 'dart:math' as math;

import 'package:dr/assessment_attachments.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/container/calendar_view_switcher.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/exam_timeline.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

// The views of the new design. They share the state, the helpers and the
// detail page with the Legacy views of this library.
part 'exam_calendar_new.dart';

class ExamCalendarPage extends StatefulWidget {
  const ExamCalendarPage({
    super.key,
    this.calendarView = false,
    required this.assessments,
    required this.now,
    required this.completedFor,
    required this.phasesFor,
    required this.noteFor,
    required this.attachmentsFor,
    required this.onProgressChanged,
    required this.onPhasesChanged,
    required this.onNoteChanged,
    required this.onAttachmentsChanged,
    this.weekViewBuilder,
  });

  final bool calendarView;

  /// Builds the week view route. It should subscribe to the current state so
  /// that details reopened from the week view never show an older snapshot;
  /// without it, the week view reuses this page's callbacks.
  final WidgetBuilder? weekViewBuilder;
  final List<ExamAssessment> assessments;
  final DateTime now;
  final Set<String> Function(String id) completedFor;
  final String? Function(String id) phasesFor;
  final String? Function(String id) noteFor;
  final List<AssessmentAttachment> Function(String id) attachmentsFor;
  final void Function(String id, Set<String> completed) onProgressChanged;
  final void Function(String id, List<StudyPhase> phases) onPhasesChanged;
  final void Function(String id, String note) onNoteChanged;
  final void Function(String id, List<AssessmentAttachment> attachments)
      onAttachmentsChanged;

  @override
  State<ExamCalendarPage> createState() => _ExamCalendarPageState();
}

class _ExamCalendarPageState extends State<ExamCalendarPage> {
  bool _timeline = false;

  Widget _card(ExamAssessment assessment) => _AssessmentCard(
        assessment: assessment,
        now: widget.now,
        completed: widget.completedFor(assessment.id),
        customPhases: widget.phasesFor(assessment.id),
        note: widget.noteFor(assessment.id),
        attachments: widget.attachmentsFor(assessment.id),
        onProgressChanged: (value) =>
            widget.onProgressChanged(assessment.id, value),
        onPhasesChanged: (value) =>
            widget.onPhasesChanged(assessment.id, value),
        onNoteChanged: (value) => widget.onNoteChanged(assessment.id, value),
        onAttachmentsChanged: (value) =>
            widget.onAttachmentsChanged(assessment.id, value),
      );

  /// An assessment in the new design, with the gap below it.
  Widget _glassCard(ExamAssessment assessment) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _GlassAssessmentCard(
          assessment: assessment,
          now: widget.now,
          completed: widget.completedFor(assessment.id),
          customPhases: widget.phasesFor(assessment.id),
          onTap: () => _openDetails(assessment),
        ),
      );

  void _openDetails(ExamAssessment assessment) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _ExamDetailPage(
          assessment: assessment,
          now: widget.now,
          completed: widget.completedFor(assessment.id),
          customPhases: widget.phasesFor(assessment.id),
          note: widget.noteFor(assessment.id),
          attachments: widget.attachmentsFor(assessment.id),
          onProgressChanged: (value) =>
              widget.onProgressChanged(assessment.id, value),
          onPhasesChanged: (value) =>
              widget.onPhasesChanged(assessment.id, value),
          onNoteChanged: (value) => widget.onNoteChanged(assessment.id, value),
          onAttachmentsChanged: (value) =>
              widget.onAttachmentsChanged(assessment.id, value),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final upcoming = widget.assessments
        .where((item) => item.daysUntil(widget.now) >= 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final weekCalendar = _ExamWeekCalendar(
      assessments: upcoming,
      now: widget.now,
      completedFor: widget.completedFor,
      phasesFor: widget.phasesFor,
      noteFor: widget.noteFor,
      attachmentsFor: widget.attachmentsFor,
      onProgressChanged: widget.onProgressChanged,
      onPhasesChanged: widget.onPhasesChanged,
      onNoteChanged: widget.onNoteChanged,
      onAttachmentsChanged: widget.onAttachmentsChanged,
    );
    if (widget.calendarView) return weekCalendar;
    final past = widget.assessments
        .where((item) => item.daysUntil(widget.now) < 0)
        .toList()
        .reversed
        .toList();
    if (ResponsiveNavigationScope.isActive(context)) {
      return _NewExamCalendarView(
        upcoming: upcoming,
        past: past,
        now: widget.now,
        timeline: _timeline,
        onToggleTimeline: () => setState(() => _timeline = !_timeline),
        onOpenWeek: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: widget.weekViewBuilder ?? (_) => weekCalendar,
        )),
        cardBuilder: _glassCard,
      );
    }
    final title = Text(context.l10n.text('exam.title'));
    final actions = [
      IconButton(
        key: const Key('exam-timeline-view'),
        tooltip: context.l10n
            .text(_timeline ? 'exam.listView' : 'exam.timelineView'),
        icon: Icon(_timeline ? Icons.view_list_outlined : Icons.timeline),
        onPressed: () => setState(() => _timeline = !_timeline),
      ),
      IconButton(
        key: const Key('exam-calendar-week-view'),
        tooltip: context.l10n.text('exam.calendarView'),
        icon: const Icon(Icons.calendar_month_outlined),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: widget.weekViewBuilder ?? (_) => weekCalendar,
        )),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      body: _timeline
          ? ExamTimeline(
              assessments: upcoming,
              now: widget.now,
              assessmentBuilder: _card,
            )
          : upcoming.isEmpty && past.isEmpty
              ? const _EmptyExamCalendar()
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    16,
                    12,
                    32 + ResponsiveNavigationScope.bottomInsetOf(context),
                  ),
                  children: [
                    if (upcoming.isNotEmpty) ...[
                      Text(context.l10n.text('exam.upcoming'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      for (final assessment in upcoming) _card(assessment),
                    ],
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ExpansionTile(
                        title: Text(context.l10n.text('exam.past',
                            args: {'count': '${past.length}'})),
                        children: [
                          for (final assessment in past)
                            ListTile(
                              leading: const Icon(Icons.history_rounded),
                              title: Text(assessment.title),
                              subtitle: Text(_subtitle(context, assessment)),
                              trailing: Text(DateFormat('dd.MM.yyyy')
                                  .format(assessment.date)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _EmptyExamCalendar extends StatelessWidget {
  const _EmptyExamCalendar();
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
            child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_rounded,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(context.l10n.text('exam.empty'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(context.l10n.text('exam.emptyHint'),
                textAlign: TextAlign.center),
          ]),
        )),
      );
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.assessment,
    required this.now,
    required this.completed,
    required this.customPhases,
    required this.note,
    required this.attachments,
    required this.onProgressChanged,
    required this.onPhasesChanged,
    required this.onNoteChanged,
    required this.onAttachmentsChanged,
  });
  final ExamAssessment assessment;
  final DateTime now;
  final Set<String> completed;
  final String? customPhases;
  final String? note;
  final List<AssessmentAttachment> attachments;
  final void Function(Set<String>) onProgressChanged;
  final void Function(List<StudyPhase>) onPhasesChanged;
  final void Function(String) onNoteChanged;
  final void Function(List<AssessmentAttachment>) onAttachmentsChanged;

  @override
  Widget build(BuildContext context) {
    final phases = studyPhases(assessment, now, customPhases: customPhases);
    final count = phases.where((phase) => completed.contains(phase.id)).length;
    final days = assessment.daysUntil(now);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _ExamDetailPage(
            assessment: assessment,
            now: now,
            completed: completed,
            customPhases: customPhases,
            note: note,
            attachments: attachments,
            onProgressChanged: onProgressChanged,
            onPhasesChanged: onPhasesChanged,
            onNoteChanged: onNoteChanged,
            onAttachmentsChanged: onAttachmentsChanged,
          ),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(assessment.title,
                      style: Theme.of(context).textTheme.titleMedium)),
              _CountdownChip(days: days),
            ]),
            const SizedBox(height: 4),
            Text(_subtitle(context, assessment)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: phases.isEmpty ? 0 : count / phases.length),
            const SizedBox(height: 6),
            Text(
                context.l10n.text('exam.progress',
                    args: {'done': '$count', 'total': '${phases.length}'}),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _ExamDetailPage extends StatefulWidget {
  const _ExamDetailPage(
      {required this.assessment,
      required this.now,
      required this.completed,
      required this.customPhases,
      required this.note,
      required this.attachments,
      required this.onProgressChanged,
      required this.onPhasesChanged,
      required this.onNoteChanged,
      required this.onAttachmentsChanged});
  final ExamAssessment assessment;
  final DateTime now;
  final Set<String> completed;
  final String? customPhases;
  final String? note;
  final List<AssessmentAttachment> attachments;
  final void Function(Set<String>) onProgressChanged;
  final void Function(List<StudyPhase>) onPhasesChanged;
  final void Function(String) onNoteChanged;
  final void Function(List<AssessmentAttachment>) onAttachmentsChanged;
  @override
  State<_ExamDetailPage> createState() => _ExamDetailPageState();
}

class _ExamDetailPageState extends State<_ExamDetailPage> {
  late Set<String> completed = {...widget.completed};
  late List<StudyPhase> _phases = studyPhases(
    widget.assessment,
    widget.now,
    customPhases: widget.customPhases,
  );
  late TextEditingController noteController =
      TextEditingController(text: widget.note ?? '');
  late List<AssessmentAttachment> attachments = [...widget.attachments];
  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void _setPhaseDone(String id, bool done) => setState(() {
        done ? completed.add(id) : completed.remove(id);
        widget.onProgressChanged(completed);
      });

  @override
  Widget build(BuildContext context) {
    final days = widget.assessment.daysUntil(widget.now);
    if (ResponsiveNavigationScope.isActive(context)) {
      return _NewExamDetailView(
        assessment: widget.assessment,
        days: days,
        phases: _phases,
        completed: completed,
        onPhaseDone: _setPhaseDone,
        onEditPhases: () => _editPhases(_phases),
        noteController: noteController,
        onNoteChanged: widget.onNoteChanged,
        attachments: attachments,
        onAddAttachment: _addAttachment,
        onOpenAttachment: _openAttachment,
        onRemoveAttachment: _removeAttachment,
      );
    }
    final padding = const EdgeInsets.all(16).copyWith(
      bottom: 16 + ResponsiveNavigationScope.bottomInsetOf(context),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('exam.details'))),
      body: ListView(padding: padding, children: [
        Text(widget.assessment.title,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(_subtitle(context, widget.assessment)),
        const SizedBox(height: 10),
        _CountdownChip(days: days),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Text(context.l10n.text('exam.plan'),
                  style: Theme.of(context).textTheme.titleLarge)),
          TextButton.icon(
            onPressed: () => _editPhases(_phases),
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.l10n.text('exam.edit')),
          ),
        ]),
        Text(context.l10n.text('exam.progress', args: {
          'done':
              '${completed.where((id) => _phases.any((phase) => phase.id == id)).length}',
          'total': '${_phases.length}'
        })),
        const SizedBox(height: 8),
        for (final phase in _phases)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: completed.contains(phase.id),
            title: Text(context.l10n.studyLabel(phase.title)),
            subtitle: Text(_phaseSubtitle(context, phase)),
            onChanged: (checked) => setState(() {
              checked == true
                  ? completed.add(phase.id)
                  : completed.remove(phase.id);
              widget.onProgressChanged(completed);
            }),
          ),
        const SizedBox(height: 16),
        Text(context.l10n.text('exam.material'),
            style: Theme.of(context).textTheme.titleLarge),
        if (widget.assessment.material != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.assessment.material!)),
        const SizedBox(height: 8),
        TextField(
          controller: noteController,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.l10n.text('exam.notes')),
          onChanged: widget.onNoteChanged,
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Text(context.l10n.text('exam.files'),
                  style: Theme.of(context).textTheme.titleLarge)),
          OutlinedButton.icon(
            onPressed: _addAttachment,
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(context.l10n.text('exam.addFile')),
          ),
        ]),
        const SizedBox(height: 4),
        Text(context.l10n.text('exam.localFilesHint')),
        if (attachments.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.l10n.text('exam.noFiles'))),
        for (final attachment in attachments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(attachment.name),
            onTap: () => _openAttachment(attachment),
            trailing: IconButton(
              tooltip: context.l10n.text('exam.removeFile'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _removeAttachment(attachment),
            ),
          ),
      ]),
    );
  }

  Future<void> _addAttachment() async {
    final attachment =
        await pickAndStoreAssessmentAttachment(currentAccountScope());
    if (!mounted || attachment == null) return;
    setState(() => attachments = [...attachments, attachment]);
    widget.onAttachmentsChanged(attachments);
  }

  Future<void> _removeAttachment(AssessmentAttachment attachment) async {
    await removeAssessmentAttachment(attachment, currentAccountScope());
    if (!mounted) return;
    setState(() => attachments.remove(attachment));
    widget.onAttachmentsChanged(attachments);
  }

  Future<void> _openAttachment(AssessmentAttachment attachment) async {
    final error =
        await openAssessmentAttachment(attachment, currentAccountScope());
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('attachment.openFailed'))));
  }

  Future<void> _editPhases(List<StudyPhase> current) async {
    final editedPhases = ResponsiveNavigationScope.isActive(context)
        // A sheet of glass. It takes the theme of the page along, so the date
        // picker it opens gets the rim of the glass.
        ? await showGlassSheet<List<StudyPhase>>(
            context: context,
            builder: (_) => _StudyPhaseSheet(initial: current),
          )
        : await showDialog<List<StudyPhase>>(
            context: context,
            builder: (_) => _StudyPhaseEditor(initial: current),
          );
    if (editedPhases == null) return;
    final completedIds = editedPhases.map((phase) => phase.id).toSet();
    setState(() {
      _phases = editedPhases;
      completed.removeWhere((id) => !completedIds.contains(id));
    });
    widget.onProgressChanged(completed);
    widget.onPhasesChanged(editedPhases);
  }
}

class _ExamWeekCalendar extends StatefulWidget {
  const _ExamWeekCalendar({
    required this.assessments,
    required this.now,
    required this.completedFor,
    required this.phasesFor,
    required this.noteFor,
    required this.attachmentsFor,
    required this.onProgressChanged,
    required this.onPhasesChanged,
    required this.onNoteChanged,
    required this.onAttachmentsChanged,
  });

  final List<ExamAssessment> assessments;
  final DateTime now;
  final Set<String> Function(String id) completedFor;
  final String? Function(String id) phasesFor;
  final String? Function(String id) noteFor;
  final List<AssessmentAttachment> Function(String id) attachmentsFor;
  final void Function(String id, Set<String> completed) onProgressChanged;
  final void Function(String id, List<StudyPhase> phases) onPhasesChanged;
  final void Function(String id, String note) onNoteChanged;
  final void Function(String id, List<AssessmentAttachment> attachments)
      onAttachmentsChanged;

  @override
  State<_ExamWeekCalendar> createState() => _ExamWeekCalendarState();
}

class _ExamWeekCalendarState extends State<_ExamWeekCalendar> {
  late DateTime _monday = _mondayOf(widget.now);
  final Map<String, List<StudyPhase>> _phaseOverrides = {};

  @override
  void didUpdateWidget(_ExamWeekCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fresh callbacks resolve the current state, which already contains
    // phases edited here; local overrides would otherwise shadow later
    // changes made elsewhere.
    _phaseOverrides.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _NewExamWeekView(
        monday: _monday,
        now: widget.now,
        onMondayChanged: (monday) => setState(() => _monday = monday),
        entriesOn: _entriesOn,
        onOpen: _openAssessment,
      );
    }
    final sunday = _monday.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('exam.title'))),
      bottomNavigationBar: ResponsiveNavigationScope.spacerOf(context),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(
              tooltip: context.l10n.text('exam.previousWeek'),
              onPressed: () => setState(
                () => _monday = _monday.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                '${DateFormat('dd.MM.').format(_monday)} – ${DateFormat('dd.MM.yyyy').format(sunday)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _monday = _mondayOf(widget.now)),
              child: Text(context.l10n.text('day.today')),
            ),
            IconButton(
              tooltip: context.l10n.text('exam.nextWeek'),
              onPressed: () => setState(
                () => _monday = _monday.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, 7 * 145.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var offset = 0; offset < 7; offset++)
                        Expanded(
                            child:
                                _buildDay(_monday.add(Duration(days: offset)))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  /// The assessments on [date] and the study phases that cover it.
  _DayEntries _entriesOn(DateTime date) {
    final exams = widget.assessments
        .where((assessment) => _sameDay(assessment.date, date))
        .toList();
    final phases = <({ExamAssessment assessment, StudyPhase phase})>[];
    for (final assessment in widget.assessments) {
      for (final phase in _phasesForAssessment(assessment)) {
        final end =
            calendarDate(phase.date).add(Duration(days: phase.durationDays));
        if (!date.isBefore(_dateOnly(phase.date)) && date.isBefore(end)) {
          phases.add((assessment: assessment, phase: phase));
        }
      }
    }
    return (exams: exams, phases: phases);
  }

  Widget _buildDay(DateTime date) {
    final (:exams, :phases) = _entriesOn(date);

    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _sameDay(date, widget.now)
            ? theme.colorScheme.primaryContainer.withValues(alpha: .35)
            : null,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Column(children: [
            Text(
                DateFormat('EEE', context.l10n.locale.toLanguageTag())
                    .format(date),
                style: theme.textTheme.labelLarge),
            Text(DateFormat('dd.MM.').format(date),
                style: theme.textTheme.bodySmall),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(5),
            children: [
              for (final exam in exams) _examTile(exam),
              for (final item in phases)
                _phaseTile(item.assessment, item.phase),
              if (exams.isEmpty && phases.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(Icons.remove_rounded,
                      color: theme.colorScheme.outlineVariant),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _examTile(ExamAssessment assessment) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        color: Theme.of(context).colorScheme.errorContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('week-exam-${assessment.id}'),
          onTap: () => _openAssessment(assessment),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.text('schoolTerm.exam'),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(assessment.title,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                if (assessment.subject?.isNotEmpty ?? false)
                  Text(assessment.subject!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

  Widget _phaseTile(ExamAssessment assessment, StudyPhase phase) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        color: Theme.of(context).colorScheme.secondaryContainer,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openAssessment(assessment),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.text('exam.plan'),
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(context.l10n.studyLabel(phase.title),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                Text(assessment.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );

  void _openAssessment(ExamAssessment assessment) {
    final overriddenPhases = _phaseOverrides[assessment.id];
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _ExamDetailPage(
        assessment: assessment,
        now: widget.now,
        completed: widget.completedFor(assessment.id),
        customPhases: overriddenPhases == null
            ? widget.phasesFor(assessment.id)
            : encodeStudyPhases(overriddenPhases),
        note: widget.noteFor(assessment.id),
        attachments: widget.attachmentsFor(assessment.id),
        onProgressChanged: (value) =>
            widget.onProgressChanged(assessment.id, value),
        onPhasesChanged: (value) {
          if (mounted) {
            setState(() => _phaseOverrides[assessment.id] = [...value]);
          }
          widget.onPhasesChanged(assessment.id, value);
        },
        onNoteChanged: (value) => widget.onNoteChanged(assessment.id, value),
        onAttachmentsChanged: (value) =>
            widget.onAttachmentsChanged(assessment.id, value),
      ),
    ));
  }

  List<StudyPhase> _phasesForAssessment(ExamAssessment assessment) =>
      _phaseOverrides[assessment.id] ??
      studyPhases(
        assessment,
        widget.now,
        customPhases: widget.phasesFor(assessment.id),
      );
}

class _StudyPhaseEditor extends StatefulWidget {
  const _StudyPhaseEditor({required this.initial});
  final List<StudyPhase> initial;

  @override
  State<_StudyPhaseEditor> createState() => _StudyPhaseEditorState();
}

class _StudyPhaseEditorState extends State<_StudyPhaseEditor> {
  late final List<StudyPhase> _phases = [...widget.initial];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.text('exam.editPhases')),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var index = 0; index < _phases.length; index++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_phases[index].title),
                    subtitle: Text(
                      _phaseSubtitle(context, _phases[index]),
                    ),
                    onTap: () => _edit(index),
                    trailing: IconButton(
                      tooltip: context.l10n.text('button.delete'),
                      onPressed: () => setState(() => _phases.removeAt(index)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.l10n.text('exam.addPhase')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.text('privacyConsent.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_phases),
            child: Text(context.l10n.text('button.save')),
          ),
        ],
      );

  Future<void> _edit(int? index) async {
    final existing = index == null ? null : _phases[index];
    var title = existing?.title ?? '';
    var date = existing?.date ?? DateTime.now();
    var durationDays = existing?.durationDays ?? 1;
    final result = await showDialog<StudyPhase>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(context.l10n
              .text(index == null ? 'exam.addPhase' : 'exam.editPhase')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              initialValue: context.l10n.studyLabel(title),
              autofocus: true,
              decoration:
                  InputDecoration(labelText: context.l10n.text('exam.name')),
              onChanged: (value) => title = value,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: durationDays,
              decoration: InputDecoration(
                  labelText: context.l10n.text('exam.duration')),
              items: [1, 2, 3, 5, 7, 14]
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(context.l10n.text(
                          value == 1 ? 'exam.day' : 'exam.days',
                          args: {'count': '$value'}))))
                  .toList(),
              onChanged: (value) => setDialogState(() => durationDays = value!),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('dd.MM.yyyy').format(date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDate: date,
                );
                if (picked != null) setDialogState(() => date = picked);
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.text('privacyConsent.cancel'))),
            FilledButton(
              onPressed: () {
                final value = title.trim();
                if (value.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  StudyPhase(
                      existing?.id ??
                          'custom-${DateTime.now().microsecondsSinceEpoch}',
                      value,
                      date,
                      effort: existing?.effort ?? 'Mittel',
                      durationDays: durationDays),
                );
              },
              child: Text(context.l10n.text('exam.done')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
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

typedef _DayEntries = ({
  List<ExamAssessment> exams,
  List<({ExamAssessment assessment, StudyPhase phase})> phases,
});

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime date) => calendarDate(date);

DateTime _mondayOf(DateTime date) =>
    _dateOnly(date).subtract(Duration(days: date.weekday - 1));

String _phaseSubtitle(BuildContext context, StudyPhase phase) {
  final date = DateFormat('EEE, dd.MM.', context.l10n.locale.toLanguageTag())
      .format(phase.date);
  final duration = context.l10n.text(
      phase.durationDays == 1 ? 'exam.day' : 'exam.days',
      args: {'count': '${phase.durationDays}'});
  return '$date · $duration';
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.days});
  final int days;
  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(
            days == 0 ? Icons.today_rounded : Icons.hourglass_top_rounded,
            size: 18),
        label: Text(context.l10n.assessmentCountdown(days)),
      );
}

String _subtitle(BuildContext context, ExamAssessment assessment) => [
      if (assessment.subject != null && assessment.subject!.trim().isNotEmpty)
        assessment.subject!,
      DateFormat('EEE, dd.MM.yyyy', context.l10n.locale.toLanguageTag())
          .format(assessment.date),
    ].join(' · ');
