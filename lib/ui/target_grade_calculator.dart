import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/target_grade_calculation.dart';
import 'package:dr/ui/grade_calculator.dart' show tryParseFormattedGrade;
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';

class TargetGradeCalculator extends StatelessWidget {
  const TargetGradeCalculator({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => AnimatedBuilder(
        animation: appClock,
        builder: (context, _) => _TargetGradeCalculatorPage(
          state: state,
          now: appClock.now,
        ),
      ),
    );
  }
}

class _TargetGradeCalculatorPage extends StatefulWidget {
  const _TargetGradeCalculatorPage({required this.state, required this.now});

  final AppState state;
  final DateTime now;

  @override
  State<_TargetGradeCalculatorPage> createState() =>
      _TargetGradeCalculatorPageState();
}

class _TargetGradeCalculatorPageState
    extends State<_TargetGradeCalculatorPage> {
  static const _minimumFutureGrades = 0;
  static const _maximumFutureGrades = 10;

  final _targetController = TextEditingController();
  final List<TextEditingController> _weightControllers =
      <TextEditingController>[];
  final List<TargetGradeEntry> _additionalExistingGrades = <TargetGradeEntry>[];
  bool _includeCalendarAssessments = true;
  Subject? _subject;
  Semester _semester = Semester.all;
  TargetGradeCalculation? _calculation;
  String? _error;

  List<Subject> get _subjects => widget.state.gradesState.subjects.toList();

  List<ExamAssessment> get _calendarAssessments => _subject == null
      ? const <ExamAssessment>[]
      : upcomingExamAssessmentsForSubject(widget.state, _subject!, widget.now);

  List<ExamAssessment> get _includedCalendarAssessments =>
      _includeCalendarAssessments
          ? _calendarAssessments
          : const <ExamAssessment>[];

  List<int> get _futureWeights => <int>[
        ...List<int>.filled(_includedCalendarAssessments.length, 100),
        ..._weightControllers.map((controller) => int.parse(controller.text)),
      ];

  @override
  void didUpdateWidget(covariant _TargetGradeCalculatorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state || widget.now != oldWidget.now) {
      _calculation = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    for (final controller in _weightControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<GradeAll> get _grades =>
      _subject
          ?.basicGrades(_semester)
          ?.where((grade) => !grade.cancelled && grade.grade != null)
          .toList() ??
      <GradeAll>[];

  List<TargetGradeEntry> get _calculationGrades => <TargetGradeEntry>[
        ..._grades.map(
          (grade) => TargetGradeEntry(
            grade: grade.grade!,
            weightPercentage: grade.weightPercentage,
          ),
        ),
        ..._additionalExistingGrades,
      ];

  void _changeFutureGradeCount(int delta) {
    final nextCount = _weightControllers.length + delta;
    if (nextCount < _minimumFutureGrades || nextCount > _maximumFutureGrades) {
      return;
    }
    setState(() {
      if (delta > 0) {
        _weightControllers.add(TextEditingController(text: '100'));
      } else {
        _weightControllers.removeLast().dispose();
      }
      _calculation = null;
      _error = null;
    });
  }

  void _calculate() {
    final l10n = context.l10n;
    final target = tryParseFormattedGrade(_targetController.text);
    final manualWeights = _weightControllers
        .map((controller) => int.tryParse(controller.text))
        .toList();
    if (_subject == null) {
      setState(
          () => _error = l10n.text('targetCalculator.error.selectSubject'));
      return;
    }
    if (_calculationGrades.isEmpty) {
      setState(() => _error = l10n.text('targetCalculator.error.noGrades'));
      return;
    }
    if (target == null || target < minimumGrade || target > maximumGrade) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidTarget'));
      return;
    }
    if (_calculationGrades.any(
      (grade) =>
          grade.grade < minimumGrade ||
          grade.grade > maximumGrade ||
          grade.weightPercentage < 0,
    )) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidExisting'));
      return;
    }
    if (manualWeights
        .any((weight) => weight == null || weight <= 0 || weight > 100)) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidWeight'));
      return;
    }
    if (_includedCalendarAssessments.isEmpty && manualWeights.isEmpty) {
      setState(
          () => _error = l10n.text('targetCalculator.error.noFutureGrades'));
      return;
    }
    final calculation = calculateTargetGrades(
      existingGrades: _calculationGrades,
      targetGrade: target,
      futureWeights: <int>[
        ...List<int>.filled(_includedCalendarAssessments.length, 100),
        ...manualWeights.cast<int>(),
      ],
    );
    setState(() {
      _calculation = calculation;
      _error = null;
    });
  }

  String _formatAverage(double average) =>
      gradeAverageFormat.format(average / 100);

  String _formatContribution(int value) =>
      gradeAverageFormat.format(value / 10000);

  Future<void> _addExistingGrade() async {
    final gradeController = TextEditingController();
    final weightController = TextEditingController(text: '100');
    String? error;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.text('targetCalculator.addExistingGrade')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: gradeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: context.l10n.text('gradeCalculator.grade')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.text('gradeCalculator.weight'),
                suffixText: '%',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.text('dialog.close')),
            ),
            ElevatedButton(
              onPressed: () {
                final grade = tryParseFormattedGrade(gradeController.text);
                final weight = int.tryParse(weightController.text);
                if (grade == null ||
                    grade < minimumGrade ||
                    grade > maximumGrade ||
                    weight == null ||
                    weight < 0) {
                  setDialogState(() => error = context.l10n
                      .text('targetCalculator.error.invalidExisting'));
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child:
                  Text(context.l10n.text('targetCalculator.addExistingGrade')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || added != true) {
      gradeController.dispose();
      weightController.dispose();
      return;
    }
    setState(() {
      _additionalExistingGrades.add(TargetGradeEntry(
        grade: tryParseFormattedGrade(gradeController.text)!,
        weightPercentage: int.parse(weightController.text),
      ));
      _calculation = null;
      _error = null;
    });
    gradeController.dispose();
    weightController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grades = _grades;
    final calendarAssessments = _calendarAssessments;
    final existingWeight = _calculationGrades.fold<int>(
      0,
      (sum, grade) => sum + grade.weightPercentage,
    );
    final existingScore = _calculationGrades.fold<int>(
      0,
      (sum, grade) => sum + grade.grade * grade.weightPercentage,
    );
    final currentAverage =
        existingWeight == 0 ? null : existingScore / existingWeight;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('targetCalculator.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Subject>(
            key: const Key('target-calculator-subject'),
            initialValue: _subject,
            decoration: InputDecoration(
                labelText: l10n.text('targetCalculator.subject')),
            items: _subjects
                .map(
                  (subject) => DropdownMenuItem<Subject>(
                    value: subject,
                    child: Text(l10n.translateSubjectName(subject.name)),
                  ),
                )
                .toList(),
            onChanged: (subject) => setState(() {
              _subject = subject;
              _calculation = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Semester>(
            initialValue: _semester,
            decoration: InputDecoration(
                labelText: l10n.text('targetCalculator.period')),
            items: Semester.values
                .map(
                  (semester) => DropdownMenuItem<Semester>(
                    value: semester,
                    child: Text(l10n.semesterLabel(semester)),
                  ),
                )
                .toList(),
            onChanged: (semester) {
              if (semester == null) {
                return;
              }
              setState(() {
                _semester = semester;
                _calculation = null;
                _error = null;
              });
            },
          ),
          if (_subject != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.text('targetCalculator.currentGrades'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (grades.isEmpty)
                      Text(l10n.text('targetCalculator.noGrades'))
                    else ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final grade in grades)
                            Chip(
                              label: Text(
                                  '${formatGradeFromInt(grade.grade)} · ${grade.weightPercentage}%'),
                            ),
                        ],
                      ),
                    ],
                    if (_additionalExistingGrades.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final grade in _additionalExistingGrades)
                            InputChip(
                              label: Text(
                                  '${formatGradeFromInt(grade.grade)} · ${grade.weightPercentage}%'),
                              onDeleted: () => setState(() {
                                _additionalExistingGrades.remove(grade);
                                _calculation = null;
                                _error = null;
                              }),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addExistingGrade,
                      icon: const Icon(Icons.add),
                      label:
                          Text(l10n.text('targetCalculator.addExistingGrade')),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${l10n.text('targetCalculator.currentAverage')}: ${currentAverage == null ? '/' : _formatAverage(currentAverage)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            key: const Key('target-calculator-target'),
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.text('targetCalculator.target'),
              hintText: l10n.text('targetCalculator.targetHint'),
            ),
            onChanged: (_) => setState(() {
              _calculation = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.text('targetCalculator.futureGrades'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (calendarAssessments.isNotEmpty) ...[
                    Row(children: [
                      Expanded(
                        child: Text(
                          l10n.text('targetCalculator.calendarAssessments',
                              args: {
                                'count': calendarAssessments.length.toString(),
                              }),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        key: const Key('target-calculator-toggle-calendar'),
                        onPressed: () => setState(() {
                          _includeCalendarAssessments =
                              !_includeCalendarAssessments;
                          _calculation = null;
                          _error = null;
                        }),
                        child: Text(l10n.text(_includeCalendarAssessments
                            ? 'targetCalculator.ignoreCalendarAssessments'
                            : 'targetCalculator.useCalendarAssessments')),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(l10n.text('targetCalculator.calendarAssessmentsInfo'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (_includeCalendarAssessments)
                      for (final assessment in calendarAssessments)
                        ListTile(
                          key: Key(
                              'target-calculator-calendar-${assessment.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text(assessment.title),
                          subtitle: Text([
                            DateFormat('dd.MM.yyyy').format(assessment.date),
                            l10n.translateSubjectName(assessment.subject!),
                            if (assessment.type != null &&
                                assessment.type!.isNotEmpty)
                              assessment.type!,
                          ].join(' · ')),
                          trailing: const Text('100%'),
                        )
                    else
                      Text(
                          l10n.text(
                              'targetCalculator.calendarAssessmentsIgnored'),
                          style: Theme.of(context).textTheme.bodySmall),
                    const Divider(),
                  ],
                  Text(l10n.text('targetCalculator.additionalFutureGrades'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        key: const Key('target-calculator-remove-future'),
                        onPressed:
                            _weightControllers.length > _minimumFutureGrades
                                ? () => _changeFutureGradeCount(-1)
                                : null,
                        icon: const Icon(Icons.remove),
                        tooltip:
                            l10n.text('targetCalculator.removeFutureGrade'),
                      ),
                      Text(l10n.text('targetCalculator.futureGradeCount',
                          args: {
                            'count': _weightControllers.length.toString()
                          })),
                      IconButton(
                        key: const Key('target-calculator-add-future'),
                        onPressed:
                            _weightControllers.length < _maximumFutureGrades
                                ? () => _changeFutureGradeCount(1)
                                : null,
                        icon: const Icon(Icons.add),
                        tooltip: l10n.text('targetCalculator.addFutureGrade'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.text('targetCalculator.futureWeightInfo'),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (var index = 0;
                      index < _weightControllers.length;
                      index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        key: Key('target-calculator-weight-$index'),
                        controller: _weightControllers[index],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.text('targetCalculator.futureWeight',
                              args: {'count': (index + 1).toString()}),
                          suffixText: '%',
                        ),
                        onChanged: (_) => setState(() {
                          _calculation = null;
                          _error = null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            key: const Key('target-calculator-calculate'),
            onPressed: _calculate,
            icon: const Icon(Icons.calculate),
            label: Text(l10n.text('targetCalculator.calculate')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_calculation != null) ...[
            const SizedBox(height: 20),
            _ResultCard(
              calculation: _calculation!,
              futureWeights: _futureWeights,
              futureLabels: <String>[
                for (final assessment in _includedCalendarAssessments)
                  '${DateFormat('dd.MM.yyyy').format(assessment.date)} · ${assessment.title}',
                for (var index = 0; index < _weightControllers.length; index++)
                  l10n.text('targetCalculator.additionalFutureGrade',
                      args: {'count': (index + 1).toString()}),
              ],
              target: _targetController.text,
              formatAverage: _formatAverage,
              formatContribution: _formatContribution,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.calculation,
    required this.futureWeights,
    required this.futureLabels,
    required this.target,
    required this.formatAverage,
    required this.formatContribution,
  });

  final TargetGradeCalculation calculation;
  final List<int> futureWeights;
  final List<String> futureLabels;
  final String target;
  final String Function(double value) formatAverage;
  final String Function(int value) formatContribution;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasDifferentWeights = futureWeights.toSet().length > 1;
    final grades = List<Widget>.generate(
      calculation.suggestedGrades.length,
      (index) {
        final grade = formatGradeFromInt(calculation.suggestedGrades[index]);
        final weight = hasDifferentWeights ? ' (${futureWeights[index]}%)' : '';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.assignment_turned_in_outlined),
          title: Text(futureLabels[index]),
          subtitle:
              Text('${l10n.text('targetCalculator.requiredGrade')}$weight'),
          trailing: Text(grade, style: Theme.of(context).textTheme.titleMedium),
        );
      },
    );
    final isReachable = calculation.isReachable;
    return Card(
      color: isReachable ? null : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isReachable
                  ? l10n.text('targetCalculator.resultReached')
                  : l10n.text('targetCalculator.resultUnreachable',
                      args: {'target': target}),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
                '${l10n.text('targetCalculator.requiredContribution')}: ${formatContribution(calculation.requiredFutureScore < 0 ? 0 : calculation.requiredFutureScore)}'),
            const SizedBox(height: 8),
            Text(
              isReachable
                  ? l10n.text('targetCalculator.suggestedGrades')
                  : l10n.text('targetCalculator.bestGrades'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            ...grades,
            const SizedBox(height: 8),
            Text(
              isReachable
                  ? l10n.text('targetCalculator.resultAverage', args: {
                      'average': formatAverage(calculation.resultingAverage)
                    })
                  : l10n.text('targetCalculator.bestAverage', args: {
                      'average': formatAverage(calculation.resultingAverage)
                    }),
            ),
          ],
        ),
      ),
    );
  }
}
