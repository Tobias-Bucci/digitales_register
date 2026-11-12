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
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The gap between the days of the list.
const _dayGap = 8.0;

/// The class register of the new design. `ClassRegisterPage` keeps loading,
/// refreshing and the cache, and passes what it has to this view.
class ClassRegisterPageNew extends StatelessWidget {
  const ClassRegisterPageNew({
    super.key,
    required this.lessons,
    required this.lastFetched,
    required this.loadError,
    required this.loading,
    required this.offline,
    required this.onRefresh,
  });

  /// Null until the first lessons arrived, newest day first.
  final List<ClassRegisterLesson>? lessons;
  final DateTime? lastFetched;
  final Object? loadError;
  final bool loading, offline;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GlassPage(
      loading: loading,
      header: GlassPageHeader(
        surfaceKey: const Key('class-register-app-header'),
        titleKey: const Key('class-register-header-title'),
        title: l10n.text('classRegister.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        actions: [
          HeaderDiscButton(
            key: const Key('class-register-refresh'),
            tooltip: l10n.text('appNotifications.refresh'),
            icon: Icons.refresh_rounded,
            onPressed: () => unawaited(onRefresh()),
          ),
        ],
      ),
      body: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final top = MediaQuery.paddingOf(context).top;
    Widget refreshable(Widget child) => RefreshIndicator(
          edgeOffset: top,
          onRefresh: onRefresh,
          child: child,
        );
    final lessons = this.lessons;
    if (lessons == null) {
      if (offline) {
        return GlassStateCard(
          key: const Key('class-register-offline'),
          icon: Icons.wifi_off_rounded,
          title: l10n.text('offline.title'),
          body: l10n.text('offline.body'),
          actionLabel: l10n.text('common.retry'),
          onAction: () => unawaited(onRefresh()),
        );
      }
      final error = loadError;
      if (error != null) {
        return GlassStateCard(
          key: const Key('class-register-error'),
          icon: Icons.error_outline_rounded,
          title: l10n.text('classRegister.loadFailed'),
          body: error.toString(),
          actionLabel: l10n.text('classRegister.retry'),
          onAction: () => unawaited(onRefresh()),
        );
      }
      // The bar below the header shows that the lessons are on their way.
      return const SizedBox.expand(key: Key('class-register-loading'));
    }
    if (lessons.isEmpty) {
      return refreshable(GlassStateCard(
        key: const Key('class-register-empty'),
        icon: Icons.fact_check_outlined,
        title: l10n.text('classRegister.empty'),
        body: '',
      ));
    }
    final grouped = groupBy(lessons, (lesson) => lesson.date);
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final lastFetched = this.lastFetched;
    final rows = <Widget>[
      if (offline && lastFetched != null)
        GlassOfflineHint(
          key: const Key('class-register-last-fetched'),
          message: l10n.text(
            'grades.offlineMode',
            args: {
              'time': l10n.formatTimeAgo(
                UtcDateTime.makeUtc(lastFetched.toLocal()),
              ),
            },
          ),
          onRetry: () => unawaited(onRefresh()),
        ),
      _Summary(count: lessons.length, lastFetched: lastFetched),
    ];
    final count = rows.length + dates.length;
    return refreshable(GlassListBody.builder(
      listKey: const Key('class-register-list'),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index < rows.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: rows[index],
          );
        }
        final date = dates[index - rows.length];
        return Padding(
          padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : _dayGap),
          child: _Day(date: date, lessons: grouped[date]!),
        );
      },
    ));
  }
}

/// How many lessons there are and when they were loaded, quietly above the
/// list.
class _Summary extends StatelessWidget {
  const _Summary({required this.count, required this.lastFetched});

  final int count;
  final DateTime? lastFetched;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lastFetched = this.lastFetched;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        [
          l10n.text(
            count == 1
                ? 'classRegister.lessonCount.one'
                : 'classRegister.lessonCount.other',
            args: {'count': count.toString()},
          ),
          if (lastFetched != null)
            l10n.text(
              'classRegister.lastFetched',
              args: {
                'time': DateFormat.Hm(l10n.locale.toLanguageTag())
                    .format(lastFetched),
              },
            ),
        ].join(' · '),
        key: const Key('class-register-summary'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A day: its date as a heading, then its lessons in one card.
class _Day extends StatelessWidget {
  const _Day({required this.date, required this.lessons});

  final DateTime date;
  final List<ClassRegisterLesson> lessons;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: ValueKey('class-register-day-${date.toIso8601String()}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSectionHeading(
          title:
              DateFormat.yMMMMEEEEd(l10n.locale.toLanguageTag()).format(date),
          count: lessons.length,
        ),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, lesson) in lessons.indexed) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: scheme.outlineVariant,
                  ),
                _LessonRow(lesson: lesson),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A lesson: its hour, the subject, what it is and where, its state, and what
/// was entered for it.
class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final ClassRegisterLesson lesson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final facts = [
      if (lesson.timeLabel.isNotEmpty) lesson.timeLabel,
      if (lesson.className.isNotEmpty) lesson.className,
      if (lesson.rooms.isNotEmpty) lesson.rooms.join(', '),
      if (lesson.lessonTypeName.isNotEmpty)
        l10n.translateSchoolTerm(lesson.lessonTypeName),
    ];
    return Padding(
      key: const Key('class-register-lesson'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HourMark(label: lesson.hourLabel),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.subjectName.isEmpty
                      ? l10n.text('classRegister.noSubject')
                      : l10n.translateSubjectName(lesson.subjectName),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (facts.isNotEmpty) Text(facts.join(' · '), style: muted),
                const SizedBox(height: 6),
                _Badges(lesson: lesson),
                if (lesson.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  LinkifiedText(
                    lesson.description,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                ],
                for (final section in lesson.detailSections)
                  _Section(section: section),
                if (lesson.teachers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.text(
                      'classRegister.teachers',
                      args: {'teachers': lesson.teachers.join(', ')},
                    ),
                    style: muted,
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

/// The hour of a lesson on a quiet disc at the start of its row.
class _HourMark extends StatelessWidget {
  const _HourMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The state of a lesson, whether it was a substitution, and how much was
/// entered for it.
class _Badges extends StatelessWidget {
  const _Badges({required this.lesson});

  final ClassRegisterLesson lesson;

  String _count(AppLocalizations l10n, String key, int count) => l10n.text(
        count == 1 ? '$key.one' : '$key.other',
        args: {'count': count.toString()},
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (status, statusBackground, statusForeground) = lesson.hasToBeSigned
        ? (
            l10n.text('classRegister.status.open'),
            scheme.errorContainer,
            scheme.onErrorContainer,
          )
        : lesson.signedByCurrentUser
            ? (
                l10n.text('classRegister.status.signed'),
                scheme.successContainer,
                scheme.onSuccessContainer,
              )
            : (
                l10n.text(
                  lesson.signedByOne
                      ? 'classRegister.status.recorded'
                      : 'classRegister.status.readOnly',
                ),
                scheme.surfaceContainerHighest,
                scheme.onSurfaceVariant,
              );
    final secondary = (scheme.secondaryContainer, scheme.onSecondaryContainer);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Badge(
          label: status,
          background: statusBackground,
          foreground: statusForeground,
        ),
        if (lesson.isSubstitute)
          _Badge(
            label: l10n.text('classRegister.substitute'),
            icon: Icons.swap_horiz_rounded,
            background: scheme.warningContainer,
            foreground: scheme.onWarningContainer,
          ),
        if (lesson.lessonContents.isNotEmpty)
          _Badge(
            label: _count(
              l10n,
              'classRegister.contents',
              lesson.lessonContents.length,
            ),
            icon: Icons.menu_book_outlined,
            background: secondary.$1,
            foreground: secondary.$2,
          ),
        if (lesson.homeworkExams.isNotEmpty)
          _Badge(
            label: _count(
              l10n,
              'classRegister.homework',
              lesson.homeworkExams.length,
            ),
            icon: Icons.assignment_outlined,
            background: secondary.$1,
            foreground: secondary.$2,
          ),
        if (lesson.grades.isNotEmpty)
          _Badge(
            label: _count(l10n, 'classRegister.grades', lesson.grades.length),
            icon: Icons.grade_outlined,
            background: secondary.$1,
            foreground: secondary.$2,
          ),
        if (lesson.missingStudents.isNotEmpty)
          _Badge(
            label: _count(
              l10n,
              'classRegister.absences',
              lesson.missingStudents.length,
            ),
            icon: Icons.event_busy_outlined,
            background: scheme.noticeContainer,
            foreground: scheme.onNoticeContainer,
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Color background, foreground;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 2, 8, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What was entered for a lesson under one title: contents, homework,
/// grades, absences, notes or observations.
class _Section extends StatelessWidget {
  const _Section({required this.section});

  final ClassRegisterDetailSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // With large text, the words need the width more than the icon does.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!large) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child:
                  Icon(section.icon, size: 16, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.titleFor(context),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                for (final line in section.lines)
                  LinkifiedText(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
