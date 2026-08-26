import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/target_grade_calculation.dart';
import 'package:dr/ui/grade_calculator.dart' show tryParseFormattedGrade;
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class TargetGradeCalculator extends StatelessWidget {
  const TargetGradeCalculator({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, BuiltList<Subject>>(
      connect: (state) => state.gradesState.subjects,
      builder: (context, subjects, actions) => _TargetGradeCalculatorPage(
        subjects: subjects.toList(),
      ),
    );
  }
}

class _TargetGradeCalculatorPage extends StatefulWidget {
  const _TargetGradeCalculatorPage({required this.subjects});

  final List<Subject> subjects;

  @override
  State<_TargetGradeCalculatorPage> createState() =>
      _TargetGradeCalculatorPageState();
}

class _TargetGradeCalculatorPageState
    extends State<_TargetGradeCalculatorPage> {
  static const _minimumFutureGrades = 1;
  static const _maximumFutureGrades = 10;

  final _targetController = TextEditingController();
  final List<TextEditingController> _weightControllers =
      <TextEditingController>[
    TextEditingController(text: '100'),
    TextEditingController(text: '100'),
  ];
  Subject? _subject;
  Semester _semester = Semester.all;
  TargetGradeCalculation? _calculation;
  String? _error;

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

  List<TargetGradeEntry> get _calculationGrades => _grades
      .map(
        (grade) => TargetGradeEntry(
          grade: grade.grade!,
          weightPercentage: grade.weightPercentage,
        ),
      )
      .toList();

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
    final weights = _weightControllers
        .map((controller) => int.tryParse(controller.text))
        .toList();
    if (_subject == null) {
      setState(
          () => _error = l10n.text('targetCalculator.error.selectSubject'));
      return;
    }
    if (_grades.isEmpty) {
      setState(() => _error = l10n.text('targetCalculator.error.noGrades'));
      return;
    }
    if (target == null || target < minimumGrade || target > maximumGrade) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidTarget'));
      return;
    }
    if (_calculationGrades.any(
      (grade) => grade.grade < minimumGrade || grade.grade > maximumGrade,
    )) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidExisting'));
      return;
    }
    if (weights
        .any((weight) => weight == null || weight <= 0 || weight > 100)) {
      setState(
          () => _error = l10n.text('targetCalculator.error.invalidWeight'));
      return;
    }
    final calculation = calculateTargetGrades(
      existingGrades: _calculationGrades,
      targetGrade: target,
      futureWeights: weights.cast<int>(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grades = _grades;
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
            items: widget.subjects
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
                      const SizedBox(height: 12),
                      Text(
                        '${l10n.text('targetCalculator.currentAverage')}: ${currentAverage == null ? '/' : _formatAverage(currentAverage)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
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
              futureWeights: _weightControllers
                  .map((controller) => int.parse(controller.text))
                  .toList(),
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
    required this.target,
    required this.formatAverage,
    required this.formatContribution,
  });

  final TargetGradeCalculation calculation;
  final List<int> futureWeights;
  final String target;
  final String Function(double value) formatAverage;
  final String Function(int value) formatContribution;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasDifferentWeights = futureWeights.toSet().length > 1;
    final grades = List<String>.generate(
      calculation.suggestedGrades.length,
      (index) {
        final grade = formatGradeFromInt(calculation.suggestedGrades[index]);
        return hasDifferentWeights
            ? '$grade (${futureWeights[index]}%)'
            : grade;
      },
    ).join(' & ');
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
                '${isReachable ? l10n.text('targetCalculator.suggestedGrades') : l10n.text('targetCalculator.bestGrades')}: $grades'),
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
