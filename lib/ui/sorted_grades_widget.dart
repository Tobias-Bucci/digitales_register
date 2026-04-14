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

import 'package:dr/app_state.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef ViewSubjectDetailCallback = void Function(Subject s);
typedef SetBoolCallback = void Function(bool byType);

bool _isFailingGrade(int? grade) => grade != null && grade < 600;
bool _isPassingGrade(int? grade) => grade != null && grade >= 600;

TextStyle? _cancelledStyle(TextStyle? baseStyle, bool cancelled) {
  if (!cancelled) {
    return baseStyle;
  }
  return baseStyle?.copyWith(decoration: TextDecoration.lineThrough) ??
      const TextStyle(decoration: TextDecoration.lineThrough);
}

TextStyle? _gradeTextStyle(
  BuildContext context,
  TextStyle? baseStyle, {
  required bool cancelled,
  required bool failing,
  required bool passing,
  required bool colorized,
}) {
  final style = _cancelledStyle(baseStyle, cancelled);
  if (!colorized || (!failing && !passing)) {
    return style;
  }
  final foreground = failing
      ? Theme.of(context).colorScheme.onErrorContainer
      : Colors.green.shade900;
  return style?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ) ??
      TextStyle(
        color: foreground,
        fontWeight: FontWeight.w700,
        decoration:
            cancelled ? TextDecoration.lineThrough : TextDecoration.none,
      );
}

class _GradeBadge extends StatelessWidget {
  const _GradeBadge({
    required this.text,
    required this.textStyle,
    required this.failing,
    required this.passing,
    required this.colorized,
  });

  final String text;
  final TextStyle? textStyle;
  final bool failing;
  final bool passing;
  final bool colorized;

  @override
  Widget build(BuildContext context) {
    final content = Text(text, style: textStyle);
    if (!colorized || (!failing && !passing)) {
      return content;
    }

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: failing
            ? Theme.of(context).colorScheme.errorContainer
            : Colors.green.shade100,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: content,
      ),
    );
  }
}

class SortedGradesWidget extends StatefulWidget {
  final SortedGradesViewModel vm;
  final ViewSubjectDetailCallback viewSubjectDetail;
  final SetBoolCallback sortByTypeCallback;
  final SetBoolCallback showCancelledCallback;
  final SetBoolCallback colorGradesCallback;
  final VoidCallback showGradeCalculator;

  const SortedGradesWidget({
    super.key,
    required this.vm,
    required this.viewSubjectDetail,
    required this.sortByTypeCallback,
    required this.showCancelledCallback,
    required this.colorGradesCallback,
    required this.showGradeCalculator,
  });

  @override
  State<SortedGradesWidget> createState() => _SortedGradesWidgetState();
}

class _SortedGradesWidgetState extends State<SortedGradesWidget> {
  String? _favoriteSubject;
  String? _expandedSubjectKey;

  String _subjectExpansionKey(Subject subject) =>
      subject.id?.toString() ?? subject.name.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final availableFavoriteSubjects = filterAvailableFavoriteSubjects(
      widget.vm.favoriteSubjects,
      widget.vm.subjects.map((subject) => subject.name),
    );
    final selectedFavoriteSubject = _favoriteSubject == null
        ? null
        : findSubjectIgnoreCase(availableFavoriteSubjects, _favoriteSubject!);
    final visibleSubjects = selectedFavoriteSubject == null
        ? widget.vm.subjects
        : widget.vm.subjects
            .where(
              (subject) =>
                  matchesFavoriteSubject(subject.name, selectedFavoriteSubject),
            )
            .toList();

    return Column(
      key: ValueKey(widget.vm.semester),
      children: <Widget>[
        if (availableFavoriteSubjects.isNotEmpty)
          FavoriteSubjectFilter(
            subjects: availableFavoriteSubjects,
            selectedSubject: selectedFavoriteSubject,
            onSelected: (favoriteSubject) {
              setState(() {
                _favoriteSubject = favoriteSubject;
              });
            },
            subjectThemes: widget.vm.subjectThemes,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          ),
        SwitchListTile.adaptive(
          title: Text(context.t('grades.sortByType')),
          onChanged: widget.sortByTypeCallback,
          value: widget.vm.sortByType,
        ),
        SwitchListTile.adaptive(
          title: Text(context.t('grades.showDeleted')),
          onChanged: widget.showCancelledCallback,
          value: widget.vm.showCancelled!,
        ),
        SwitchListTile.adaptive(
          title: Text(context.t('grades.colorGrades')),
          onChanged: widget.colorGradesCallback,
          value: widget.vm.colorGrades,
        ),
        const Divider(
          height: 0,
        ),
        for (final s in visibleSubjects)
          SubjectWidget(
            key: ValueKey(_subjectExpansionKey(s)),
            subject: s,
            sortByType: widget.vm.sortByType,
            viewSubjectDetail: () => widget.viewSubjectDetail(s),
            showCancelled: widget.vm.showCancelled!,
            semester: widget.vm.semester,
            noInternet: widget.vm.noInternet,
            ignoredForAverage: widget.vm.ignoredSubjectsForAverage.any(
              (element) => element.toLowerCase() == s.name.toLowerCase(),
            ),
            colorGrades: widget.vm.colorGrades,
            expanded: _expandedSubjectKey == _subjectExpansionKey(s),
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedSubjectKey = _subjectExpansionKey(s);
                } else if (_expandedSubjectKey == _subjectExpansionKey(s)) {
                  _expandedSubjectKey = null;
                }
              });
            },
          ),
        if (widget.vm.subjects.any(
          (s) => widget.vm.ignoredSubjectsForAverage.any(
            (element) => element.toLowerCase() == s.name.toLowerCase(),
          ),
        ))
          ListTile(
            title: Text(
              context.t('grades.excludedAverageInfo'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ListTile(
            title: Row(
              children: [
                Text(context.t('grades.calculator')),
              ],
            ),
            subtitle: Text(context.t('grades.calculator.subtitle')),
            onTap: widget.showGradeCalculator,
          ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant SortedGradesWidget oldWidget) {
    if (oldWidget.vm.semester != widget.vm.semester) {
      _expandedSubjectKey = null;
    }
    if (_favoriteSubject != null &&
        findSubjectIgnoreCase(
              filterAvailableFavoriteSubjects(
                widget.vm.favoriteSubjects,
                widget.vm.subjects.map((subject) => subject.name),
              ),
              _favoriteSubject!,
            ) ==
            null) {
      _favoriteSubject = null;
    }
    final visibleSubjects = (_favoriteSubject == null
            ? widget.vm.subjects
            : widget.vm.subjects.where(
                (subject) =>
                    matchesFavoriteSubject(subject.name, _favoriteSubject!),
              ))
        .toList();
    if (_expandedSubjectKey != null &&
        !visibleSubjects.any((subject) =>
            _subjectExpansionKey(subject) == _expandedSubjectKey)) {
      _expandedSubjectKey = null;
    }
    super.didUpdateWidget(oldWidget);
  }
}

class SubjectWidget extends StatefulWidget {
  final bool sortByType;
  final bool showCancelled;
  final bool noInternet;
  final bool ignoredForAverage;
  final bool colorGrades;
  final Subject subject;
  final Semester semester;
  final VoidCallback viewSubjectDetail;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;

  const SubjectWidget(
      {super.key,
      required this.sortByType,
      required this.subject,
      required this.viewSubjectDetail,
      required this.showCancelled,
      required this.semester,
      required this.noInternet,
      required this.ignoredForAverage,
      required this.colorGrades,
      required this.expanded,
      required this.onExpansionChanged});

  @override
  _SubjectWidgetState createState() => _SubjectWidgetState();
}

class _SubjectWidgetState extends State<SubjectWidget> {
  late final ExpansibleController _controller;

  bool get closed => !widget.expanded;

  @override
  void initState() {
    super.initState();
    _controller = ExpansibleController();
  }

  @override
  void didUpdateWidget(SubjectWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) {
      return;
    }
    if (widget.expanded) {
      _controller.expand();
    } else {
      _controller.collapse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget? _lastFetchedMessage() {
    if (closed || !widget.noInternet) {
      return null;
    }
    final formatted = formatTimeAgoPerSemester(
      localizations: context.l10n,
      noInternet: widget.noInternet,
      lastFetched: widget.subject.lastFetchedDetailed,
      semester: widget.semester,
    );
    if (formatted == null) {
      return null;
    }
    return Text(
      "$formatted.",
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.subject.detailEntries(widget.semester);
    final averageStyle = Theme.of(context).textTheme.titleMedium;
    final average = widget.subject.average(widget.semester);
    final failingAverage = _isFailingGrade(average);
    final passingAverage = _isPassingGrade(average);
    return AbsorbPointer(
      absorbing: widget.noInternet && entries == null,
      child: ExpansionTile(
        controller: _controller,
        initiallyExpanded: widget.expanded,
        maintainState: true,
        title: Text.rich(
          TextSpan(
            text: context.l10n.translateSubjectName(widget.subject.name),
            children: [
              if (widget.ignoredForAverage)
                const TextSpan(
                  text: " *",
                  style: TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ),
        subtitle: _lastFetchedMessage(),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ø ', style: averageStyle),
            _GradeBadge(
              text: widget.subject.averageFormatted(widget.semester),
              failing: failingAverage,
              passing: passingAverage,
              colorized: widget.colorGrades,
              textStyle: _gradeTextStyle(
                context,
                averageStyle,
                cancelled: false,
                failing: failingAverage,
                passing: passingAverage,
                colorized: widget.colorGrades,
              ),
            ),
          ],
        ),
        trailing:
            widget.noInternet && entries == null ? const SizedBox() : null,
        onExpansionChanged: (expansion) {
          if (expansion) {
            logPerformanceEvent(
              "grades_subject_expanded",
              <String, Object?>{
                "subjectId": widget.subject.id,
                "semester": widget.semester.name,
              },
            );
            widget.viewSubjectDetail();
          }
          widget.onExpansionChanged(expansion);
        },
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeIn,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (currentChild != null) currentChild,
                    for (final child in previousChildren)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: child,
                      ),
                  ],
                );
              },
              duration: const Duration(milliseconds: 200),
              child: entries != null
                  ? Column(
                      key: ValueKey(
                        "${widget.subject.id}-${widget.semester.name}-${widget.sortByType}-${widget.showCancelled}-${entries.length}",
                      ),
                      children: [
                        if (widget.sortByType)
                          ...widget.subject
                              .detailEntriesByType(widget.semester)
                              .entries
                              .map(
                                (entry) => GradeTypeWidget(
                                  typeName: entry.key,
                                  colorGrades: widget.colorGrades,
                                  entries: entry.value
                                      .where((g) =>
                                          widget.showCancelled || !g.cancelled)
                                      .toList(),
                                ),
                              )
                        else
                          ...entries
                              .where(
                                  (g) => widget.showCancelled || !g.cancelled)
                              .map(
                                (g) => g is GradeDetail
                                    ? GradeWidget(
                                        grade: g,
                                        colorGrades: widget.colorGrades,
                                      )
                                    : ObservationWidget(
                                        observation: g as Observation,
                                      ),
                              )
                      ],
                    )
                  : AnimatedLinearProgressIndicator(show: !widget.noInternet),
            ),
          ),
        ],
      ),
    );
  }
}

class GradeWidget extends StatelessWidget {
  final GradeDetail grade;
  final bool colorGrades;

  const GradeWidget({
    super.key,
    required this.grade,
    this.colorGrades = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final failing = _isFailingGrade(grade.grade);
    final passing = _isPassingGrade(grade.grade);
    return Column(
      children: <Widget>[
        ListTile(
          title: Text(
            grade.name,
            style: _cancelledStyle(theme.bodyLarge, grade.cancelled),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!grade.description.isNullOrEmpty)
                Text(
                  grade.description!,
                  style: _cancelledStyle(theme.bodyMedium, grade.cancelled),
                ),
              Text(
                "${DateFormat("dd.MM.yy", Localizations.localeOf(context).toLanguageTag()).format(grade.date)}: ${context.l10n.translateSchoolTerm(grade.type)} - ${grade.weightPercentage}%",
                style: _cancelledStyle(theme.bodyMedium, grade.cancelled),
              ),
              Text(
                context.l10n.translateCreatedText(grade.created),
                style: _cancelledStyle(theme.bodySmall, grade.cancelled),
              ),
              if (!grade.cancelledDescription.isNullOrEmpty)
                Text(
                  grade.cancelledDescription!,
                  style: _cancelledStyle(theme.bodySmall, grade.cancelled),
                ),
            ],
          ),
          trailing: _GradeBadge(
            text: grade.gradeFormatted,
            failing: failing,
            passing: passing,
            colorized: colorGrades,
            textStyle: _gradeTextStyle(
              context,
              theme.titleMedium,
              cancelled: grade.cancelled,
              failing: failing,
              passing: passing,
              colorized: colorGrades,
            ),
          ),
          isThreeLine: true,
        ),
        if (grade.competences.isNotEmpty)
          for (final c in grade.competences)
            CompetenceWidget(
              competence: c,
              cancelled: grade.cancelled,
            ),
      ],
    );
  }
}

class ObservationWidget extends StatelessWidget {
  final Observation observation;

  const ObservationWidget({super.key, required this.observation});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return ListTile(
      title: Text(
        context.l10n.translateSchoolTerm(observation.typeName),
        style: _cancelledStyle(theme.bodyLarge, observation.cancelled),
      ),
      subtitle: Text(
        "${DateFormat("dd.MM.yy", Localizations.localeOf(context).toLanguageTag()).format(observation.date)}${observation.note.isNullOrEmpty ? "" : ": ${observation.note}"}\n${context.l10n.translateCreatedText(observation.created)}",
        style: _cancelledStyle(theme.bodyMedium, observation.cancelled),
      ),
    );
  }
}

class CompetenceWidget extends StatelessWidget {
  final Competence competence;
  final bool cancelled;

  const CompetenceWidget(
      {super.key, required this.competence, required this.cancelled});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 16, right: 8),
      child: Wrap(
        children: <Widget>[
          Text(
            context.l10n.translateSchoolTerm(competence.typeName),
            style: _cancelledStyle(theme.bodyMedium, cancelled),
          ),
          Row(
            children: List.generate(
              5,
              (n) => Star(
                filled: n < competence.grade,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Star extends StatelessWidget {
  final bool filled;

  const Star({super.key, required this.filled});
  @override
  Widget build(BuildContext context) {
    return Icon(filled ? Icons.star : Icons.star_border);
  }
}

class GradeTypeWidget extends StatelessWidget {
  final String typeName;
  final List<DetailEntry> entries;
  final bool colorGrades;

  const GradeTypeWidget(
      {super.key,
      required this.typeName,
      required this.entries,
      required this.colorGrades});
  @override
  Widget build(BuildContext context) {
    final displayGrades = entries
        .map(
          (g) => g is GradeDetail
              ? GradeWidget(grade: g, colorGrades: colorGrades)
              : ObservationWidget(
                  observation: g as Observation,
                ),
        )
        .toList();
    return displayGrades.isEmpty
        ? const SizedBox()
        : ExpansionTile(
            title: Text(context.l10n.translateSchoolTerm(typeName)),
            initiallyExpanded: true,
            children: displayGrades,
          );
  }
}
