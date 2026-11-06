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

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_history_container.dart';
import 'package:dr/container/grades_page_new_container.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/grade_statistics.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/compact_day_list.dart' show compactRowHeight;
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grades_overview.dart';
import 'package:dr/ui/grades_panels.dart';
import 'package:dr/ui/grades_subject_list.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// What the page can do, which is the same as what Legacy can do.
@immutable
class GradesPageCallbacks {
  const GradesPageCallbacks({
    required this.changeSemester,
    required this.showGradesSettings,
    required this.showGradesChart,
    required this.showGradeCalculator,
    required this.setSortByType,
    required this.setShowCancelled,
    required this.setColorGrades,
    required this.retry,
    required this.viewSubjectDetail,
  });

  final ValueChanged<Semester> changeSemester;
  final VoidCallback showGradesSettings, showGradesChart, showGradeCalculator;
  final ValueChanged<bool> setSortByType, setShowCancelled, setColorGrades;
  final VoidCallback retry;
  final ValueChanged<Subject> viewSubjectDetail;
}

/// The header of the page: its title, the semester and the history.
class GradesPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const GradesPageHeader({
    super.key,
    required this.semester,
    required this.onSemesterChanged,
    required this.onShowHistory,
    this.floatingMaxWidth,
  });

  static const double height = 56;

  /// What the semester control leaves to the title, for very large text.
  static const double _minTitleWidth = 56;

  final Semester semester;
  final ValueChanged<Semester> onSemesterChanged;
  final VoidCallback onShowHistory;
  final double? floatingMaxWidth;

  @override
  Size get preferredSize => Size.fromHeight(
        height + (floatingMaxWidth == null ? 0 : DesignTokens.gutter),
      );

  String _shortLabel(AppLocalizations l10n, Semester semester) {
    if (floatingMaxWidth != null) return l10n.semesterLabel(semester);
    if (semester == Semester.first) return '1';
    if (semester == Semester.second) return '2';
    return l10n.text('filter.all');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return GlassHeaderShell(
      surfaceKey: const Key('grades-app-header'),
      floatingMaxWidth: floatingMaxWidth,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            left: floatingMaxWidth == null ? 16 : 20,
            right: floatingMaxWidth == null ? 4 : 8,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      // A long word gets smaller, it is the only word there is.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l10n.text('sidebar.grades'),
                          key: const Key('grades-header-title'),
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth - _minTitleWidth - 56,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: GlassSegmentedControl<Semester>(
                      key: const Key('grades-semester'),
                      selected: semester,
                      onChanged: onSemesterChanged,
                      segments: [
                        for (final value in Semester.values)
                          GlassSegment(
                            value: value,
                            label: _shortLabel(l10n, value),
                            fullLabel: l10n.semesterLabel(value),
                          ),
                      ],
                    ),
                  ),
                ),
                HeaderDiscButton(
                  key: const Key('grades-history'),
                  tooltip: l10n.text('grades.history.title'),
                  icon: Icons.history_rounded,
                  onPressed: onShowHistory,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The grades page of the new design. Legacy keeps `GradesPage`.
class GradesPageNew extends StatelessWidget {
  const GradesPageNew({super.key, required this.vm, required this.callbacks});

  final NewGradesViewModel vm;
  final GradesPageCallbacks callbacks;

  void _showHistory(BuildContext context) {
    GradesHistoryContainer.logOpened();
    showGradesHistoryPanel(
      context,
      comparison: compareGradeSemesters(
        subjects: vm.list.subjects,
        currentSemester: Semester.second,
        previousSemester: Semester.first,
        ignoredSubjects: vm.list.ignoredSubjectsForAverage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = vm.page;
    final width = MediaQuery.sizeOf(context).width;
    final columns = DashboardColumns.forWindow(width);
    final wide = width >= tabletLayoutBreakpoint;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GradesPageHeader(
        semester: page.showSemester,
        onSemesterChanged: callbacks.changeSemester,
        onShowHistory: () => _showHistory(context),
        floatingMaxWidth: !wide
            ? null
            : columns == null
                ? DesignTokens.contentMaxWidth
                : DashboardColumns.maxWidth,
      ),
      body: DashboardBackdrop(
        child: Builder(
          builder: (context) {
            final top = MediaQuery.paddingOf(context).top;
            return Stack(
              children: [
                // Above this, slim rows would no longer be slim, and no system
                // setting of the phones in use asks for more.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 2,
                  child: Builder(
                    builder: (context) => _body(context, columns, wide: wide),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: AnimatedLinearProgressIndicator(show: page.loading),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    DashboardColumns? columns, {
    required bool wide,
  }) {
    final page = vm.page;
    if (!page.hasData && page.noInternet) {
      return GradesStateCard(
        key: const Key('grades-offline'),
        icon: Icons.wifi_off_rounded,
        title: context.t('offline.title'),
        body: context.t('offline.body'),
        actionLabel: context.t('common.retry'),
        onAction: callbacks.retry,
      );
    }
    if (!page.hasData && !page.loading) {
      return GradesStateCard(
        key: const Key('grades-empty'),
        icon: Icons.auto_graph_rounded,
        title: context.t('grades.empty.title'),
        body: context.t('grades.empty.body'),
      );
    }
    final Widget side, main;
    if (page.hasData) {
      side = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (page.noInternet)
            _OfflineHint(
              message: page.lastFetchedMessage ?? context.t('offline.title'),
              onRetry: callbacks.retry,
            ),
          _Summary(
            vm: vm,
            callbacks: callbacks,
            chartHeight: wide ? 170 : 128,
          ),
        ],
      );
      main = GradesSubjectList(
        vm: vm.list,
        colorGrades: vm.colorGrades,
        viewSubjectDetail: callbacks.viewSubjectDetail,
        onOpenDisplayOptions: () => showGradesDisplayPanel(
          context,
          onShowAverageSettings: callbacks.showGradesSettings,
        ),
      );
    } else {
      side = const _SummarySkeleton();
      main = const _SubjectsSkeleton();
    }
    const gutter = EdgeInsets.fromLTRB(
      DesignTokens.gutter,
      8,
      DesignTokens.gutter,
      DesignTokens.gutter,
    );
    if (columns != null) {
      return DashboardColumnsView(
        columns: columns,
        side: Padding(padding: gutter, child: side),
        main: Builder(
          builder: (context) => ListView(
            key: const Key('grades-list'),
            padding: columns.listPadding(MediaQuery.paddingOf(context)),
            children: [Padding(padding: gutter, child: main)],
          ),
        ),
      );
    }
    final padding = MediaQuery.paddingOf(context);
    return ReadableContent(
      maxWidth: DesignTokens.contentMaxWidth,
      child: ListView(
        key: const Key('grades-list'),
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        children: [
          Padding(
            padding: gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [side, main],
            ),
          ),
        ],
      ),
    );
  }
}

/// A message instead of the grades, in the middle of the page.
class GradesStateCard extends StatelessWidget {
  const GradesStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title, body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final actionLabel = this.actionLabel;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          padding.top + 8,
          DesignTokens.gutter,
          padding.bottom + 8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: scheme.primaryContainer,
                    shape: const CircleBorder(),
                  ),
                  child: SizedBox.square(
                    dimension: 56,
                    child: Icon(icon, color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAction,
                    style: glassControlStyle(scheme),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// That these grades are from an earlier visit, and how to try again.
class _OfflineHint extends StatelessWidget {
  const _OfflineHint({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        key: const Key('grades-last-fetched'),
        padding: const EdgeInsets.only(left: 12, right: 2),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: context.t('common.retry'),
              onPressed: onRetry,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet bar in place of text that is on its way. It stands still, the bar
/// below the header shows that something is happening.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width, height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        key: const Key('grades-loading'),
        label: context.t('grades.loading'),
        liveRegion: true,
        excludeSemantics: true,
        child: const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBar(width: 72, height: 12),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _SkeletonBar(width: 76, height: 36),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _SkeletonBar(width: 76, height: 36),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _SkeletonBar(width: double.infinity, height: 28),
              ],
            ),
          ),
        ),
      );
}

class _SubjectsSkeleton extends StatelessWidget {
  const _SubjectsSkeleton();

  static const _rows = 7;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Column(
        children: [
          for (var row = 0; row < _rows; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surfaceContainerLowest,
                  shape: StadiumBorder(
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: SizedBox(
                  height: compactRowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const _SkeletonBar(width: 28, height: 28),
                        const SizedBox(width: 8),
                        _SkeletonBar(width: 88.0 + row % 3 * 24, height: 12),
                        const Spacer(),
                        const _SkeletonBar(width: 48, height: 22),
                        const SizedBox(width: 26),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The cards above the subjects, or beside them in a wide window.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.vm,
    required this.callbacks,
    required this.chartHeight,
  });

  final NewGradesViewModel vm;
  final GradesPageCallbacks callbacks;
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    final page = vm.page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (page.showAllSubjectsAverage)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // Demo mode moves the clock, and with it the forecast.
            child: AnimatedBuilder(
              animation: appClock,
              builder: (context, _) => GradesOverviewCard(
                semester: page.showSemester,
                average: page.allSubjectsAverage,
                certificateAverage: page.certificateAverage,
                colorGrades: vm.colorGrades,
                forecast: calculateGradeForecast(
                  subjects: vm.list.subjects,
                  semester: page.showSemester,
                  ignoredSubjects: vm.list.ignoredSubjectsForAverage,
                ),
              ),
            ),
          ),
        if (page.showGradesDiagram)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GradesChartCard(
              onOpen: callbacks.showGradesChart,
              chartHeight: chartHeight,
            ),
          ),
        // Demo mode moves the clock, and with it what counts for the statistics.
        AnimatedBuilder(
          animation: appClock,
          builder: (context, _) => _Insights(vm: vm, callbacks: callbacks),
        ),
      ],
    );
  }
}

/// Statistics and the calculators.
class _Insights extends StatelessWidget {
  const _Insights({required this.vm, required this.callbacks});

  final NewGradesViewModel vm;
  final GradesPageCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statistics = calculateGradeStatistics(
      subjects: vm.list.subjects,
      semester: vm.page.showSemester,
      ignoredSubjects: vm.list.ignoredSubjectsForAverage,
    );
    final best = statistics.subjectAverages.firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GradesInsightTile(
                key: const Key('grades-statistics'),
                icon: Icons.bar_chart_rounded,
                title: l10n.text('grades.statistics'),
                subtitle: best == null
                    ? l10n.text('grades.statistics.subtitle')
                    : l10n.text(
                        'grades.statistics.best',
                        args: {
                          'subject': l10n.translateSubjectName(best.name),
                        },
                      ),
                onTap: () => showStatisticsPanel(
                  context,
                  statistics: statistics,
                  colorGrades: vm.colorGrades,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GradesInsightTile(
                key: const Key('grades-calculator'),
                icon: Icons.calculate_outlined,
                title: l10n.text('grades.calculator'),
                subtitle: l10n.text('grades.calculator.subtitle'),
                onTap: callbacks.showGradeCalculator,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
