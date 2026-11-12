// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

/// The export in the new design. The state class in `export_page.dart` keeps
/// all of the logic (selection, filters, creating and saving the file) and
/// builds this view below the shell; the legacy view stays as it is.
library;

import 'package:dr/app_state.dart' show Semester;
import 'package:dr/export/export_data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/profile_new.dart' show glassFieldDecoration;
import 'package:flutter/material.dart';

/// The icon of an export category.
IconData exportCategoryIcon(ExportCategory c) => switch (c) {
      ExportCategory.certificates => Icons.workspace_premium_outlined,
      ExportCategory.grades => Icons.insights_outlined,
      ExportCategory.messages => Icons.mail_outline,
      ExportCategory.timetable => Icons.calendar_view_week_outlined,
      ExportCategory.exams => Icons.event_note_outlined,
      ExportCategory.tasks => Icons.assignment_outlined,
      ExportCategory.absences => Icons.event_busy_outlined,
      ExportCategory.lessons => Icons.menu_book_outlined,
    };

class ExportNewView extends StatelessWidget {
  const ExportNewView({
    super.key,
    required this.available,
    required this.selected,
    required this.count,
    required this.format,
    required this.semester,
    required this.year,
    required this.years,
    required this.subject,
    required this.subjects,
    required this.range,
    required this.dated,
    required this.busy,
    required this.loading,
    required this.loadFailed,
    required this.noInternet,
    required this.status,
    required this.error,
    required this.onToggle,
    required this.onFormat,
    required this.onYear,
    required this.onSemester,
    required this.onSubject,
    required this.onChooseDates,
    required this.onResetDates,
    required this.onChooseEntries,
    required this.onReload,
    required this.onExport,
  });

  /// How many entries each category has.
  final Map<ExportCategory, int> available;

  /// The chosen categories, in their order, with the entries that pass the
  /// filters.
  final Map<ExportCategory, int> selected;

  /// The entries that will be saved.
  final int count;
  final ExportFormat format;
  final Semester semester;
  final int? year;
  final List<int> years;
  final String? subject;
  final List<String> subjects;

  /// The chosen period, or null for all dates.
  final String? range;

  /// Whether a chosen category has dates, so that year and period apply.
  final bool dated;
  final bool busy, loading, loadFailed, noInternet;

  /// What became of the last export: saved, cancelled or failed ([error]).
  final String? status;
  final bool error;

  final void Function(ExportCategory category, bool selected) onToggle;
  final ValueChanged<ExportFormat> onFormat;
  final ValueChanged<int?> onYear;
  final ValueChanged<Semester> onSemester;
  final ValueChanged<String?> onSubject;
  final VoidCallback onChooseDates, onResetDates, onExport;
  final ValueChanged<ExportCategory> onChooseEntries;
  final Future<void> Function()? onReload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String t(String key) => l10n.text('export.$key');
    final onReload = this.onReload;
    return GlassPage(
      loading: loading || busy,
      header: GlassPageHeader(
        surfaceKey: const Key('export-app-header'),
        titleKey: const Key('export-header-title'),
        title: t('title'),
        floatingMaxWidth: glassHeaderFloatingWidth(
          MediaQuery.sizeOf(context).width,
          twoColumns: true,
        ),
        actions: [
          if (onReload != null)
            HeaderDiscButton(
              key: const Key('export-reload'),
              tooltip: t('reload'),
              icon: Icons.refresh_rounded,
              onPressed: () {
                // The bar below the header shows the load in progress.
                if (!loading && !busy) onReload();
              },
            ),
        ],
      ),
      // From 1080 px the categories stand beside the options and the save
      // button; below, all of it is one list.
      body: Builder(
        builder: (context) => GlassColumnsBody(
          listKey: const Key('export-list'),
          side: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Intro(),
              if (loading) ...[
                const SizedBox(height: 8),
                _Notice(
                  key: const Key('export-loading'),
                  icon: Icons.sync_rounded,
                  text: t('loading'),
                ),
              ] else if (loadFailed && onReload != null) ...[
                const SizedBox(height: 8),
                GlassOfflineHint(
                  key: const Key('export-load-failed'),
                  icon: Icons.sync_problem_rounded,
                  message: t('loadFailed'),
                  onRetry: () {
                    if (!busy) onReload();
                  },
                ),
              ],
              const SizedBox(height: 8),
              GlassSectionHeading(
                title: t('categories'),
                count: selected.isEmpty ? null : selected.length,
              ),
              _categories(context),
              // Above the options, where they follow in the same list.
              if (DashboardColumns.forWindow(
                    MediaQuery.sizeOf(context).width,
                  ) ==
                  null)
                const SizedBox(height: 8),
            ],
          ),
          main: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected.isNotEmpty) ...[
                GlassSectionHeading(title: t('options')),
                _options(context),
                const SizedBox(height: 8),
                GlassSectionHeading(title: t('selection'), count: count),
                _selection(context),
              ],
              const SizedBox(height: 16),
              _summary(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categories(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String t(String key) => context.t('export.$key');
    return GlassCard(
      key: const Key('export-categories'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final c in ExportCategory.values)
              CheckboxListTile(
                key: ValueKey('export-category-${c.name}'),
                value: selected.containsKey(c),
                onChanged: busy ? null : (value) => onToggle(c, value!),
                secondary: Icon(exportCategoryIcon(c),
                    size: 20, color: scheme.primary),
                contentPadding:
                    const EdgeInsetsDirectional.only(start: 12, end: 8),
                // Two lines stay above 48 px.
                visualDensity: VisualDensity.compact,
                title: Text(
                  t('category.${c.name}'),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${t('description.${c.name}')} · ${available[c] ?? 0}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _options(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String t(String key) => l10n.text('export.$key');
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    final range = this.range;
    return GlassCard(
      key: const Key('export-options'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AbsorbPointer(
              absorbing: busy,
              child: GlassSegmentedControl<ExportFormat>(
                key: const Key('export-format'),
                segments: [
                  GlassSegment(
                    value: ExportFormat.pdf,
                    label: t('pdf'),
                    fullLabel: t('pdf'),
                  ),
                  GlassSegment(
                    value: ExportFormat.csv,
                    label: t('csv'),
                    fullLabel: t('csv'),
                  ),
                ],
                selected: format,
                onChanged: onFormat,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t(format == ExportFormat.csv && selected.length > 1
                ? 'zipHint'
                : 'formatHint'),
            style: hint,
          ),
          if (dated) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('year:$year:${years.join(',')}'),
              isExpanded: true,
              initialValue: year,
              decoration: glassFieldDecoration(
                context,
                labelText: t('schoolYear'),
              ),
              items: [
                DropdownMenuItem<int>(child: Text(t('allYears'))),
                for (final y in years)
                  DropdownMenuItem(value: y, child: Text('$y-${y + 1}')),
              ],
              onChanged: busy ? null : onYear,
            ),
            const SizedBox(height: 8),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: const Key('export-period'),
                contentPadding: const EdgeInsetsDirectional.only(start: 4),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                leading: Icon(Icons.date_range_outlined,
                    size: 20, color: scheme.primary),
                minLeadingWidth: 20,
                horizontalTitleGap: 8,
                title: Text(
                  t('period'),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  range ?? t('allDates'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                onTap: busy ? null : onChooseDates,
                trailing: range == null
                    ? Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant)
                    : IconButton(
                        tooltip: t('reset'),
                        onPressed: busy ? null : onResetDates,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ],
          if (selected.containsKey(ExportCategory.grades)) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<Semester>(
              isExpanded: true,
              initialValue: semester,
              decoration: glassFieldDecoration(
                context,
                labelText: t('semester'),
              ),
              items: [
                for (final s in Semester.values)
                  DropdownMenuItem(
                      value: s, child: Text(l10n.semesterLabel(s))),
              ],
              onChanged: busy ? null : (value) => onSemester(value!),
            ),
          ],
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('subject:$subject:${subjects.join(',')}'),
              initialValue: subject,
              isExpanded: true,
              decoration: glassFieldDecoration(
                context,
                labelText: t('field.subject'),
              ),
              items: [
                DropdownMenuItem<String>(child: Text(t('allSubjects'))),
                for (final s in subjects)
                  DropdownMenuItem(
                    value: s,
                    child: Text(s, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy ? null : onSubject,
            ),
          ],
          if (selected.containsKey(ExportCategory.certificates)) ...[
            const SizedBox(height: 12),
            Text(t('certificateNotice'), style: hint),
          ],
        ],
      ),
    );
  }

  Widget _selection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String t(String key) => context.t('export.$key');
    return GlassCard(
      key: const Key('export-selection'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final MapEntry(key: c, value: entries) in selected.entries)
              ListTile(
                key: ValueKey('export-selection-${c.name}'),
                contentPadding:
                    const EdgeInsetsDirectional.only(start: 12, end: 12),
                minLeadingWidth: 20,
                horizontalTitleGap: 12,
                visualDensity: VisualDensity.compact,
                leading: Icon(exportCategoryIcon(c),
                    size: 20, color: scheme.primary),
                title: Text(
                  t('category.${c.name}'),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '$entries ${t('entries')}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                trailing: c == ExportCategory.certificates
                    ? null
                    : Icon(Icons.tune, color: scheme.onSurfaceVariant),
                onTap: busy || c == ExportCategory.certificates
                    ? null
                    : () => onChooseEntries(c),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String t(String key) => context.t('export.$key');
    final status = this.status;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected.isNotEmpty && count == 0) ...[
          _Notice(
            key: const Key('export-empty'),
            icon: Icons.filter_alt_off_outlined,
            text: t('empty'),
          ),
          const SizedBox(height: 8),
        ],
        if (status != null) ...[
          _Notice(
            key: Key(error ? 'export-error' : 'export-status'),
            icon: error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            iconColor: error ? scheme.error : scheme.primary,
            text: status,
            live: true,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        FilledButton.icon(
          key: const Key('export-save'),
          onPressed: busy || loading || count == 0 ? null : onExport,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                )
              : const Icon(Icons.save_alt_rounded, size: 20),
          label: Text(busy ? t('creating') : '${t('save')} ($count)'),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t(noInternet ? 'offlineNotice' : 'scopeNotice'),
            style: small,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(t('privacyNotice'), style: small),
        ),
      ],
    );
  }
}

/// What the export does, at the top of the page.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      key: const Key('export-intro'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.primaryContainer,
              shape: const CircleBorder(),
            ),
            child: SizedBox.square(
              dimension: 44,
              child: Icon(
                Icons.file_download_outlined,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    context.t('export.headline'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.t('export.intro'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A short message on a card: loading, nothing to export, the result.
class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor,
    this.live = false,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: live,
              container: true,
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
