import 'dart:math' as math;

import 'package:dr/assessment_attachments.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExamCalendarPage extends StatelessWidget {
  const ExamCalendarPage({
    super.key,
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
  Widget build(BuildContext context) {
    final upcoming =
        assessments.where((item) => item.daysUntil(now) >= 0).toList();
    final past = assessments
        .where((item) => item.daysUntil(now) < 0)
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prüfungskalender'),
        actions: [
          IconButton(
            key: const Key('exam-calendar-week-view'),
            tooltip: 'Kalenderansicht',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _ExamWeekCalendar(
                assessments: upcoming,
                now: now,
                completedFor: completedFor,
                phasesFor: phasesFor,
                noteFor: noteFor,
                attachmentsFor: attachmentsFor,
                onProgressChanged: onProgressChanged,
                onPhasesChanged: onPhasesChanged,
                onNoteChanged: onNoteChanged,
                onAttachmentsChanged: onAttachmentsChanged,
              ),
            )),
          ),
        ],
      ),
      body: upcoming.isEmpty && past.isEmpty
          ? const _EmptyExamCalendar()
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
              children: [
                if (upcoming.isNotEmpty) ...[
                  Text('Kommende Prüfungen',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final assessment in upcoming)
                    _AssessmentCard(
                      assessment: assessment,
                      now: now,
                      completed: completedFor(assessment.id),
                      customPhases: phasesFor(assessment.id),
                      note: noteFor(assessment.id),
                      attachments: attachmentsFor(assessment.id),
                      onProgressChanged: (value) =>
                          onProgressChanged(assessment.id, value),
                      onPhasesChanged: (value) =>
                          onPhasesChanged(assessment.id, value),
                      onNoteChanged: (value) =>
                          onNoteChanged(assessment.id, value),
                      onAttachmentsChanged: (value) =>
                          onAttachmentsChanged(assessment.id, value),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: Text('Vergangene Prüfungen (${past.length})'),
                    children: [
                      for (final assessment in past)
                        ListTile(
                          leading: const Icon(Icons.history_rounded),
                          title: Text(assessment.title),
                          subtitle: Text(_subtitle(assessment)),
                          trailing: Text(
                              DateFormat('dd.MM.yyyy').format(assessment.date)),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_available_rounded,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Noch keine Prüfungen',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                'Lege auf dem Dashboard eine Erinnerung mit /test, /cw oder /exam an. Sie erscheint automatisch hier und im Kalender.',
                textAlign: TextAlign.center),
          ]),
        ),
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
            Text(_subtitle(assessment)),
            const SizedBox(height: 12),
            LinearProgressIndicator(
                value: phases.isEmpty ? 0 : count / phases.length),
            const SizedBox(height: 6),
            Text('$count von ${phases.length} Lernphasen erledigt',
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

  @override
  Widget build(BuildContext context) {
    final days = widget.assessment.daysUntil(widget.now);
    return Scaffold(
      appBar: AppBar(title: const Text('Prüfungsdetails')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(widget.assessment.title,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(_subtitle(widget.assessment)),
        const SizedBox(height: 10),
        _CountdownChip(days: days),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Text('Lernplan',
                  style: Theme.of(context).textTheme.titleLarge)),
          TextButton.icon(
            onPressed: () => _editPhases(_phases),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Bearbeiten'),
          ),
        ]),
        Text(
            '${completed.where((id) => _phases.any((phase) => phase.id == id)).length} von ${_phases.length} Lernphasen erledigt'),
        const SizedBox(height: 8),
        for (final phase in _phases)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: completed.contains(phase.id),
            title: Text(phase.title),
            subtitle: Text(_phaseSubtitle(phase)),
            onChanged: (checked) => setState(() {
              checked == true
                  ? completed.add(phase.id)
                  : completed.remove(phase.id);
              widget.onProgressChanged(completed);
            }),
          ),
        const SizedBox(height: 16),
        Text('Prüfungsstoff', style: Theme.of(context).textTheme.titleLarge),
        if (widget.assessment.material != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.assessment.material!)),
        const SizedBox(height: 8),
        TextField(
          controller: noteController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Eigene Lernnotizen oder Stoff ergänzen'),
          onChanged: widget.onNoteChanged,
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
              child: Text('Lokale Dateien',
                  style: Theme.of(context).textTheme.titleLarge)),
          OutlinedButton.icon(
            onPressed: _addAttachment,
            icon: const Icon(Icons.attach_file_rounded),
            label: const Text('Datei hinzufügen'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
            'PDF, TXT, Markdown und andere Dateien bleiben nur auf diesem Gerät.'),
        if (attachments.isEmpty)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Noch keine Dateien angehängt.')),
        for (final attachment in attachments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(attachment.name),
            onTap: () => _openAttachment(attachment),
            trailing: IconButton(
              tooltip: 'Datei entfernen',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _removeAttachment(attachment),
            ),
          ),
      ]),
    );
  }

  Future<void> _addAttachment() async {
    final attachment = await pickAndStoreAssessmentAttachment();
    if (!mounted || attachment == null) return;
    setState(() => attachments = [...attachments, attachment]);
    widget.onAttachmentsChanged(attachments);
  }

  Future<void> _removeAttachment(AssessmentAttachment attachment) async {
    await removeAssessmentAttachment(attachment);
    if (!mounted) return;
    setState(() => attachments.remove(attachment));
    widget.onAttachmentsChanged(attachments);
  }

  Future<void> _openAttachment(AssessmentAttachment attachment) async {
    final error = await openAssessmentAttachment(attachment);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editPhases(List<StudyPhase> current) async {
    final editedPhases = await showDialog<List<StudyPhase>>(
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
  Widget build(BuildContext context) {
    final sunday = _monday.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(title: const Text('Prüfungskalender')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(
              tooltip: 'Vorherige Woche',
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
              child: const Text('Heute'),
            ),
            IconButton(
              tooltip: 'Nächste Woche',
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

  Widget _buildDay(DateTime date) {
    final exams = widget.assessments
        .where((assessment) => _sameDay(assessment.date, date))
        .toList();
    final phases = <({ExamAssessment assessment, StudyPhase phase})>[];
    for (final assessment in widget.assessments) {
      for (final phase in _phasesForAssessment(assessment)) {
        final end = phase.date.add(Duration(days: phase.durationDays));
        if (!date.isBefore(_dateOnly(phase.date)) && date.isBefore(end)) {
          phases.add((assessment: assessment, phase: phase));
        }
      }
    }

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
            Text(DateFormat('EEE', 'de').format(date),
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
                Text('Prüfung', style: Theme.of(context).textTheme.labelSmall),
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lernphase · ${phase.effort}',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(phase.title, maxLines: 3, overflow: TextOverflow.ellipsis),
              Text(assessment.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
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
        title: const Text('Lernphasen bearbeiten'),
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
                      '${DateFormat('dd.MM.yyyy').format(_phases[index].date)} · ${_phases[index].durationDays} Tage · ${_phases[index].effort}',
                    ),
                    onTap: () => _edit(index),
                    trailing: IconButton(
                      tooltip: 'Löschen',
                      onPressed: () => setState(() => _phases.removeAt(index)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Lernphase hinzufügen'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_phases),
            child: const Text('Speichern'),
          ),
        ],
      );

  Future<void> _edit(int? index) async {
    final existing = index == null ? null : _phases[index];
    var title = existing?.title ?? '';
    var date = existing?.date ?? DateTime.now();
    var effort = existing?.effort ?? 'Mittel';
    var durationDays = existing?.durationDays ?? 1;
    final result = await showDialog<StudyPhase>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(
              index == null ? 'Lernphase hinzufügen' : 'Lernphase bearbeiten'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              initialValue: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Bezeichnung'),
              onChanged: (value) => title = value,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: effort,
              decoration: const InputDecoration(labelText: 'Aufwand'),
              items: const ['Leicht', 'Mittel', 'Intensiv']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setDialogState(() => effort = value!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: durationDays,
              decoration: const InputDecoration(labelText: 'Dauer'),
              items: const [1, 2, 3, 5, 7, 14]
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value ${value == 1 ? 'Tag' : 'Tage'}')))
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
                child: const Text('Abbrechen')),
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
                      effort: effort,
                      durationDays: durationDays),
                );
              },
              child: const Text('Fertig'),
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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _mondayOf(DateTime date) =>
    _dateOnly(date).subtract(Duration(days: date.weekday - 1));

String _phaseSubtitle(StudyPhase phase) {
  final date = DateFormat('EEE, dd.MM.', 'de').format(phase.date);
  final duration =
      phase.durationDays == 1 ? '1 Tag' : '${phase.durationDays} Tage';
  return '$date · $duration · ${phase.effort}';
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.days});
  final int days;
  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(
            days == 0 ? Icons.today_rounded : Icons.hourglass_top_rounded,
            size: 18),
        label: Text(countdownLabel(days)),
      );
}

String _subtitle(ExamAssessment assessment) => [
      if (assessment.subject != null && assessment.subject!.trim().isNotEmpty)
        assessment.subject!,
      DateFormat('EEE, dd.MM.yyyy', 'de').format(assessment.date),
    ].join(' · ');
