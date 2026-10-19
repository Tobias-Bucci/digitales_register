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

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class ClassRegisterPage extends StatefulWidget {
  const ClassRegisterPage({
    super.key,
    this.loader,
    this.cachedLoader = loadCachedClassRegisterLessonPayload,
    this.refreshLoader = refreshClassRegisterLessonPayload,
  });

  final Future<List<ClassRegisterLesson>> Function()? loader;
  final Future<ClassRegisterPayloadSnapshot?> Function() cachedLoader;
  final Future<ClassRegisterPayloadSnapshot?> Function() refreshLoader;

  @override
  State<ClassRegisterPage> createState() => _ClassRegisterPageState();
}

class _ClassRegisterPageState extends State<ClassRegisterPage> {
  List<ClassRegisterLesson>? _lessons;
  DateTime? _lastFetched;
  String? _fingerprint;
  Object? _loadError;
  bool _loading = true;
  Future<void>? _pendingRefresh;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant ClassRegisterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        oldWidget.cachedLoader != widget.cachedLoader ||
        oldWidget.refreshLoader != widget.refreshLoader) {
      _pendingRefresh = null;
      _lessons = null;
      _lastFetched = null;
      _fingerprint = null;
      _loadError = null;
      _loading = true;
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final directLoader = widget.loader;
    if (directLoader != null) {
      await _loadDirect(directLoader);
      return;
    }

    final cached = await widget.cachedLoader();
    if (!mounted) {
      return;
    }
    if (cached != null) {
      _applySnapshot(cached);
      setState(() {
        _loading = false;
        _loadError = null;
      });
      unawaited(_refresh(silent: true));
    } else {
      await _refresh();
    }
  }

  Future<void> _loadDirect(
    Future<List<ClassRegisterLesson>> Function() loader,
  ) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final lessons = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _lessons = _sortedLessons(lessons);
        _lastFetched = DateTime.now();
        _fingerprint = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final directLoader = widget.loader;
    if (directLoader != null) {
      await _loadDirect(directLoader);
      return;
    }

    final pending = _pendingRefresh;
    if (pending != null) {
      await pending;
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    final future = _refreshFromRemote(silent: silent);
    _pendingRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_pendingRefresh, future)) {
        _pendingRefresh = null;
      }
    }
  }

  Future<void> _refreshFromRemote({required bool silent}) async {
    try {
      final snapshot = await widget.refreshLoader();
      if (!mounted) {
        return;
      }
      if (snapshot == null) {
        throw const ClassRegisterLoadException();
      }
      final changed = _fingerprint != snapshot.fingerprint || _lessons == null;
      setState(() {
        if (changed) {
          _applySnapshot(snapshot);
        } else {
          _lastFetched = snapshot.fetchedAt;
          _fingerprint = snapshot.fingerprint;
        }
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_lessons == null || !silent) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applySnapshot(ClassRegisterPayloadSnapshot snapshot) {
    _lessons = _lessonsFromPayload(snapshot.payload);
    _lastFetched = snapshot.fetchedAt;
    _fingerprint = snapshot.fingerprint;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check_outlined),
            const SizedBox(width: 8),
            Text(l10n.text('classRegister.title')),
          ],
        ),
      ),
      body: Stack(
        children: [
          _buildBody(),
          AnimatedLinearProgressIndicator(show: _loading),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final lessons = _lessons;
    if (lessons != null) {
      return _ClassRegisterContent(
        lessons: lessons,
        lastFetched: _lastFetched,
        onRefresh: _refresh,
      );
    }
    if (isOffline()) {
      return const NoInternet();
    }
    final error = _loadError;
    if (error != null) {
      return _ClassRegisterError(
        error: error.toString(),
        onRetry: _refresh,
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

Future<List<ClassRegisterLesson>> loadClassRegisterLessons() async {
  final rawLessons = await loadClassRegisterLessonPayload();
  if (rawLessons == null) {
    throw const ClassRegisterLoadException();
  }
  return _lessonsFromPayload(rawLessons);
}

List<ClassRegisterLesson> _lessonsFromPayload(
  List<Map<String, dynamic>> payload,
) {
  return _sortedLessons(payload.map(ClassRegisterLesson.fromJson).toList());
}

List<ClassRegisterLesson> _sortedLessons(List<ClassRegisterLesson> lessons) {
  return lessons
    ..sort((a, b) {
      final dateCompare = b.date.compareTo(a.date);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return a.hour.compareTo(b.hour);
    });
}

class ClassRegisterLoadException implements Exception {
  const ClassRegisterLoadException();

  @override
  String toString() => 'Class register request returned no lesson list.';
}

class _ClassRegisterContent extends StatelessWidget {
  const _ClassRegisterContent({
    required this.lessons,
    required this.lastFetched,
    required this.onRefresh,
  });

  final List<ClassRegisterLesson> lessons;
  final DateTime? lastFetched;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final grouped = groupBy(lessons, (lesson) => lesson.date);
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _ClassRegisterHeader(
                totalLessons: lessons.length,
                lastFetched: lastFetched,
              ),
              if (lessons.isEmpty) const _EmptyClassRegister(),
              for (final date in dates)
                _LessonDaySection(
                  date: date,
                  lessons: grouped[date] ?? const <ClassRegisterLesson>[],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassRegisterHeader extends StatelessWidget {
  const _ClassRegisterHeader({
    required this.totalLessons,
    required this.lastFetched,
  });

  final int totalLessons;
  final DateTime? lastFetched;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('classRegister.title'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (lastFetched != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.text(
                          'classRegister.lastFetched',
                          args: {
                            'time': DateFormat.Hm(
                              l10n.locale.toLanguageTag(),
                            ).format(lastFetched!),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    l10n.text(
                      totalLessons == 1
                          ? 'classRegister.lessonCount.one'
                          : 'classRegister.lessonCount.other',
                      args: {'count': totalLessons.toString()},
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
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

class _LessonDaySection extends StatelessWidget {
  const _LessonDaySection({
    required this.date,
    required this.lessons,
  });

  final DateTime date;
  final List<ClassRegisterLesson> lessons;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              DateFormat.yMMMMEEEEd(
                l10n.locale.toLanguageTag(),
              ).format(date),
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final lesson in lessons) _LessonCard(lesson: lesson),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = lesson.hasToBeSigned
        ? scheme.error
        : lesson.signedByCurrentUser
            ? Colors.green
            : scheme.outline;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            right: null,
            child:
                ColoredBox(color: statusColor, child: const SizedBox(width: 5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 620;
                    final meta = _LessonMeta(lesson: lesson);
                    final title = _LessonTitle(lesson: lesson);
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          meta,
                          const SizedBox(height: 8),
                          title,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 130, child: meta),
                        const SizedBox(width: 14),
                        Expanded(child: title),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                _LessonChips(lesson: lesson),
                if (lesson.detailSections.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final section in lesson.detailSections)
                    _DetailSection(section: section),
                ],
                if (lesson.teachers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.text(
                      'classRegister.teachers',
                      args: {'teachers': lesson.teachers.join(', ')},
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonMeta extends StatelessWidget {
  const _LessonMeta({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.hourLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.primary,
          ),
        ),
        if (lesson.timeLabel.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            lesson.timeLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _StatusBadge(lesson: lesson),
        if (lesson.isSubstitute) ...[
          const SizedBox(height: 6),
          _SoftBadge(
            label: l10n.text('classRegister.substitute'),
            icon: Icons.swap_horiz_outlined,
          ),
        ],
      ],
    );
  }
}

class _LessonTitle extends StatelessWidget {
  const _LessonTitle({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.subjectName.isEmpty
              ? l10n.text('classRegister.noSubject')
              : l10n.translateSubjectName(lesson.subjectName),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            if (lesson.className.isNotEmpty)
              _InlineMeta(
                icon: Icons.groups_2_outlined,
                text: lesson.className,
              ),
            if (lesson.rooms.isNotEmpty)
              _InlineMeta(
                icon: Icons.meeting_room_outlined,
                text: lesson.rooms.join(', '),
              ),
            if (lesson.lessonTypeName.isNotEmpty)
              _InlineMeta(
                icon: Icons.category_outlined,
                text: l10n.translateSchoolTerm(lesson.lessonTypeName),
              ),
          ],
        ),
        if (lesson.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(
            lesson.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _LessonChips extends StatelessWidget {
  const _LessonChips({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chips = [
      if (lesson.lessonContents.isNotEmpty)
        _ChipData(
          icon: Icons.menu_book_outlined,
          label: l10n.text(
            lesson.lessonContents.length == 1
                ? 'classRegister.contents.one'
                : 'classRegister.contents.other',
            args: {'count': lesson.lessonContents.length.toString()},
          ),
        ),
      if (lesson.homeworkExams.isNotEmpty)
        _ChipData(
          icon: Icons.assignment_outlined,
          label: l10n.text(
            lesson.homeworkExams.length == 1
                ? 'classRegister.homework.one'
                : 'classRegister.homework.other',
            args: {'count': lesson.homeworkExams.length.toString()},
          ),
        ),
      if (lesson.grades.isNotEmpty)
        _ChipData(
          icon: Icons.grade_outlined,
          label: l10n.text(
            lesson.grades.length == 1
                ? 'classRegister.grades.one'
                : 'classRegister.grades.other',
            args: {'count': lesson.grades.length.toString()},
          ),
        ),
      if (lesson.missingStudents.isNotEmpty)
        _ChipData(
          icon: Icons.event_busy_outlined,
          label: l10n.text(
            lesson.missingStudents.length == 1
                ? 'classRegister.absences.one'
                : 'classRegister.absences.other',
            args: {'count': lesson.missingStudents.length.toString()},
          ),
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          _SoftBadge(label: chip.label, icon: chip.icon),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.section});

  final ClassRegisterDetailSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(section.icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.titleFor(context),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 3),
                    for (final line in section.lines)
                      SelectableText(
                        line,
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final label = lesson.hasToBeSigned
        ? l10n.text('classRegister.status.open')
        : lesson.signedByCurrentUser
            ? l10n.text('classRegister.status.signed')
            : lesson.signedByOne
                ? l10n.text('classRegister.status.recorded')
                : l10n.text('classRegister.status.readOnly');
    final color = lesson.hasToBeSigned
        ? scheme.error
        : lesson.signedByCurrentUser
            ? Colors.green
            : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.onSecondaryContainer),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ClassRegisterError extends StatelessWidget {
  const _ClassRegisterError({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('classRegister.loadFailed'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.text('classRegister.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyClassRegister extends StatelessWidget {
  const _EmptyClassRegister();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Text(
          context.t('classRegister.empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}

class ClassRegisterLesson {
  const ClassRegisterLesson({
    required this.date,
    required this.hour,
    required this.toHour,
    required this.timeStart,
    required this.timeEnd,
    required this.className,
    required this.subjectName,
    required this.lessonTypeName,
    required this.description,
    required this.note,
    required this.classComment,
    required this.signedByCurrentUser,
    required this.signedByOne,
    required this.hasToBeSigned,
    required this.isSubstitute,
    required this.rooms,
    required this.teachers,
    required this.lessonContents,
    required this.homeworkExams,
    required this.grades,
    required this.missingStudents,
    required this.observations,
    required this.criticalObservations,
  });

  final DateTime date;
  final int hour;
  final int toHour;
  final int timeStart;
  final int timeEnd;
  final String className;
  final String subjectName;
  final String lessonTypeName;
  final String description;
  final String note;
  final String classComment;
  final bool signedByCurrentUser;
  final bool signedByOne;
  final bool hasToBeSigned;
  final bool isSubstitute;
  final List<String> rooms;
  final List<String> teachers;
  final List<String> lessonContents;
  final List<String> homeworkExams;
  final List<String> grades;
  final List<String> missingStudents;
  final List<String> observations;
  final List<String> criticalObservations;

  String get hourLabel => toHour > hour ? '$hour - $toHour' : '$hour';

  String get timeLabel {
    final start = _formatSeconds(timeStart);
    final end = _formatSeconds(timeEnd);
    if (start.isEmpty && end.isEmpty) {
      return '';
    }
    return '$start - $end';
  }

  List<ClassRegisterDetailSection> get detailSections {
    final sections = <ClassRegisterDetailSection>[];
    if (lessonContents.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.contents',
          icon: Icons.menu_book_outlined,
          lines: lessonContents,
        ),
      );
    }
    if (homeworkExams.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.homework',
          icon: Icons.assignment_outlined,
          lines: homeworkExams,
        ),
      );
    }
    if (grades.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.grades',
          icon: Icons.grade_outlined,
          lines: grades,
        ),
      );
    }
    if (missingStudents.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.absences',
          icon: Icons.event_busy_outlined,
          lines: missingStudents,
        ),
      );
    }
    final notes =
        [note, classComment].where((item) => item.isNotEmpty).toList();
    if (notes.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.notes',
          icon: Icons.notes_outlined,
          lines: notes,
        ),
      );
    }
    final observationLines = [...criticalObservations, ...observations];
    if (observationLines.isNotEmpty) {
      sections.add(
        ClassRegisterDetailSection(
          titleKey: 'classRegister.section.observations',
          icon: Icons.warning_amber_outlined,
          lines: observationLines,
        ),
      );
    }
    return sections;
  }

  factory ClassRegisterLesson.fromJson(Map json) {
    final subject = getMap(json['subject']);
    return ClassRegisterLesson(
      date: DateTime.tryParse(getString(json['date']) ?? '') ?? DateTime(1970),
      hour: _intValue(json['hour']),
      toHour: _intValue(json['toHour'], fallback: _intValue(json['hour'])),
      timeStart: _intValue(json['timeStart']),
      timeEnd: _intValue(json['timeEnd']),
      className: getString(json['className']) ?? '',
      subjectName: getString(subject?['name']) ?? '',
      lessonTypeName: getString(json['lessonTypeName']) ?? '',
      description: getString(json['description']) ?? '',
      note: getString(json['note']) ?? '',
      classComment: getString(json['classComment']) ?? '',
      signedByCurrentUser: getBool(json['signedByCurrentUser']) ?? false,
      signedByOne: getBool(json['signedByOne']) ?? false,
      hasToBeSigned: getBool(json['hasToBeSigned']) ?? false,
      isSubstitute: _intValue(json['isSubstitute']) != 0,
      rooms: _namedItems(json['rooms']),
      teachers: _teacherItems(json['teachers']),
      lessonContents: _contentItems(json['lessonContents']),
      homeworkExams: _contentItems(json['homeworkExams']) +
          _contentItems(json['homeworkExamsOther']),
      grades: _contentItems(json['grades']),
      missingStudents: _studentItems(json['missingStudents']) +
          _studentItems(json['absenceOpenAbsencesStudents']),
      observations: _contentItems(json['observations']),
      criticalObservations: _contentItems(json['criticalObservations']),
    );
  }
}

class ClassRegisterDetailSection {
  const ClassRegisterDetailSection({
    required this.titleKey,
    required this.icon,
    required this.lines,
  });

  final String titleKey;
  final IconData icon;
  final List<String> lines;

  String titleFor(BuildContext context) => context.t(titleKey);
}

class _ChipData {
  const _ChipData({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _formatSeconds(int seconds) {
  if (seconds <= 0) {
    return '';
  }
  final hour = seconds ~/ 3600;
  final minute = (seconds % 3600) ~/ 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

List<String> _namedItems(dynamic value) {
  final list = value is List ? value : const [];
  return list
      .map((item) => getMap(item))
      .nonNulls
      .map((item) => getString(item['name']) ?? '')
      .where((item) => item.trim().isNotEmpty)
      .toList();
}

List<String> _teacherItems(dynamic value) {
  final list = value is List ? value : const [];
  return list
      .map((item) => getMap(item))
      .nonNulls
      .map((item) {
        final firstName = getString(item['firstName']) ?? '';
        final lastName = getString(item['lastName']) ?? '';
        return '$firstName $lastName'.trim();
      })
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _studentItems(dynamic value) {
  final list = value is List ? value : const [];
  return list
      .map((item) => getMap(item))
      .nonNulls
      .map((item) {
        return getString(item['name']) ??
            [
              getString(item['firstName']) ?? '',
              getString(item['lastName']) ?? '',
            ].where((part) => part.isNotEmpty).join(' ');
      })
      .where((item) => item.trim().isNotEmpty)
      .toList();
}

List<String> _contentItems(dynamic value) {
  final list = value is List ? value : const [];
  return list
      .map(_contentText)
      .where((item) => item.trim().isNotEmpty)
      .toList();
}

String _contentText(dynamic value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  final map = getMap(value);
  if (map == null) {
    return value.toString();
  }
  final typeName =
      getString(map['typeName']) ?? getString(map['homeworkTypeName']);
  final name = getString(map['name']) ??
      getString(map['description']) ??
      getString(map['note']) ??
      getString(map['string']) ??
      '';
  final grade = getString(map['grade']) ?? getString(map['gradeFormatted']);
  final parts = [
    if (typeName != null && typeName.trim().isNotEmpty) typeName,
    if (name.trim().isNotEmpty) name,
    if (grade != null && grade.trim().isNotEmpty) grade,
  ];
  return parts.join(': ');
}
