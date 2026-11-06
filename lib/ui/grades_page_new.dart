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
import 'package:dr/ui/dashboard_app_header.dart';
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
          child: Row(
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
              GlassSegmentedControl<Semester>(
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GradesPageHeader(
        semester: page.showSemester,
        onSemesterChanged: callbacks.changeSemester,
        onShowHistory: () => _showHistory(context),
        floatingMaxWidth: width < tabletLayoutBreakpoint
            ? null
            : DesignTokens.contentMaxWidth,
      ),
      body: DashboardBackdrop(
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return Stack(
              children: [
                ReadableContent(
                  maxWidth: DesignTokens.contentMaxWidth,
                  child: ListView(
                    padding: EdgeInsets.only(
                      top: padding.top + 8,
                      bottom: padding.bottom + 8,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.gutter,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Summary(vm: vm, callbacks: callbacks),
                            GradesSubjectList(
                              vm: vm.list,
                              colorGrades: vm.colorGrades,
                              viewSubjectDetail: callbacks.viewSubjectDetail,
                              onOpenDisplayOptions: () =>
                                  showGradesDisplayPanel(
                                context,
                                onShowAverageSettings:
                                    callbacks.showGradesSettings,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: padding.top),
                  child: AnimatedLinearProgressIndicator(show: page.loading),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The cards above the subjects, or beside them in a wide window.
class _Summary extends StatelessWidget {
  const _Summary({required this.vm, required this.callbacks});

  final NewGradesViewModel vm;
  final GradesPageCallbacks callbacks;

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
            child: GradesChartCard(onOpen: callbacks.showGradesChart),
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
