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
    required this.noteFor,
    required this.attachmentsFor,
    required this.onProgressChanged,
    required this.onNoteChanged,
    required this.onAttachmentsChanged,
  });

  final List<ExamAssessment> assessments;
  final DateTime now;
  final Set<String> Function(String id) completedFor;
  final String? Function(String id) noteFor;
  final List<AssessmentAttachment> Function(String id) attachmentsFor;
  final void Function(String id, Set<String> completed) onProgressChanged;
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
      appBar: AppBar(title: const Text('Prüfungskalender')),
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
                      note: noteFor(assessment.id),
                      attachments: attachmentsFor(assessment.id),
                      onProgressChanged: (value) =>
                          onProgressChanged(assessment.id, value),
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
    required this.note,
    required this.attachments,
    required this.onProgressChanged,
    required this.onNoteChanged,
    required this.onAttachmentsChanged,
  });
  final ExamAssessment assessment;
  final DateTime now;
  final Set<String> completed;
  final String? note;
  final List<AssessmentAttachment> attachments;
  final void Function(Set<String>) onProgressChanged;
  final void Function(String) onNoteChanged;
  final void Function(List<AssessmentAttachment>) onAttachmentsChanged;

  @override
  Widget build(BuildContext context) {
    final phases = studyPhases(assessment, now);
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
            note: note,
            attachments: attachments,
            onProgressChanged: onProgressChanged,
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
      required this.note,
      required this.attachments,
      required this.onProgressChanged,
      required this.onNoteChanged,
      required this.onAttachmentsChanged});
  final ExamAssessment assessment;
  final DateTime now;
  final Set<String> completed;
  final String? note;
  final List<AssessmentAttachment> attachments;
  final void Function(Set<String>) onProgressChanged;
  final void Function(String) onNoteChanged;
  final void Function(List<AssessmentAttachment>) onAttachmentsChanged;
  @override
  State<_ExamDetailPage> createState() => _ExamDetailPageState();
}

class _ExamDetailPageState extends State<_ExamDetailPage> {
  late Set<String> completed = {...widget.completed};
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
    final phases = studyPhases(widget.assessment, widget.now);
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
        Text('Lernplan', style: Theme.of(context).textTheme.titleLarge),
        Text(
            '${completed.where((id) => phases.any((phase) => phase.id == id)).length} von ${phases.length} Lernphasen erledigt'),
        const SizedBox(height: 8),
        for (final phase in phases)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: completed.contains(phase.id),
            title: Text(phase.title),
            subtitle: Text(DateFormat('EEE, dd.MM.', 'de').format(phase.date)),
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
