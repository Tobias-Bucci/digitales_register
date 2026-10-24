import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Both cards read the existing grade store. Opening the grades page uses its
/// normal cached load; displaying or reordering cards never issues requests.
class DashboardGradeCard extends StatelessWidget {
  const DashboardGradeCard({super.key, this.recent = false});
  final bool recent;

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, AppState>(
        connect: (state) => state,
        builder: (context, state, actions) {
          final grades = state.gradesState;
          final title = context
              .t(recent ? 'dashboard.recentGrade.title' : 'grades.average');
          if (grades.loading && grades.subjects.isEmpty) {
            return DashboardLoadingCard(title: title);
          }
          Subject? latestSubject;
          GradeAll? latest;
          if (recent) {
            for (final subject in grades.subjects) {
              for (final grade in subject.basicGrades(grades.semester) ??
                  const <GradeAll>[]) {
                if (!grade.cancelled &&
                    grade.grade != null &&
                    (latest == null || grade.date.isAfter(latest.date))) {
                  latest = grade;
                  latestSubject = subject;
                }
              }
            }
          }
          final average = recent ? null : overallGradeAverage(state);
          final hundredths = recent
              ? latest?.grade
              : average == null
                  ? null
                  : average * 100;
          final text = recent
              ? latest == null
                  ? null
                  : formatGradeFromInt(latest.grade)
              : average == null
                  ? null
                  : appSelectors.allSubjectsAverage(state);
          final semester = context.l10n.semesterLabel(grades.semester);
          final details = recent && latest != null
              ? '${context.l10n.translateSubjectName(latestSubject!.name)} · '
                  '${MaterialLocalizations.of(context).formatMediumDate(latest.date)}\n$semester'
              : semester;
          return DashboardSummaryCard(
            icon: recent ? Icons.history_edu_rounded : Icons.calculate_outlined,
            title: title,
            primaryText: text ?? context.t('dashboard.grades.empty'),
            primaryContent: text == null
                ? null
                : GradeBadge(
                    text: text,
                    hundredths: hundredths,
                    colorized: state.settingsState.colorGrades,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
            secondaryText: [
              details,
              if (text == null) context.t('dashboard.grades.open'),
              if (state.noInternet) context.t('dashboard.customize.offline'),
            ].join('\n'),
            onTap: actions.routingActions.showGrades.call,
          );
        },
      );
}

/// Reuses the assessment projection shared by the calendar and study plan.
class DashboardNextAssessmentCard extends StatelessWidget {
  const DashboardNextAssessmentCard({super.key});

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, AppState>(
        connect: (state) => state,
        builder: (context, state, actions) => AnimatedBuilder(
          animation: appClock,
          builder: (context, _) {
            final next = examAssessments(state)
                .where((entry) => entry.daysUntil(appClock.now) >= 0)
                .firstOrNull;
            final title = context.t('dashboard.nextAssessment.title');
            if (next == null && state.dashboardState.loading) {
              return DashboardLoadingCard(title: title);
            }
            final days = next?.daysUntil(appClock.now);
            return DashboardSummaryCard(
              icon: Icons.event_note_rounded,
              title: title,
              primaryText:
                  next?.title ?? context.t('dashboard.studyPlan.empty'),
              secondaryText: [
                if (next != null) ...[
                  if (next.subject != null)
                    context.l10n.translateSubjectName(next.subject!),
                  MaterialLocalizations.of(context).formatMediumDate(next.date),
                  context.l10n.assessmentCountdown(days!),
                ] else
                  context.t('dashboard.studyPlan.open'),
                if (state.noInternet) context.t('dashboard.customize.offline'),
              ].join('\n'),
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) =>
                      const ExamCalendarContainer(calendarView: true))),
            );
          },
        ),
      );
}
