// Copyright (C) 2021 Michael Debertol
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
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

typedef ViewSubjectDetailCallback = void Function(Subject s);
typedef SetBoolCallback = void Function(bool byType);

TextStyle? _cancelledStyle(TextStyle? baseStyle, bool cancelled) {
  if (!cancelled) {
    return baseStyle;
  }
  return baseStyle?.copyWith(decoration: TextDecoration.lineThrough) ??
      const TextStyle(decoration: TextDecoration.lineThrough);
}

class SortedGradesWidget extends StatefulWidget {
  final SortedGradesViewModel vm;
  final ViewSubjectDetailCallback viewSubjectDetail;
  final SetBoolCallback sortByTypeCallback, showCancelledCallback;
  final VoidCallback showGradeCalculator;

  const SortedGradesWidget({
    super.key,
    required this.vm,
    required this.viewSubjectDetail,
    required this.sortByTypeCallback,
    required this.showCancelledCallback,
    required this.showGradeCalculator,
  });

  @override
  State<SortedGradesWidget> createState() => _SortedGradesWidgetState();
}

class _SortedGradesWidgetState extends State<SortedGradesWidget> {
  String? _favoriteSubject;

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
          title: const Text("Noten nach Art sortieren"),
          onChanged: widget.sortByTypeCallback,
          value: widget.vm.sortByType,
        ),
        SwitchListTile.adaptive(
          title: const Text("Gelöschte Noten anzeigen"),
          onChanged: widget.showCancelledCallback,
          value: widget.vm.showCancelled!,
        ),
        const Divider(
          height: 0,
        ),
        for (final s in visibleSubjects)
          SubjectWidget(
            subject: s,
            sortByType: widget.vm.sortByType,
            viewSubjectDetail: () => widget.viewSubjectDetail(s),
            showCancelled: widget.vm.showCancelled!,
            semester: widget.vm.semester,
            noInternet: widget.vm.noInternet,
            ignoredForAverage: widget.vm.ignoredSubjectsForAverage.any(
              (element) => element.toLowerCase() == s.name.toLowerCase(),
            ),
          ),
        if (widget.vm.subjects.any(
          (s) => widget.vm.ignoredSubjectsForAverage.any(
            (element) => element.toLowerCase() == s.name.toLowerCase(),
          ),
        ))
          const ListTile(
            title: Text(
              "* Du hast dieses Fach aus dem Notendurchschnitt ausgeschlossen",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ListTile(
            title: Row(
              children: [
                Text("Notenrechner"),
              ],
            ),
            subtitle:
                const Text("Berechne den Durchschnitt von beliebigen Noten"),
            onTap: widget.showGradeCalculator,
          ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant SortedGradesWidget oldWidget) {
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
    super.didUpdateWidget(oldWidget);
  }
}

class SubjectWidget extends StatefulWidget {
  final bool sortByType, showCancelled, noInternet, ignoredForAverage;
  final Subject subject;
  final Semester semester;
  final VoidCallback viewSubjectDetail;

  const SubjectWidget(
      {super.key,
      required this.sortByType,
      required this.subject,
      required this.viewSubjectDetail,
      required this.showCancelled,
      required this.semester,
      required this.noInternet,
      required this.ignoredForAverage});

  @override
  _SubjectWidgetState createState() => _SubjectWidgetState();
}

class _SubjectWidgetState extends State<SubjectWidget> {
  bool closed = true;
  @override
  void didUpdateWidget(SubjectWidget oldWidget) {
    if (oldWidget.semester != widget.semester) closed = true;
    super.didUpdateWidget(oldWidget);
  }

  Widget? _lastFetchedMessage() {
    if (closed || !widget.noInternet) {
      return null;
    }
    final formatted = formatTimeAgoPerSemester(
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
    return AbsorbPointer(
      absorbing: widget.noInternet && entries == null,
      child: ExpansionTile(
        key: ValueKey(widget.subject.id),
        title: Text.rich(
          TextSpan(
            text: widget.subject.name,
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
        leading: Text.rich(
          TextSpan(
            text: 'Ø ',
            style: averageStyle,
            children: <TextSpan>[
              TextSpan(
                text: widget.subject.averageFormatted(widget.semester),
                style: averageStyle,
              ),
            ],
          ),
        ),
        trailing:
            widget.noInternet && entries == null ? const SizedBox() : null,
        onExpansionChanged: (expansion) {
          setState(() {
            closed = !expansion;
            if (expansion) {
              widget.viewSubjectDetail();
            }
          });
        },
        initiallyExpanded: !closed,
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
                      // we're using a UniqueKey here so that the framework
                      // detects a change on every rebuild. There would be no
                      // animations otherwise, as the Column as the direct child
                      // of the AnimatedSwitcher always stays the same (just different children).
                      key: UniqueKey(),
                      children: [
                        if (widget.sortByType)
                          ...Subject.sortByType(entries).entries.map(
                                (entry) => GradeTypeWidget(
                                  typeName: entry.key,
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
                                    ? GradeWidget(grade: g)
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

  const GradeWidget({super.key, required this.grade});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                "${DateFormat("dd.MM.yy").format(grade.date)}: ${grade.type} - ${grade.weightPercentage}%",
                style: _cancelledStyle(theme.bodyMedium, grade.cancelled),
              ),
              Text(
                grade.created,
                style: _cancelledStyle(theme.bodySmall, grade.cancelled),
              ),
              if (!grade.cancelledDescription.isNullOrEmpty)
                Text(
                  grade.cancelledDescription!,
                  style: _cancelledStyle(theme.bodySmall, grade.cancelled),
                ),
            ],
          ),
          trailing: Text(
            grade.gradeFormatted,
            style: _cancelledStyle(theme.titleMedium, grade.cancelled),
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
        observation.typeName,
        style: _cancelledStyle(theme.bodyLarge, observation.cancelled),
      ),
      subtitle: Text(
        "${DateFormat("dd.MM.yy").format(observation.date)}${observation.note.isNullOrEmpty ? "" : ": ${observation.note}"}\n${observation.created}",
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
            competence.typeName,
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

  const GradeTypeWidget(
      {super.key, required this.typeName, required this.entries});
  @override
  Widget build(BuildContext context) {
    final displayGrades = entries
        .map(
          (g) => g is GradeDetail
              ? GradeWidget(grade: g)
              : ObservationWidget(
                  observation: g as Observation,
                ),
        )
        .toList();
    return displayGrades.isEmpty
        ? const SizedBox()
        : ExpansionTile(
            title: Text(typeName),
            initiallyExpanded: true,
            children: displayGrades,
          );
  }
}
