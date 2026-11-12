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

import 'package:dr/course_materials.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The gap between the courses of the list.
const _courseGap = 8.0;

/// A topic or a material inside the card of a course.
const _rowShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
);

Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: milliseconds);

/// The course materials of the new design. `CourseMaterialsPage` keeps
/// loading, refreshing, the cache and opening the materials, and passes what
/// it has to this view.
class CourseMaterialsPageNew extends StatelessWidget {
  const CourseMaterialsPageNew({
    super.key,
    required this.courses,
    required this.lastFetched,
    required this.loadError,
    required this.refreshError,
    required this.openingEntryId,
    required this.loading,
    required this.offline,
    required this.onRefresh,
    required this.onOpenEntry,
  });

  /// Null until the first courses arrived.
  final List<CourseMaterialCourse>? courses;
  final DateTime? lastFetched;
  final Object? loadError;

  /// Why the last refresh failed while the saved courses stay visible.
  final Object? refreshError;
  final int? openingEntryId;
  final bool loading, offline;
  final Future<void> Function() onRefresh;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GlassPage(
      loading: loading,
      header: GlassPageHeader(
        surfaceKey: const Key('course-materials-app-header'),
        titleKey: const Key('course-materials-header-title'),
        title: l10n.text('courseMaterials.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        actions: [
          HeaderDiscButton(
            key: const Key('course-materials-refresh'),
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
    final courses = this.courses;
    if (courses == null) {
      if (offline) {
        return GlassStateCard(
          key: const Key('course-materials-offline'),
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
          key: const Key('course-materials-error'),
          icon: Icons.error_outline_rounded,
          title: l10n.text('courseMaterials.loadFailed'),
          body: error is CourseMaterialsIncompleteException
              ? l10n.text('courseMaterials.incomplete')
              : error.toString(),
          actionLabel: l10n.text('courseMaterials.retry'),
          onAction: () => unawaited(onRefresh()),
        );
      }
      // The bar below the header shows that the courses are on their way.
      return const SizedBox.expand(key: Key('course-materials-loading'));
    }
    final shown = [
      for (final course in courses)
        if (course.entryCount > 0) course,
    ];
    final refreshError = this.refreshError;
    final hint = refreshError == null
        ? null
        : GlassOfflineHint(
            key: const Key('course-materials-refresh-failed'),
            icon: offline ? Icons.wifi_off_rounded : Icons.sync_problem_rounded,
            message: l10n.text(
              refreshError is CourseMaterialsIncompleteException
                  ? 'courseMaterials.refreshIncomplete'
                  : 'courseMaterials.refreshFailed',
            ),
            onRetry: () => unawaited(onRefresh()),
          );
    if (shown.isEmpty) {
      final empty = GlassStateCard(
        key: const Key('course-materials-empty'),
        icon: Icons.folder_copy_outlined,
        title: l10n.text('courseMaterials.empty'),
        body: '',
      );
      if (hint == null) return refreshable(empty);
      return refreshable(GlassListBody(
        listKey: const Key('course-materials-list'),
        children: [
          hint,
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: empty,
            ),
          ),
        ],
      ));
    }
    final total = shown.fold<int>(0, (sum, course) => sum + course.entryCount);
    final rows = <Widget>[
      if (hint != null) hint,
      _Summary(count: total, lastFetched: lastFetched),
    ];
    final count = rows.length + shown.length;
    return refreshable(GlassListBody.builder(
      listKey: const Key('course-materials-list'),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index < rows.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: rows[index],
          );
        }
        final course = shown[index - rows.length];
        return Padding(
          padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : _courseGap),
          child: _Course(
            key: ValueKey('course-materials-course-${course.id}'),
            course: course,
            openingEntryId: openingEntryId,
            onOpenEntry: onOpenEntry,
          ),
        );
      },
    ));
  }
}

/// How many materials there are and when they were loaded, quietly above the
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
                ? 'courseMaterials.entryCount.one'
                : 'courseMaterials.entryCount.other',
            args: {'count': count.toString()},
          ),
          if (lastFetched != null)
            l10n.text(
              'courseMaterials.lastFetched',
              args: {
                'time': DateFormat.Hm(l10n.locale.toLanguageTag())
                    .format(lastFetched),
              },
            ),
        ].join(' · '),
        key: const Key('course-materials-summary'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A course: its subject as a heading, then a card with its class, its title
/// and its topics.
class _Course extends StatelessWidget {
  const _Course({
    super.key,
    required this.course,
    required this.openingEntryId,
    required this.onOpenEntry,
  });

  final CourseMaterialCourse course;
  final int? openingEntryId;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = course.subjectName.isEmpty
        ? course.title
        : l10n.translateSubjectName(course.subjectName);
    final facts = [
      if (course.className.isNotEmpty) course.className,
      // The title is the heading already when the course has no subject.
      if (course.subjectName.isNotEmpty) course.title,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSectionHeading(title: title, count: course.entryCount),
        GlassCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (facts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                  child: Text(
                    facts.join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final topic in course.topics)
                // Each on a layer of its own: while one opens, the ones below
                // it only move and are not painted again.
                RepaintBoundary(
                  key: ValueKey('course-materials-topic-${topic.id}'),
                  child: _Topic(
                    topic: topic,
                    openingEntryId: openingEntryId,
                    onOpenEntry: onOpenEntry,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A topic: a slim row that opens in place into its materials.
class _Topic extends StatefulWidget {
  const _Topic({
    required this.topic,
    required this.openingEntryId,
    required this.onOpenEntry,
  });

  final CourseMaterialTopic topic;
  final int? openingEntryId;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  State<_Topic> createState() => _TopicState();
}

class _TopicState extends State<_Topic> with SingleTickerProviderStateMixin {
  bool _expanded = false;

  late final AnimationController _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
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

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (MediaQuery.disableAnimationsOf(context)) {
      _opening.value = _expanded ? 1 : 0;
    } else if (_expanded) {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topic = widget.topic;
    final count = topic.entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassFocusRing(
          shape: _rowShape,
          activeTint: scheme.onSurface.withValues(alpha: 0.05),
          child: Semantics(
            button: true,
            expanded: _expanded,
            label: '${topic.displayTitle}, $count',
            onTap: _toggle,
            excludeSemantics: true,
            child: InkWell(
              customBorder: _rowShape,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              mouseCursor: NewDesignTheme.clickCursor,
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.folder_open_outlined
                            : Icons.folder_outlined,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          topic.displayTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: _motion(context, 220),
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
        ),
        if (_expanded || !_opening.isDismissed)
          SizeTransition(
            sizeFactor: _sizeFactor,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 0, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in topic.entries)
                    _Entry(
                      key: ValueKey('course-materials-entry-${entry.id}'),
                      entry: entry,
                      opening: widget.openingEntryId == entry.id,
                      onOpen: widget.onOpenEntry,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A material: a file or a link, opened with a tap. While it opens, its icon
/// turns into a ring.
class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.entry,
    required this.opening,
    required this.onOpen,
  });

  final CourseMaterialEntry entry;
  final bool opening;
  final ValueChanged<CourseMaterialEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final facts = [
      if (entry.typeName.isNotEmpty) entry.typeName,
      if (entry.lastModified.isNotEmpty) entry.lastModified,
    ];
    final onTap = opening ? null : () => onOpen(entry);
    return GlassFocusRing(
      shape: _rowShape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Semantics(
        button: true,
        enabled: !opening,
        label: [entry.title, ...facts].join(', '),
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          customBorder: _rowShape,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          mouseCursor: NewDesignTheme.clickCursor,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: opening
                        ? CircularProgressIndicator(
                            key: const Key('course-materials-opening'),
                            strokeWidth: 2,
                            color: scheme.primary,
                          )
                        : Icon(
                            entry.isLink
                                ? Icons.link_rounded
                                : Icons.insert_drive_file_outlined,
                            size: 20,
                            color: scheme.primary,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: theme.textTheme.bodyMedium),
                        if (facts.isNotEmpty)
                          Text(
                            facts.join(' · '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    entry.isLink
                        ? Icons.open_in_new_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
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
