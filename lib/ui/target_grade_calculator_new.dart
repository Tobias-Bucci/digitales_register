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

// The target grade calculator in the new design. It is a part of
// `target_grade_calculator.dart`, so that it runs on the same state and the
// same calculation as Legacy; only what is drawn differs.
part of 'target_grade_calculator.dart';

/// Asks for a grade that is not in the register yet, in a sheet of glass, with
/// the checks of the dialog of Legacy.
Future<TargetGradeEntry?> _showExistingGradeSheet(BuildContext context) =>
    showGlassSheet<TargetGradeEntry>(
      context: context,
      builder: (_) => const _ExistingGradePanel(),
    );

class _ExistingGradePanel extends StatefulWidget {
  const _ExistingGradePanel();

  @override
  State<_ExistingGradePanel> createState() => _ExistingGradePanelState();
}

class _ExistingGradePanelState extends State<_ExistingGradePanel> {
  final _gradeController = TextEditingController();
  final _weightController = TextEditingController(text: '100');
  String? _error;

  @override
  void dispose() {
    _gradeController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _add() {
    final grade = tryParseFormattedGrade(_gradeController.text);
    final weight = int.tryParse(_weightController.text);
    if (grade == null ||
        grade < minimumGrade ||
        grade > maximumGrade ||
        weight == null ||
        weight < 0) {
      setState(() =>
          _error = context.l10n.text('targetCalculator.error.invalidExisting'));
      return;
    }
    Navigator.pop(
      context,
      TargetGradeEntry(grade: grade, weightPercentage: weight),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        key: const Key('target-calculator-existing-panel'),
        title: l10n.text('targetCalculator.addExistingGrade'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('target-calculator-existing-grade'),
              controller: _gradeController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: glassFieldDecoration(
                context,
                labelText: l10n.text('gradeCalculator.grade'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('target-calculator-existing-weight'),
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: glassFieldDecoration(
                context,
                labelText: l10n.text('gradeCalculator.weight'),
                errorText: _error,
              ).copyWith(suffixText: '%'),
            ),
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.text('common.cancel')),
                ),
                FilledButton(
                  key: const Key('target-calculator-existing-confirm'),
                  onPressed: _add,
                  child: Text(l10n.text('targetCalculator.addExistingGrade')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The heading of a card of the page.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

/// The page of the target grade calculator in the new design, on the state of
/// Legacy.
class _NewTargetGradeCalculatorView extends StatelessWidget {
  const _NewTargetGradeCalculatorView({
    required this.state,
    required this.grades,
    required this.calendarAssessments,
    required this.includedCalendarAssessments,
    required this.calendarLimited,
    required this.currentAverage,
  });

  final _TargetGradeCalculatorPageState state;
  final List<GradeAll> grades;
  final List<ExamAssessment> calendarAssessments, includedCalendarAssessments;
  final bool calendarLimited;
  final double? currentAverage;

  static String _chipLabel(int grade, int weight) =>
      '${formatGradeFromInt(grade)} · $weight%';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    final format = GradesFormat.of(context);
    // Grades are colourful unless the switch was turned off, as on the grades
    // page of the new design.
    final colorGrades = !state.widget.state.settingsState.gradeColorsTurnedOff;
    final subject = state._subject;
    final calculation = state._calculation;
    final error = state._error;
    final width = MediaQuery.sizeOf(context).width;
    final shortSemester = width < tabletLayoutBreakpoint;

    String semesterShort(Semester semester) {
      if (!shortSemester) return l10n.semesterLabel(semester);
      if (semester == Semester.first) return '1';
      if (semester == Semester.second) return '2';
      return l10n.text('filter.all');
    }

    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    final periodLabel = Text(
      l10n.text('targetCalculator.period'),
      style: theme.textTheme.labelLarge?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    final periodControl = FittedBox(
      fit: BoxFit.scaleDown,
      child: GlassSegmentedControl<Semester>(
        key: const Key('target-calculator-period'),
        selected: state._semester,
        onChanged: state._selectSemester,
        segments: [
          for (final semester in Semester.values)
            GlassSegment(
              value: semester,
              label: semesterShort(semester),
              fullLabel: l10n.semesterLabel(semester),
            ),
        ],
      ),
    );

    return GlassPage(
      header: GlassPageHeader(
        surfaceKey: const Key('target-calculator-header'),
        title: l10n.text('targetCalculator.title'),
        floatingMaxWidth: glassHeaderFloatingWidth(width),
      ),
      body: GlassListBody(
        listKey: const Key('target-calculator-list'),
        children: [
          GlassCard(
            key: const Key('target-calculator-inputs'),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<Subject>(
                  key: const Key('target-calculator-subject'),
                  isExpanded: true,
                  initialValue: subject,
                  borderRadius: DesignTokens.cardBorderRadius,
                  decoration: glassFieldDecoration(
                    context,
                    labelText: l10n.text('targetCalculator.subject'),
                  ),
                  items: [
                    for (final subject in state._subjects)
                      DropdownMenuItem<Subject>(
                        value: subject,
                        child: Text(
                          l10n.translateSubjectName(subject.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: state._selectSubject,
                ),
                const SizedBox(height: 12),
                // Above 130 % the label goes above the switch.
                Flex(
                  direction: largeText ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: largeText
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (largeText)
                      periodLabel
                    else
                      Expanded(child: periodLabel),
                    const SizedBox(width: 8, height: 4),
                    if (largeText)
                      periodControl
                    else
                      Flexible(
                        flex: 3,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: periodControl,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('target-calculator-target'),
                  controller: state._targetController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: glassFieldDecoration(
                    context,
                    labelText: l10n.text('targetCalculator.target'),
                    hintText: l10n.text('targetCalculator.targetHint'),
                  ),
                  onChanged: (_) => state._invalidate(),
                ),
              ],
            ),
          ),
          if (subject != null) ...[
            const SizedBox(height: 8),
            GlassCard(
              key: const Key('target-calculator-current'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CardTitle(l10n.text('targetCalculator.currentGrades')),
                  const SizedBox(height: 8),
                  if (grades.isEmpty && state._additionalExistingGrades.isEmpty)
                    Text(l10n.text('targetCalculator.noGrades'), style: note)
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final grade in grades)
                          GlassChip(
                            icon: Icons.school_outlined,
                            label: _chipLabel(
                              grade.grade!,
                              grade.weightPercentage,
                            ),
                          ),
                        for (final grade in state._additionalExistingGrades)
                          InputChip(
                            label: Text(
                              _chipLabel(grade.grade, grade.weightPercentage),
                            ),
                            avatar: const Icon(Icons.edit_note_rounded),
                            shape: const StadiumBorder(),
                            mouseCursor: NewDesignTheme.clickCursor,
                            deleteButtonTooltipMessage:
                                l10n.text('button.delete'),
                            onDeleted: () => state._removeExistingGrade(grade),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      key: const Key('target-calculator-add-existing'),
                      style: glassControlStyle(scheme),
                      onPressed: state._addExistingGrade,
                      icon: const Icon(Icons.add, size: 20),
                      label:
                          Text(l10n.text('targetCalculator.addExistingGrade')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.text('targetCalculator.currentAverage'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GradeBadge(
                        key: const Key('target-calculator-current-average'),
                        text: format.average(currentAverage),
                        hundredths: currentAverage,
                        colorized: colorGrades,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          GlassCard(
            key: const Key('target-calculator-future'),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardTitle(l10n.text('targetCalculator.futureGrades')),
                const SizedBox(height: 8),
                if (calendarAssessments.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.text('targetCalculator.calendarAssessments',
                              args: {
                                'count': (calendarLimited
                                        ? includedCalendarAssessments.length
                                        : calendarAssessments.length)
                                    .toString(),
                              }),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('target-calculator-toggle-calendar'),
                        onPressed: state._toggleCalendarAssessments,
                        child: Text(l10n.text(state._includeCalendarAssessments
                            ? 'targetCalculator.ignoreCalendarAssessments'
                            : 'targetCalculator.useCalendarAssessments')),
                      ),
                    ],
                  ),
                  Text(
                    l10n.text('targetCalculator.calendarAssessmentsInfo'),
                    style: note,
                  ),
                  if (calendarLimited) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.text('targetCalculator.calendarAssessmentsLimited',
                          args: {
                            'used':
                                includedCalendarAssessments.length.toString(),
                            'total': calendarAssessments.length.toString(),
                            'max': maximumFutureAssessments.toString(),
                          }),
                      key: const Key('target-calculator-calendar-limited'),
                      style: note,
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (state._includeCalendarAssessments)
                    for (final assessment in includedCalendarAssessments)
                      _FutureRow(
                        key: Key('target-calculator-calendar-${assessment.id}'),
                        icon: Icons.event_note_outlined,
                        title: assessment.title,
                        subtitle: [
                          format.longDate(assessment.date),
                          l10n.translateSubjectName(assessment.subject!),
                          if (assessment.type != null &&
                              assessment.type!.isNotEmpty)
                            assessment.type!,
                        ].join(' · '),
                        trailing: Text(
                          format.weight(100),
                          style: theme.textTheme.labelLarge,
                        ),
                      )
                  else
                    Text(
                      l10n.text('targetCalculator.calendarAssessmentsIgnored'),
                      style: note,
                    ),
                  Divider(
                    height: 20,
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ],
                Text(
                  l10n.text('targetCalculator.additionalFutureGrades'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      key: const Key('target-calculator-remove-future'),
                      style: HeaderDiscButton.styleOf(scheme),
                      iconSize: HeaderDiscButton.iconSize,
                      onPressed: state._weightControllers.length >
                              _TargetGradeCalculatorPageState
                                  ._minimumFutureGrades
                          ? () => state._changeFutureGradeCount(-1)
                          : null,
                      icon: const Icon(Icons.remove),
                      tooltip: l10n.text('targetCalculator.removeFutureGrade'),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        l10n.text('targetCalculator.futureGradeCount', args: {
                          'count': state._weightControllers.length.toString()
                        }),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('target-calculator-add-future'),
                      style: HeaderDiscButton.styleOf(scheme),
                      iconSize: HeaderDiscButton.iconSize,
                      onPressed: state._weightControllers.length <
                              _TargetGradeCalculatorPageState
                                  ._maximumFutureGrades
                          ? () => state._changeFutureGradeCount(1)
                          : null,
                      icon: const Icon(Icons.add),
                      tooltip: l10n.text('targetCalculator.addFutureGrade'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.text('targetCalculator.futureWeightInfo'),
                  style: note,
                ),
                for (var index = 0;
                    index < state._weightControllers.length;
                    index++) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: Key('target-calculator-weight-$index'),
                    controller: state._weightControllers[index],
                    keyboardType: TextInputType.number,
                    decoration: glassFieldDecoration(
                      context,
                      labelText: l10n.text('targetCalculator.futureWeight',
                          args: {'count': (index + 1).toString()}),
                    ).copyWith(suffixText: '%'),
                    onChanged: (_) => state._invalidate(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('target-calculator-calculate'),
            onPressed: state._calculate,
            icon: const Icon(Icons.calculate),
            label: Text(l10n.text('targetCalculator.calculate')),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            GlassCard(
              key: const Key('target-calculator-error'),
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 20, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (calculation != null) ...[
            const SizedBox(height: 8),
            _NewResultCard(
              calculation: calculation,
              futureWeights: state._futureWeights,
              futureLabels: <String>[
                for (final assessment in includedCalendarAssessments)
                  '${format.longDate(assessment.date)} · ${assessment.title}',
                for (var index = 0;
                    index < state._weightControllers.length;
                    index++)
                  l10n.text('targetCalculator.additionalFutureGrade',
                      args: {'count': (index + 1).toString()}),
              ],
              target: state._targetController.text,
              colorGrades: colorGrades,
            ),
          ],
        ],
      ),
    );
  }
}

/// A future grade: what it is, and its weight or the grade it needs.
class _FutureRow extends StatelessWidget {
  const _FutureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title, subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// What the calculation found, in the style of the overview of the grades
/// page: whether the target is reachable, the grades it needs and the average
/// they lead to.
class _NewResultCard extends StatelessWidget {
  const _NewResultCard({
    required this.calculation,
    required this.futureWeights,
    required this.futureLabels,
    required this.target,
    required this.colorGrades,
  });

  final TargetGradeCalculation calculation;
  final List<int> futureWeights;
  final List<String> futureLabels;
  final String target;
  final bool colorGrades;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final reachable = calculation.isReachable;
    final hasDifferentWeights = futureWeights.toSet().length > 1;
    final average = format.average(calculation.resultingAverage);
    // In ten-thousandths, as Legacy shows it with two decimals.
    final contribution = format.average(
      (calculation.requiredFutureScore < 0
              ? 0
              : calculation.requiredFutureScore) /
          100,
    );
    return GlassCard(
      key: const Key('target-calculator-result'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  reachable
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 22,
                  color: reachable ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reachable
                        ? l10n.text('targetCalculator.resultReached')
                        : l10n.text('targetCalculator.resultUnreachable',
                            args: {'target': target}),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Semantics(
                  label: format.spoken(average, calculation.resultingAverage),
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: GradeBadge(
                      key: const Key('target-calculator-result-average'),
                      text: average,
                      hundredths: calculation.resultingAverage,
                      colorized: colorGrades,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            reachable
                ? l10n.text('targetCalculator.resultAverage',
                    args: {'average': average})
                : l10n.text('targetCalculator.bestAverage',
                    args: {'average': average}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.text('targetCalculator.requiredContribution')}: '
            '$contribution',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Divider(
            height: 20,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          _CardTitle(
            reachable
                ? l10n.text('targetCalculator.suggestedGrades')
                : l10n.text('targetCalculator.bestGrades'),
          ),
          for (var index = 0;
              index < calculation.suggestedGrades.length;
              index++)
            _FutureRow(
              icon: Icons.assignment_turned_in_outlined,
              title: futureLabels[index],
              subtitle: hasDifferentWeights
                  ? '${l10n.text('targetCalculator.requiredGrade')} '
                      '(${futureWeights[index]}%)'
                  : l10n.text('targetCalculator.requiredGrade'),
              trailing: GradeBadge(
                text: format.grade(
                  formatGradeFromInt(calculation.suggestedGrades[index]),
                ),
                hundredths: calculation.suggestedGrades[index],
                colorized: colorGrades,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
