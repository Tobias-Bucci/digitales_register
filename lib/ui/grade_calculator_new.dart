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

// The grade calculator in the new design. It is a part of
// `grade_calculator.dart`, so that it shares the grades, the inputs and their
// checks with Legacy; only what is drawn differs.
part of 'grade_calculator.dart';

/// The weighted average of [grades] in hundredths, rounded as everywhere else,
/// or null without any weight. The same as `_calculateAverage`, as a number.
int? _averageHundredths(List<_Grade> grades) {
  var weights = 0;
  var sum = 0;
  for (final grade in grades) {
    weights += grade.weightPercentage;
    sum += grade.grade * grade.weightPercentage;
  }
  return roundedGradeAverage(sum, weights);
}

/// Asks for a new grade in a sheet of glass: the fields and checks of the
/// dialog of Legacy.
Future<Tuple2<int, int>?> _showNewGradeSheet(BuildContext context) =>
    showGlassSheet<Tuple2<int, int>>(
      context: context,
      builder: (_) => const _NewGradePanel(),
    );

class _NewGradePanel extends StatefulWidget {
  const _NewGradePanel();

  @override
  State<_NewGradePanel> createState() => _NewGradePanelState();
}

class _NewGradePanelState extends State<_NewGradePanel> {
  int? grade, weight;

  @override
  Widget build(BuildContext context) {
    final grade = this.grade, weight = this.weight;
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassPanel(
        key: const Key('grade-calculator-add-panel'),
        title: context.t('gradeCalculator.newGrade'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Input(
              key: const Key('grade-calculator-add-grade'),
              autofocus: true,
              showErrorForEmptyInput: false,
              inputType: _InputType.grade,
              newDesign: true,
              updateValue: (value) => setState(() => this.grade = value),
            ),
            const SizedBox(height: 12),
            _Input(
              key: const Key('grade-calculator-add-weight'),
              showErrorForEmptyInput: false,
              inputType: _InputType.weight,
              newDesign: true,
              updateValue: (value) => setState(() => this.weight = value),
            ),
            const SizedBox(height: 16),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.t('common.cancel')),
                ),
                FilledButton(
                  key: const Key('grade-calculator-add-confirm'),
                  onPressed: grade != null && weight != null
                      ? () => Navigator.pop(context, Tuple2(grade, weight))
                      : null,
                  child: Text(context.t('gradeCalculator.add')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The page of the grade calculator in the new design, on the state of
/// [GradeCalculator].
class _NewGradeCalculatorView extends StatelessWidget {
  const _NewGradeCalculatorView({required this.state});

  final _GradeCalculatorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grades = state.grades;
    final width = MediaQuery.sizeOf(context).width;
    return StoreConnection<AppState, AppActions, bool>(
      // Grades are colourful unless the switch was turned off, as on the
      // grades page of the new design.
      connect: (state) => !state.settingsState.gradeColorsTurnedOff,
      builder: (context, colorGrades, actions) => GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('grade-calculator-header'),
          title: l10n.text('gradeCalculator.title'),
          floatingMaxWidth: glassHeaderFloatingWidth(
            width,
            twoColumns: grades.isNotEmpty,
          ),
          actions: [
            HeaderDiscButton(
              key: const Key('grade-calculator-target'),
              tooltip: l10n.text('targetCalculator.open'),
              icon: Icons.track_changes,
              onPressed: state.showTargetCalculator,
            ),
          ],
        ),
        body: grades.isEmpty
            ? GlassStateCard(
                key: const Key('grade-calculator-welcome'),
                icon: Icons.calculate_outlined,
                title: l10n.text('gradeCalculator.title'),
                // One sentence, wrapped where the card wants it.
                body: l10n.text('gradeCalculator.greeting').replaceAll(
                      '\n',
                      ' ',
                    ),
                actionLabel: l10n.text('gradeCalculator.addGrade'),
                actionIcon: Icons.add,
                onAction: state.addGrade,
                secondaryActions: [
                  TextButton.icon(
                    key: const Key('grade-calculator-import'),
                    onPressed: state.importGrades,
                    icon: const Icon(Icons.save_alt),
                    label: Text(l10n.text('gradeCalculator.importGrades')),
                  ),
                  TextButton.icon(
                    key: const Key('grade-calculator-open-target'),
                    onPressed: state.showTargetCalculator,
                    icon: const Icon(Icons.track_changes),
                    label: Text(l10n.text('targetCalculator.open')),
                  ),
                ],
              )
            : GlassColumnsBody(
                listKey: const Key('grade-calculator-list'),
                side: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResultCard(
                    grades: grades,
                    colorGrades: colorGrades,
                    onAdd: state.addGrade,
                  ),
                ),
                main: _GradeRows(
                  grades: grades,
                  updateGrade: state.updateGrade,
                ),
              ),
      ),
    );
  }
}

/// The average of the grades, large and coloured like on the grades page, and
/// the way to add one more.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.grades,
    required this.colorGrades,
    required this.onAdd,
  });

  final List<_Grade> grades;
  final bool colorGrades;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final hundredths = _averageHundredths(grades);
    final text = format.average(hundredths);
    final label = l10n.text('gradeCalculator.average');
    final count = l10n.gradeCountLabel(grades.length);
    return GlassCard(
      key: const Key('grade-calculator-result'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '$label, ${format.spoken(text, hundredths)}, $count',
            liveRegion: true,
            container: true,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // With very large text, the number gets smaller instead of
                // breaking the card.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    child: GradeBadge(
                      key: ValueKey(text),
                      text: text,
                      hundredths: hundredths,
                      colorized: colorGrades,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count,
                  key: const Key('grade-calculator-count'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('grade-calculator-add'),
            style: glassControlStyle(scheme),
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 20),
            label: Text(l10n.text('gradeCalculator.addGrade')),
          ),
        ],
      ),
    );
  }
}

/// The grades of the calculator as rows of one card. Weight and grade stay
/// fields that change the average as they are typed, as in Legacy.
class _GradeRows extends StatelessWidget {
  const _GradeRows({required this.grades, required this.updateGrade});

  final List<_Grade> grades;
  final _UpdateGrade updateGrade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      key: const Key('grade-calculator-grades'),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < grades.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                endIndent: 8,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            _GradeRow(
              key: ObjectKey(grades[index]),
              grade: grades[index],
              updateGrade: updateGrade,
            ),
          ],
        ],
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({super.key, required this.grade, required this.updateGrade});

  final _Grade grade;
  final _UpdateGrade updateGrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = grade.description;
    // Above 130 % the two fields no longer fit side by side on a phone.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    final weight = _Input(
      initial: grade.weightPercentage.toString(),
      inputType: _InputType.weight,
      newDesign: true,
      updateValue: (value) {
        if (value != null) {
          updateGrade(
            grade,
            _Grade(
              grade: grade.grade,
              weightPercentage: value,
              // show no description
            ),
          );
        }
      },
    );
    final value = _Input(
      initial: formatGradeFromInt(grade.grade),
      inputType: _InputType.grade,
      newDesign: true,
      updateValue: (value) {
        if (value != null) {
          updateGrade(
            grade,
            _Grade(
              grade: value,
              weightPercentage: grade.weightPercentage,
              // show no description anymore
            ),
          );
        }
      },
    );
    final remove = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: IconButton(
        key: const Key('grade-calculator-remove'),
        tooltip: context.t('button.delete'),
        onPressed: () => updateGrade(grade, null),
        icon: const Icon(Icons.close_rounded),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6, right: 8),
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (stacked)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [weight, const SizedBox(height: 8), value],
                  ),
                ),
                remove,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A weight has three digits; wide windows give the rest to
                // the grade.
                Flexible(
                  flex: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: weight,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: value),
                remove,
              ],
            ),
        ],
      ),
    );
  }
}

/// The import of the grades of a subject, in a sheet of glass.
class _NewImportPanel extends StatelessWidget {
  const _NewImportPanel({required this.state});

  final _ImportGradesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedSemester = state.selectedSemester;
    final note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    return GlassPanel(
      key: const Key('grade-calculator-import-panel'),
      title: l10n.text('gradeCalculator.importTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: glassFieldDecoration(context).copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Subject>(
                key: const Key('grade-calculator-import-subject'),
                isExpanded: true,
                borderRadius: DesignTokens.cardBorderRadius,
                items: [
                  for (final subject in state.widget.subjects)
                    DropdownMenuItem(
                      value: subject,
                      child: Text(
                        l10n.translateSubjectName(subject.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                value: state.selectedSubject,
                hint: Text(l10n.text('gradeCalculator.selectSubject')),
                onChanged: state._selectSubject,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GlassSegmentedControl<Semester?>(
                key: const Key('grade-calculator-import-semester'),
                selected: selectedSemester,
                onChanged: state._selectSemester,
                segments: [
                  for (final semester in Semester.values)
                    GlassSegment(
                      value: semester,
                      label: l10n.semesterLabel(semester),
                      fullLabel: l10n.semesterLabel(semester),
                    ),
                ],
              ),
            ),
          ),
          if (state.skippedGrades > 0) ...[
            const SizedBox(height: 8),
            Text(l10n.skippedGradesLabel(state.skippedGrades), style: note),
          ],
          if (selectedSemester != null &&
              state.selectedSubject != null &&
              state.grades!.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.text('gradeCalculator.noGradesAvailable'),
              style: note?.copyWith(color: scheme.error),
            ),
          ],
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
              FilledButton.icon(
                key: const Key('grade-calculator-import-confirm'),
                onPressed: state._canImport
                    ? () => Navigator.pop(context, state.grades)
                    : null,
                icon: const Icon(Icons.save_alt, size: 20),
                label: Text(l10n.text('gradeCalculator.import')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
