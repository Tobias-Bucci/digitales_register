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
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class CourseMaterialsPage extends StatefulWidget {
  const CourseMaterialsPage({
    super.key,
    this.loader,
    this.cachedLoader = loadCachedCourseMaterialsPayload,
    this.refreshLoader = refreshCourseMaterialsPayload,
    this.entryOpener = openCourseMaterialEntry,
  });

  final Future<List<CourseMaterialCourse>> Function()? loader;
  final Future<PagePayloadSnapshot<List<Map<String, dynamic>>>?> Function()
      cachedLoader;
  final Future<PagePayloadSnapshot<List<Map<String, dynamic>>>?> Function()
      refreshLoader;
  final Future<bool> Function(CourseMaterialEntry entry) entryOpener;

  @override
  State<CourseMaterialsPage> createState() => _CourseMaterialsPageState();
}

class _CourseMaterialsPageState extends State<CourseMaterialsPage> {
  List<CourseMaterialCourse>? _courses;
  DateTime? _lastFetched;
  String? _fingerprint;
  Object? _loadError;
  int? _openingEntryId;
  bool _loading = true;
  Future<void>? _pendingRefresh;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant CourseMaterialsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        oldWidget.cachedLoader != widget.cachedLoader ||
        oldWidget.refreshLoader != widget.refreshLoader ||
        oldWidget.entryOpener != widget.entryOpener) {
      _pendingRefresh = null;
      _courses = null;
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
    Future<List<CourseMaterialCourse>> Function() loader,
  ) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final courses = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _courses = courses;
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
        throw const CourseMaterialsLoadException();
      }
      final changed = _fingerprint != snapshot.fingerprint || _courses == null;
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
      if (_courses == null || !silent) {
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

  void _applySnapshot(
    PagePayloadSnapshot<List<Map<String, dynamic>>> snapshot,
  ) {
    _courses = courseMaterialCoursesFromPayload(snapshot.payload);
    _lastFetched = snapshot.fetchedAt;
    _fingerprint = snapshot.fingerprint;
  }

  Future<void> _openEntry(CourseMaterialEntry entry) async {
    setState(() {
      _openingEntryId = entry.id;
    });
    try {
      final success = await widget.entryOpener(entry);
      if (!success && mounted) {
        showSnackBar(context.t('courseMaterials.openFailed'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingEntryId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_copy_outlined),
            const SizedBox(width: 8),
            Text(l10n.text('courseMaterials.title')),
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
    final courses = _courses;
    if (courses != null) {
      return _CourseMaterialsContent(
        courses: courses,
        lastFetched: _lastFetched,
        openingEntryId: _openingEntryId,
        onRefresh: _refresh,
        onOpenEntry: _openEntry,
      );
    }
    if (isOffline()) {
      return const NoInternet();
    }
    final error = _loadError;
    if (error != null) {
      return _CourseMaterialsError(
        error: error.toString(),
        onRetry: _refresh,
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

class _CourseMaterialsContent extends StatelessWidget {
  const _CourseMaterialsContent({
    required this.courses,
    required this.lastFetched,
    required this.openingEntryId,
    required this.onRefresh,
    required this.onOpenEntry,
  });

  final List<CourseMaterialCourse> courses;
  final DateTime? lastFetched;
  final int? openingEntryId;
  final Future<void> Function() onRefresh;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final totalEntries =
        courses.fold<int>(0, (sum, course) => sum + course.entryCount);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _CourseMaterialsHeader(
                totalEntries: totalEntries,
                lastFetched: lastFetched,
              ),
              if (totalEntries == 0) const _EmptyCourseMaterials(),
              for (final course in courses)
                if (course.entryCount > 0)
                  _CourseCard(
                    course: course,
                    openingEntryId: openingEntryId,
                    onOpenEntry: onOpenEntry,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseMaterialsHeader extends StatelessWidget {
  const _CourseMaterialsHeader({
    required this.totalEntries,
    required this.lastFetched,
  });

  final int totalEntries;
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
                      l10n.text('courseMaterials.title'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (lastFetched != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.text(
                          'courseMaterials.lastFetched',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    l10n.text(
                      totalEntries == 1
                          ? 'courseMaterials.entryCount.one'
                          : 'courseMaterials.entryCount.other',
                      args: {'count': totalEntries.toString()},
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

class _CourseCard extends StatelessWidget {
  const _CourseCard({
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
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.subjectName.isEmpty
                  ? course.title
                  : l10n.translateSubjectName(course.subjectName),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (course.className.isNotEmpty)
                  _InlineMeta(
                    icon: Icons.groups_2_outlined,
                    text: course.className,
                  ),
                _InlineMeta(
                  icon: Icons.menu_book_outlined,
                  text: course.title,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final topic in course.topics)
              _TopicSection(
                topic: topic,
                openingEntryId: openingEntryId,
                onOpenEntry: onOpenEntry,
              ),
          ],
        ),
      ),
    );
  }
}

class _TopicSection extends StatefulWidget {
  const _TopicSection({
    required this.topic,
    required this.openingEntryId,
    required this.onOpenEntry,
  });

  final CourseMaterialTopic topic;
  final int? openingEntryId;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  State<_TopicSection> createState() => _TopicSectionState();
}

class _TopicSectionState extends State<_TopicSection> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleExpanded,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.topic.displayTitle,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.topic.entries.length.toString(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                        child: Column(
                          children: [
                            for (final entry in widget.topic.entries)
                              _CourseEntryTile(
                                entry: entry,
                                opening: widget.openingEntryId == entry.id,
                                onOpenEntry: widget.onOpenEntry,
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseEntryTile extends StatelessWidget {
  const _CourseEntryTile({
    required this.entry,
    required this.opening,
    required this.onOpenEntry,
  });

  final CourseMaterialEntry entry;
  final bool opening;
  final ValueChanged<CourseMaterialEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: opening ? null : () => onOpenEntry(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: opening
                      ? const CircularProgressIndicator(strokeWidth: 2.5)
                      : Icon(
                          entry.isLink
                              ? Icons.open_in_new_outlined
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
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (entry.typeName.isNotEmpty)
                            Text(
                              entry.typeName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          if (entry.lastModified.isNotEmpty)
                            Text(
                              entry.lastModified,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseMaterialsError extends StatelessWidget {
  const _CourseMaterialsError({
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
              l10n.text('courseMaterials.loadFailed'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.text('courseMaterials.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCourseMaterials extends StatelessWidget {
  const _EmptyCourseMaterials();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Text(
          context.t('courseMaterials.empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
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
