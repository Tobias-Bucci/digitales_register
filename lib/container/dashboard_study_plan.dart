import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

Future<void> _openStudyPlan(BuildContext context) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => const ExamCalendarContainer(calendarView: true),
    ));

/// Uses the same assessments and saved progress as the full study plan.
class DashboardStudyPlanCard extends StatelessWidget {
  const DashboardStudyPlanCard({super.key});

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, AppState>(
        connect: (state) => state,
        builder: (context, state, actions) => AnimatedBuilder(
          animation: appClock,
          builder: (context, _) {
            final now = appClock.now;
            final upcoming = examAssessments(state)
                .where((assessment) => assessment.daysUntil(now) >= 0);
            final next = upcoming.firstOrNull;
            final phases = next == null
                ? <StudyPhase>[]
                : studyPhases(next, now,
                    customPhases:
                        state.settingsState.assessmentStudyPhases[next.id]);
            final completed =
                next == null ? <String>{} : completedPhaseIds(state, next.id);
            final done = phases.where((p) => completed.contains(p.id)).length;
            return DashboardSummaryCard(
              icon: Icons.school_outlined,
              title: context.t('exam.plan'),
              primaryText:
                  next?.title ?? context.t('dashboard.studyPlan.empty'),
              secondaryText: next == null
                  ? context.t('dashboard.studyPlan.open')
                  : '${MaterialLocalizations.of(context).formatMediumDate(next.date)}'
                      '${next.subject == null ? '' : ' · ${next.subject}'}'
                      '\n${context.t('exam.progress', args: {
                          'done': '$done',
                          'total': '${phases.length}'
                        })}',
              onTap: () => _openStudyPlan(context),
            );
          },
        ),
      );
}
