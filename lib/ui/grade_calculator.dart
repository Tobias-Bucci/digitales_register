// Copyright (C) 2021 Michael Debertol
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

import 'package:built_collection/built_collection.dart';
import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_average.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/ui/profile_new.dart' show glassFieldDecoration;
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:tuple/tuple.dart';

part 'grade_calculator_new.dart';

bool isGradeInRange(int grade) {
  return grade >= 0 && grade <= 1000;
}

int? tryParseFormattedGrade(String grade) {
  bool matchesWholeInput(RegExpMatch? match) {
    return match != null && match.start == 0 && match.end == match.input.length;
  }

  final accurate = RegExp(r"(\d+)(?:[.,](\d{1,2}))?").firstMatch(grade);
  if (matchesWholeInput(accurate)) {
    final major = accurate!.group(1)!;
    final minor = accurate.group(2);
    final majorParsed = int.tryParse(major);
    if (majorParsed == null) {
      return null;
    }
    var minorParsed = minor != null ? int.tryParse(minor) : 0;
    if (minorParsed == null) {
      return null;
    }
    if (minor?.length == 1) {
      // parse .5 as 50/100
      minorParsed *= 10;
    }
    final combinedGrade = majorParsed * 100 + minorParsed;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final less = RegExp(r"(\d+)-").firstMatch(grade);
  if (matchesWholeInput(less)) {
    final lessParsed = int.tryParse(less!.group(1)!);
    if (lessParsed == null) {
      return null;
    }
    final combinedGrade = lessParsed * 100 - 25;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final more = RegExp(r"(\d+)\+").firstMatch(grade);
  if (matchesWholeInput(more)) {
    final moreParsed = int.tryParse(more!.group(1)!);
    if (moreParsed == null) {
      return null;
    }
    final combinedGrade = moreParsed * 100 + 25;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final between = RegExp(r"(\d+)[-/](\d+)").firstMatch(grade);
  if (matchesWholeInput(between)) {
    final startParsed = int.tryParse(between!.group(1)!);
    if (startParsed == null) {
      return null;
    }
    final endParsed = int.tryParse(between.group(2)!);
    if (endParsed == null) {
      return null;
    }
    if (endParsed != startParsed + 1) {
      return null;
    }
    final combinedGrade = startParsed * 100 + 50;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  return null;
}

String _calculateAverage(List<_Grade> grades) {
  var weights = 0;
  var sum = 0;
  for (final grade in grades) {
    weights += grade.weightPercentage;
    sum += grade.grade * grade.weightPercentage;
  }
  if (weights == 0) {
    return "/";
  }
  final average = roundedGradeAverage(sum, weights)!;
  return gradeAverageFormat.format(average / 100);
}

typedef _UpdateGrade = void Function(_Grade previous, _Grade? updated);

class GradeCalculator extends StatefulWidget {
  const GradeCalculator({super.key});
  @override
  _GradeCalculatorState createState() => _GradeCalculatorState();
}

class _Grade {
  int grade;
  int weightPercentage;
  String? description;

  _Grade({
    required this.grade,
    required this.weightPercentage,
    this.description,
  });
}

class _GradeCalculatorState extends State<GradeCalculator> {
  final List<_Grade> grades = [];

  void showTargetCalculator() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TargetGradeCalculator(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> addGrade() async {
    final Tuple2<int, int>? grade = ResponsiveNavigationScope.isActive(context)
        ? await _showNewGradeSheet(context)
        : await _showNewGradeDialog();
    if (grade != null && mounted) {
      setState(() {
        grades.add(_Grade(grade: grade.item1, weightPercentage: grade.item2));
      });
      await AnalyticsService.logCustomEvent('grade_calculator_added_grade');
    }
  }

  Future<Tuple2<int, int>?> _showNewGradeDialog() {
    return showDialog(
      context: context,
      builder: (context) {
        int? grade;
        int? weight;
        return StatefulBuilder(
          builder: (context, setState) => InfoDialog(
            title: Text(context.t('gradeCalculator.newGrade')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Input(
                  autofocus: true,
                  showErrorForEmptyInput: false,
                  inputType: _InputType.grade,
                  updateValue: (value) {
                    setState(() {
                      grade = value;
                    });
                  },
                ),
                _Input(
                  showErrorForEmptyInput: false,
                  inputType: _InputType.weight,
                  updateValue: (value) {
                    setState(() {
                      weight = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(context.t('common.cancel')),
              ),
              ElevatedButton(
                onPressed: grade != null && weight != null
                    ? () {
                        Navigator.pop(context, Tuple2(grade!, weight!));
                      }
                    : null,
                child: Text(context.t('gradeCalculator.add')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> importGrades() async {
    final List<_Grade>? result = ResponsiveNavigationScope.isActive(context)
        // A sheet of glass in the new design.
        ? await showGlassSheet<List<_Grade>>(
            context: context,
            builder: (_) => const _ImportGradesContainer(newDesign: true),
          )
        : await Navigator.of(
            context,
            rootNavigator: true,
          ).push(
            MaterialPageRoute(
              builder: (context) => const _ImportGradesContainer(),
              fullscreenDialog: true,
            ),
          );
    if (result == null || !mounted) {
      return;
    }
    assert(grades.isEmpty);
    assert(result.isNotEmpty);
    setState(() {
      grades.addAll(result);
    });
    await AnalyticsService.logCustomEvent(
        'grade_calculator_imported_grades', {'count': result.length});
  }

  void updateGrade(_Grade previous, _Grade? updated) {
    if (!mounted) return;
    setState(() {
      if (updated == null) {
        grades.remove(previous);
      } else {
        assert(grades.contains(previous));
        previous.description = updated.description;
        previous.grade = updated.grade;
        previous.weightPercentage = updated.weightPercentage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Inside the shell of the new design; Legacy and the root route keep the
    // page as it was.
    if (ResponsiveNavigationScope.isActive(context)) {
      return _NewGradeCalculatorView(state: this);
    }
    final showGreeting = grades.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('gradeCalculator.title')),
        actions: [
          IconButton(
            onPressed: showTargetCalculator,
            icon: const Icon(Icons.track_changes),
            tooltip: context.t('targetCalculator.open'),
          ),
        ],
      ),
      body: AnimatedCrossFade(
        firstChild: Greeting(
          import: importGrades,
          add: addGrade,
          showTargetCalculator: showTargetCalculator,
        ),
        secondChild: GradesList(
          grades: grades,
          updateGrade: updateGrade,
          addGrade: addGrade,
        ),
        crossFadeState:
            showGreeting ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 250),
      ),
      floatingActionButton: showGreeting
          ? null
          : FloatingActionButton.extended(
              onPressed: addGrade,
              label: Text(context.t('gradeCalculator.addGrade')),
              icon: const Icon(Icons.add),
            ),
    );
  }
}

@visibleForTesting
class GradesList extends StatelessWidget {
  final List<_Grade> grades;
  final _UpdateGrade updateGrade;
  final VoidCallback addGrade;

  const GradesList(
      {super.key,
      required this.grades,
      required this.updateGrade,
      required this.addGrade});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 2,
          child: ListTile(
            title: Text(context.t('gradeCalculator.average')),
            subtitle: Text(context.l10n.gradeCountLabel(grades.length)),
            trailing: Text(_calculateAverage(grades)),
          ),
        ),
        if (grades.isNotEmpty)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8).copyWith(bottom: 160),
              children: [
                for (final grade in grades)
                  GradeTile(
                    key: ObjectKey(grade),
                    grade: grade,
                    updateGrade: updateGrade,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

@visibleForTesting
class GradeTile extends StatelessWidget {
  final _Grade grade;
  final _UpdateGrade updateGrade;

  const GradeTile({super.key, required this.grade, required this.updateGrade});

  @override
  Widget build(BuildContext context) {
    return DeleteableTile(
      onDeleted: () {
        updateGrade(grade, null);
      },
      icon: const Icon(Icons.close),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 100,
                    child: _Input(
                      initial: grade.weightPercentage.toString(),
                      inputType: _InputType.weight,
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
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _Input(
                      initial: formatGradeFromInt(grade.grade),
                      inputType: _InputType.grade,
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
                    ),
                  ),
                ),
              ],
            ),
            if (grade.description != null)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  grade.description!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
class Greeting extends StatelessWidget {
  final VoidCallback import, add, showTargetCalculator;

  const Greeting({
    super.key,
    required this.import,
    required this.add,
    required this.showTargetCalculator,
  });
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              context.t('gradeCalculator.greeting'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: import,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.save_alt),
                    const SizedBox(width: 8),
                    Text(context.t('gradeCalculator.importGrades')),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: add,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add),
                    const SizedBox(width: 8),
                    Text(context.t('gradeCalculator.addGrade')),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: showTargetCalculator,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.track_changes),
                    const SizedBox(width: 8),
                    Text(context.t('targetCalculator.open')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportGrades extends StatefulWidget {
  final List<Subject> subjects;

  /// Shown in a sheet of the new design.
  final bool newDesign;

  const _ImportGrades({required this.subjects, this.newDesign = false});
  @override
  _ImportGradesState createState() => _ImportGradesState();
}

class _ImportGradesContainer extends StatelessWidget {
  const _ImportGradesContainer({this.newDesign = false});

  final bool newDesign;

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, BuiltList<Subject>>(
      connect: (state) => state.gradesState.subjects,
      builder: (context, state, actions) => _ImportGrades(
        subjects: state.toList(),
        newDesign: newDesign,
      ),
    );
  }
}

class _ImportGradesState extends State<_ImportGrades> {
  Subject? selectedSubject;
  Semester? selectedSemester;
  List<_Grade>? grades;

  /// Uncancelled entries that were left out because they have no numeric
  /// value (the backend may report unknown or non-numeric grades).
  int skippedGrades = 0;

  @override
  void didUpdateWidget(_ImportGrades oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = selectedSubject;
    if (selected == null) return;
    // The subject list may be refreshed while this page is open; keep the
    // selection pointing at the current instance (or drop it if the subject
    // disappeared) so the dropdown value always matches one of its items.
    selectedSubject = widget.subjects
        .where((s) => selected.id != null
            ? s.id == selected.id
            : equalsIgnoreCase(s.name, selected.name))
        .firstOrNull;
    _computeGrades();
  }

  void _recalculateGrades() {
    setState(_computeGrades);
  }

  /// For the sheet of the new design, as the dropdown of Legacy does it.
  void _selectSubject(Subject? subject) {
    setState(() {
      selectedSubject = subject;
    });
    _recalculateGrades();
  }

  /// For the sheet of the new design, as the radio buttons of Legacy do it.
  void _selectSemester(Semester? semester) {
    setState(() {
      selectedSemester = semester;
    });
    _recalculateGrades();
  }

  bool get _canImport =>
      selectedSemester != null && selectedSubject != null && grades!.isNotEmpty;

  void _computeGrades() {
    final subject = selectedSubject;
    final semester = selectedSemester;
    if (subject == null || semester == null) {
      grades = [];
      skippedGrades = 0;
      return;
    }
    // Invalid negative weights are left out as in every other average.
    final uncancelled = subject
            .basicGrades(semester)
            ?.where((e) => !e.cancelled && e.weightPercentage >= 0)
            .toList() ??
        const <GradeAll>[];
    grades = [
      for (final e in uncancelled)
        if (e.grade case final grade?)
          _Grade(
            grade: grade,
            weightPercentage: e.weightPercentage,
            description:
                "${context.l10n.translateSubjectName(subject.name)} · ${context.l10n.translateSchoolTerm(e.type)}",
          ),
    ];
    skippedGrades = uncancelled.length - grades!.length;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.newDesign) return _NewImportPanel(state: this);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('gradeCalculator.importTitle')),
      ),
      body: Column(
        children: [
          DropdownButton<Subject>(
            isExpanded: true,
            items: [
              for (final subject in widget.subjects)
                DropdownMenuItem(
                  value: subject,
                  child: Text(
                    context.l10n.translateSubjectName(subject.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            value: selectedSubject,
            hint: Text(context.t('gradeCalculator.selectSubject')),
            onChanged: (subject) {
              setState(() {
                selectedSubject = subject;
              });
              _recalculateGrades();
            },
          ),
          const SizedBox(
            height: 16,
          ),
          RadioGroup<Semester>(
            groupValue: selectedSemester,
            onChanged: (value) {
              setState(() {
                selectedSemester = value;
              });
              _recalculateGrades();
            },
            child: Column(
              children: [
                // ignore: prefer_const_constructors
                RadioListTile<Semester>(
                  title: Text(context.l10n.semesterLabel(Semester.first)),
                  value: Semester.first,
                ),
                // ignore: prefer_const_constructors
                RadioListTile<Semester>(
                  title: Text(context.l10n.semesterLabel(Semester.second)),
                  value: Semester.second,
                ),
                // ignore: prefer_const_constructors
                RadioListTile<Semester>(
                  title: Text(context.l10n.semesterLabel(Semester.all)),
                  value: Semester.all,
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Center(
            child: ElevatedButton(
              onPressed: selectedSemester != null &&
                      selectedSubject != null &&
                      grades!.isNotEmpty
                  ? () {
                      Navigator.pop(context, grades);
                    }
                  : null,
              child: Text(context.t('gradeCalculator.import')),
            ),
          ),
          if (skippedGrades > 0)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(context.l10n.skippedGradesLabel(skippedGrades)),
            ),
          if (selectedSemester != null &&
              selectedSubject != null &&
              grades!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                context.t('gradeCalculator.noGradesAvailable'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

enum _InputType { grade, weight }

class _Input extends StatefulWidget {
  final _InputType inputType;
  final String? initial;
  final void Function(int?) updateValue;
  final bool showErrorForEmptyInput;
  final bool autofocus;

  /// The field of the new design, on a card of glass.
  final bool newDesign;

  const _Input({
    super.key,
    required this.inputType,
    this.initial,
    required this.updateValue,
    this.showErrorForEmptyInput = true,
    this.autofocus = false,
    this.newDesign = false,
  });
  @override
  _InputState createState() => _InputState();
}

class _InputState extends State<_Input> {
  late final TextEditingController controller;
  final focusNode = FocusNode();

  int? getValue() {
    final value = controller.text;
    switch (widget.inputType) {
      case _InputType.grade:
        return tryParseFormattedGrade(value);
      case _InputType.weight:
        final percentage = int.tryParse(value);
        if (percentage != null && percentage >= 0 && percentage <= 100) {
          return percentage;
        } else {
          return null;
        }
    }
  }

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
    focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  bool isValid() => getValue() != null;

  @override
  Widget build(BuildContext context) {
    final errorText = isValid() ||
            (!widget.showErrorForEmptyInput && controller.text.isEmpty) ||
            focusNode.hasFocus
        ? null
        : context.t('gradeCalculator.invalidValue');
    final labelText = widget.inputType == _InputType.grade
        ? context.t('gradeCalculator.grade')
        : context.t('gradeCalculator.weight');
    final suffixText = widget.inputType == _InputType.weight ? "%" : null;
    return TextField(
      autofocus: widget.autofocus,
      keyboardType:
          widget.inputType == _InputType.weight ? TextInputType.number : null,
      focusNode: focusNode,
      controller: controller,
      decoration: widget.newDesign
          ? glassFieldDecoration(
              context,
              labelText: labelText,
              errorText: errorText,
            ).copyWith(suffixText: suffixText)
          : InputDecoration(
              errorText: errorText,
              labelText: labelText,
              suffixText: suffixText,
            ),
      onChanged: (_) {
        widget.updateValue(getValue());
        setState(() {
          // will show an error after checking the controller
        });
      },
    );
  }
}
