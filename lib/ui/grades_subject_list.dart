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
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/compact_day_list.dart' show compactRowHeight;
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_event_banner.dart' show subjectLetter;
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/ui/grades_panels.dart';
import 'package:dr/ui/sorted_grades_widget.dart' show gradesPageFocusSubject;
import 'package:dr/util.dart';
import 'package:flutter/material.dart';

const _rowGap = 4.0;

/// A row in the list and the card it opens into. Its corners are those of the
/// stadium that the rows of the dashboard have.
const _subjectShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(compactRowHeight / 2)),
);

const _gradeRowHeight = 38.0;
const _gradeRowShape = StadiumBorder();

Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: milliseconds);

/// The subjects of the semester. One of them is open at a time, as in Legacy.
class GradesSubjectList extends StatefulWidget {
  const GradesSubjectList({
    super.key,
    required this.vm,
    required this.colorGrades,
    required this.viewSubjectDetail,
    required this.onOpenDisplayOptions,
  });

  final SortedGradesViewModel vm;
  final bool colorGrades;
  final ValueChanged<Subject> viewSubjectDetail;
  final VoidCallback onOpenDisplayOptions;

  @override
  State<GradesSubjectList> createState() => _GradesSubjectListState();
}

class _GradesSubjectListState extends State<GradesSubjectList> {
  String? _favoriteSubject;
  String? _expandedSubjectKey;
  final Map<String, GlobalKey> _subjectKeys = {};

  SortedGradesViewModel get _vm => widget.vm;

  String _subjectKey(Subject subject) =>
      subject.id?.toString() ?? subject.name.toLowerCase();

  /// The old list fades out next to the new one, so they cannot share a key.
  GlobalKey _globalKey(Subject subject) => _subjectKeys.putIfAbsent(
        '${_vm.semester.name}/${_subjectKey(subject)}',
        GlobalKey.new,
      );

  List<String> get _availableFavorites => filterAvailableFavoriteSubjects(
        _vm.favoriteSubjects,
        _vm.subjects.map((subject) => subject.name),
      );

  @override
  void initState() {
    super.initState();
    gradesPageFocusSubject.addListener(_openFocusSubject);
    _openFocusSubject();
  }

  @override
  void dispose() {
    gradesPageFocusSubject.removeListener(_openFocusSubject);
    super.dispose();
  }

  @override
  void didUpdateWidget(GradesSubjectList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm.semester != _vm.semester) _expandedSubjectKey = null;
    _openFocusSubject();
    final favorite = _favoriteSubject;
    if (favorite != null &&
        findSubjectIgnoreCase(_availableFavorites, favorite) == null) {
      _favoriteSubject = null;
    }
    if (_expandedSubjectKey != null &&
        !_visibleSubjects(_favoriteSubject).any(
          (subject) => _subjectKey(subject) == _expandedSubjectKey,
        )) {
      _expandedSubjectKey = null;
    }
  }

  Iterable<Subject> _visibleSubjects(String? favorite) => favorite == null
      ? _vm.subjects
      : _vm.subjects
          .where((subject) => matchesFavoriteSubject(subject.name, favorite));

  /// Opens the subject a banner asked for, once the page knows that subject.
  void _openFocusSubject() {
    final name = gradesPageFocusSubject.value?.toLowerCase();
    if (name == null) return;
    final subject = _vm.subjects
        .where((subject) => subject.name.toLowerCase() == name)
        .firstOrNull;
    if (subject == null) return;
    gradesPageFocusSubject.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _favoriteSubject = null;
        _expandedSubjectKey = _subjectKey(subject);
      });
      widget.viewSubjectDetail(subject);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(subject));
    });
  }

  /// Scrolls to [subject], so that it comes to rest below the header.
  void _reveal(Subject subject) {
    final context = _globalKey(subject).currentContext;
    if (context == null || !context.mounted) return;
    final viewport = Scrollable.of(context).position.viewportDimension;
    final top = MediaQuery.paddingOf(context).top + _rowGap;
    Scrollable.ensureVisible(
      context,
      alignment: top / (viewport - compactRowHeight),
      duration: _motion(context, 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _setExpanded(Subject subject, bool expanded) {
    if (expanded) {
      logPerformanceEvent(
        "grades_subject_expanded",
        <String, Object?>{
          "subjectId": subject.id,
          "semester": _vm.semester.name,
        },
      );
      widget.viewSubjectDetail(subject);
    }
    setState(
        () => _expandedSubjectKey = expanded ? _subjectKey(subject) : null);
  }

  bool _ignored(Subject subject) => _vm.ignoredSubjectsForAverage.any(
        (name) => name.toLowerCase() == subject.name.toLowerCase(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final favorites = _availableFavorites;
    final favorite = _favoriteSubject == null
        ? null
        : findSubjectIgnoreCase(favorites, _favoriteSubject!);
    final subjects = _visibleSubjects(favorite).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      text: l10n.text('grades.subjects'),
                      children: [
                        TextSpan(
                          text: '  ${subjects.length}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    key: const Key('grades-subjects-title'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              HeaderDiscButton(
                key: const Key('grades-display-options'),
                tooltip: l10n.text('grades.view'),
                icon: Icons.tune_rounded,
                onPressed: widget.onOpenDisplayOptions,
              ),
            ],
          ),
        ),
        if (favorites.isNotEmpty)
          FavoriteSubjectFilter(
            subjects: favorites,
            selectedSubject: favorite,
            onSelected: (value) => setState(() => _favoriteSubject = value),
            subjectThemes: _vm.subjectThemes,
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          ),
        AnimatedSwitcher(
          duration: _motion(context, 220),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: Column(
            key: ValueKey(_vm.semester),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Each on a layer of its own: while one opens, the ones below it
              // only move and are not painted again.
              for (final subject in subjects)
                RepaintBoundary(
                  key: _globalKey(subject),
                  child: GradeSubjectEntry(
                    subject: subject,
                    semester: _vm.semester,
                    sortByType: _vm.sortByType,
                    showCancelled: _vm.showCancelled!,
                    noInternet: _vm.noInternet,
                    ignoredForAverage: _ignored(subject),
                    colorGrades: widget.colorGrades,
                    competenceStarsScale: _vm.competenceStarsScale,
                    subjectTheme: _vm.subjectThemes[subject.name],
                    expanded: _expandedSubjectKey == _subjectKey(subject),
                    onExpansionChanged: (value) => _setExpanded(subject, value),
                  ),
                ),
            ],
          ),
        ),
        if (_vm.subjects.any(_ignored))
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(
              l10n.text('grades.excludedAverageInfo'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One subject: a slim row that opens into a card with its grades.
class GradeSubjectEntry extends StatefulWidget {
  const GradeSubjectEntry({
    super.key,
    required this.subject,
    required this.semester,
    required this.sortByType,
    required this.showCancelled,
    required this.noInternet,
    required this.ignoredForAverage,
    required this.colorGrades,
    required this.competenceStarsScale,
    required this.subjectTheme,
    required this.expanded,
    required this.onExpansionChanged,
  });

  final Subject subject;
  final Semester semester;
  final bool sortByType, showCancelled, noInternet;
  final bool ignoredForAverage, colorGrades, expanded;
  final int? competenceStarsScale;
  final SubjectTheme? subjectTheme;
  final ValueChanged<bool> onExpansionChanged;

  @override
  State<GradeSubjectEntry> createState() => _GradeSubjectEntryState();
}

class _GradeSubjectEntryState extends State<GradeSubjectEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.expanded ? 1 : 0,
  )..addStatusListener(_onStatus);

  late final _sizeFactor = CurvedAnimation(
    parent: _opening,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// What is closed is not built at all, which keeps the list light.
  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(GradeSubjectEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _opening.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _opening.forward();
    } else {
      _opening.reverse();
    }
  }

  @override
  void dispose() {
    _sizeFactor.dispose();
    _opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final entries = widget.subject.detailEntries(widget.semester);
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Material(
        key: ValueKey('grades-subject-${widget.subject.name}'),
        color: scheme.surfaceContainerLowest,
        shape: _subjectShape.copyWith(
          side: BorderSide(
            color: highContrast ? scheme.outline : scheme.outlineVariant,
          ),
        ),
        // The text stands on a solid colour here, so this only gets the rim.
        child: GlassEdge(
          shape: _subjectShape,
          sheen: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SubjectHeader(
                subject: widget.subject,
                semester: widget.semester,
                ignoredForAverage: widget.ignoredForAverage,
                colorGrades: widget.colorGrades,
                subjectTheme: widget.subjectTheme,
                expanded: widget.expanded,
                // Without a connection, there is nothing to open it with.
                onTap: widget.noInternet && entries == null
                    ? null
                    : () => widget.onExpansionChanged(!widget.expanded),
              ),
              if (widget.expanded || !_opening.isDismissed)
                SizeTransition(
                  sizeFactor: _sizeFactor,
                  alignment: Alignment.topCenter,
                  child: AnimatedSize(
                    duration: _motion(context, 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _SubjectDetails(
                      subject: widget.subject,
                      semester: widget.semester,
                      sortByType: widget.sortByType,
                      showCancelled: widget.showCancelled,
                      noInternet: widget.noInternet,
                      colorGrades: widget.colorGrades,
                      competenceStarsScale: widget.competenceStarsScale,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectHeader extends StatelessWidget {
  const _SubjectHeader({
    required this.subject,
    required this.semester,
    required this.ignoredForAverage,
    required this.colorGrades,
    required this.subjectTheme,
    required this.expanded,
    required this.onTap,
  });

  final Subject subject;
  final Semester semester;
  final bool ignoredForAverage, colorGrades, expanded;
  final SubjectTheme? subjectTheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final name = l10n.translateSubjectName(subject.name);
    final hundredths = subject.average(semester);
    final average = format.average(hundredths);
    final absences = subject.absencesFor(semester);
    final absencesLabel = l10n.text(
      absences == 1 ? 'grades.absences.one' : 'grades.absences.other',
      args: {'count': '$absences'},
    );
    return GlassFocusRing(
      shape: const StadiumBorder(),
      activeTint:
          onTap == null ? null : scheme.onSurface.withValues(alpha: 0.06),
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        expanded: onTap == null ? null : expanded,
        onTap: onTap,
        label: [
          name,
          if (hundredths != null)
            l10n.text(
              'grades.spoken.average',
              args: {'value': format.spoken(average, hundredths)},
            ),
          if (absences > 0) absencesLabel,
          if (ignoredForAverage) l10n.text('grades.spoken.excluded'),
        ].join(', '),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('grades-subject-open-${subject.name}'),
          customBorder: const StadiumBorder(),
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          mouseCursor: onTap == null ? null : NewDesignTheme.clickCursor,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: compactRowHeight),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Row(
                children: [
                  _SubjectMark(name: name, subjectTheme: subjectTheme),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: name,
                        children: [
                          if (ignoredForAverage)
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (absences > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: absencesLabel,
                        child: _AbsencesBadge(count: absences),
                      ),
                    ),
                  const SizedBox(width: 6),
                  GradeBadge(
                    text: average,
                    hundredths: hundredths,
                    colorized: colorGrades,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: onTap == null
                        ? null
                        : AnimatedRotation(
                            turns: expanded ? 0.5 : 0,
                            duration: _motion(context, 240),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.expand_more_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The letter of a subject on its colour. The letter itself stays in the colour
/// of text: the colours of subjects only reach the contrast of a shape.
class _SubjectMark extends StatelessWidget {
  const _SubjectMark({required this.name, required this.subjectTheme});

  final String name;
  final SubjectTheme? subjectTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color =
        subjectTheme == null ? scheme.outline : Color(subjectTheme!.color);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.16),
        shape: CircleBorder(side: BorderSide(color: color, width: 1.5)),
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Center(
          child: Text(
            subjectLetter(name),
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _AbsencesBadge extends StatelessWidget {
  const _AbsencesBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.noticeContainer,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 13,
              color: scheme.onNoticeContainer,
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onNoticeContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectDetails extends StatelessWidget {
  const _SubjectDetails({
    required this.subject,
    required this.semester,
    required this.sortByType,
    required this.showCancelled,
    required this.noInternet,
    required this.colorGrades,
    required this.competenceStarsScale,
  });

  final Subject subject;
  final Semester semester;
  final bool sortByType, showCancelled, noInternet, colorGrades;
  final int? competenceStarsScale;

  bool _shown(DetailEntry entry) => showCancelled || !entry.cancelled;

  Widget _row(DetailEntry entry) => entry is GradeDetail
      ? GradeEntryRow(
          key: ValueKey('grades-grade-${entry.id}'),
          grade: entry,
          colorGrades: colorGrades,
          competenceStarsScale: competenceStarsScale,
        )
      : ObservationEntryRow(observation: entry as Observation);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final entries = subject.detailEntries(semester);
    final lastFetched = formatTimeAgoPerSemester(
      localizations: l10n,
      noInternet: noInternet,
      lastFetched: subject.lastFetchedDetailed,
      semester: semester,
    );
    final visible = entries?.where(_shown).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lastFetched != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text('$lastFetched.', style: muted),
            ),
          if (entries == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: AnimatedLinearProgressIndicator(show: !noInternet),
            )
          else if (visible!.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              child: Text(l10n.text('grades.subject.noEntries'), style: muted),
            )
          else if (sortByType)
            for (final group in subject.detailEntriesByType(semester).entries)
              if (group.value.any(_shown))
                _GradeTypeGroup(
                  key: ValueKey('grades-type-${group.key}'),
                  typeName: group.key,
                  rows: [
                    for (final entry in group.value.where(_shown)) _row(entry),
                  ],
                ),
          if (entries != null && !sortByType) ...visible!.map(_row),
        ],
      ),
    );
  }
}

/// The grades of one type, when the grades are sorted that way.
class _GradeTypeGroup extends StatefulWidget {
  const _GradeTypeGroup(
      {super.key, required this.typeName, required this.rows});

  final String typeName;
  final List<Widget> rows;

  @override
  State<_GradeTypeGroup> createState() => _GradeTypeGroupState();
}

class _GradeTypeGroupState extends State<_GradeTypeGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = l10n.translateSchoolTerm(widget.typeName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassFocusRing(
          shape: const StadiumBorder(),
          activeTint: scheme.onSurface.withValues(alpha: 0.05),
          child: Semantics(
            button: true,
            expanded: _open,
            label: '$type, ${widget.rows.length}',
            onTap: () => setState(() => _open = !_open),
            excludeSemantics: true,
            child: InkWell(
              customBorder: const StadiumBorder(),
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              mouseCursor: NewDesignTheme.clickCursor,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.rows.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: _motion(context, 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_open) ...widget.rows,
      ],
    );
  }
}

TextStyle? _cancelled(TextStyle? style, bool cancelled) =>
    cancelled ? style?.copyWith(decoration: TextDecoration.lineThrough) : style;

/// A slim row of an open subject.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.semanticsLabel,
    required this.date,
    required this.onTap,
    required this.child,
    this.fill,
    this.trailing,
  });

  final String semanticsLabel;
  final DateTime date;
  final VoidCallback onTap;
  final Color? fill;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: GlassFocusRing(
        shape: _gradeRowShape,
        activeTint: scheme.onSurface.withValues(alpha: 0.06),
        child: Semantics(
          button: true,
          label: semanticsLabel,
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: fill ?? scheme.surfaceContainerLow,
            shape: _gradeRowShape,
            child: InkWell(
              customBorder: _gradeRowShape,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              mouseCursor: NewDesignTheme.clickCursor,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _gradeRowHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
                  child: Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.textScalerOf(context).scale(40),
                        ),
                        child: Text(
                          format.shortDate(date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: child),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One grade in one line: date, type and title, weight and the grade. Whatever
/// else there is to it opens on a tap.
class GradeEntryRow extends StatelessWidget {
  const GradeEntryRow({
    super.key,
    required this.grade,
    required this.colorGrades,
    required this.competenceStarsScale,
  });

  final GradeDetail grade;
  final bool colorGrades;
  final int? competenceStarsScale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final type = l10n.translateSchoolTerm(grade.type);
    final value = format.grade(grade.gradeFormatted);
    final weight = format.weight(grade.weightPercentage);
    final cancelled = grade.cancelled;
    final foreground = cancelled ? scheme.onSurfaceVariant : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _EntryRow(
          date: grade.date,
          semanticsLabel: [
            type,
            grade.name,
            format.longDate(grade.date),
            l10n.text('grades.spoken.weight', args: {'value': weight}),
            l10n.text(
              'grades.spoken.grade',
              args: {'value': format.spoken(value, grade.grade)},
            ),
            if (cancelled) l10n.text('grades.spoken.cancelled'),
          ].join(', '),
          onTap: () => showGradeDetailsPanel(
            context,
            grade: grade,
            colorGrades: colorGrades,
            competenceStarsScale: competenceStarsScale,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 6),
              Text(
                weight,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              GradeBadge(
                text: value,
                hundredths: grade.grade,
                colorized: colorGrades,
                cancelled: cancelled,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: type,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (grade.name.isNotEmpty)
                  TextSpan(
                    text: '  ${grade.name}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cancelled(theme.textTheme.bodySmall, cancelled),
          ),
        ),
        for (final competence in grade.competences)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 3),
            child: CompetenceLine(
              competence: competence,
              scale: competenceStarsScale,
              cancelled: cancelled,
            ),
          ),
      ],
    );
  }
}

/// An observation has no grade, but its note says what it is about.
class ObservationEntryRow extends StatelessWidget {
  const ObservationEntryRow({super.key, required this.observation});

  final Observation observation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final type = l10n.translateSchoolTerm(observation.typeName);
    final note = observation.note;
    final cancelled = observation.cancelled;
    return _EntryRow(
      date: observation.date,
      fill: scheme.observationContainer.withValues(alpha: 0.6),
      semanticsLabel: [
        l10n.text('dashboard.observation'),
        type,
        if (!note.isNullOrEmpty) note,
        format.longDate(observation.date),
        if (cancelled) l10n.text('grades.spoken.cancelled'),
      ].join(', '),
      onTap: () => showObservationDetailsPanel(
        context,
        observation: observation,
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(left: 6, right: 6),
        child: Icon(
          Icons.visibility_outlined,
          size: 16,
          color: scheme.onObservationContainer,
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: type,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (!note.isNullOrEmpty) TextSpan(text: '  $note'),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _cancelled(
          theme.textTheme.bodySmall?.copyWith(
            color: scheme.onObservationContainer,
          ),
          cancelled,
        ),
      ),
    );
  }
}
