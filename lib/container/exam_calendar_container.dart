import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class ExamCalendarContainer extends StatelessWidget {
  const ExamCalendarContainer({super.key});

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, AppState>(
        connect: (state) => state,
        builder: (context, state, actions) => AnimatedBuilder(
          animation: appClock,
          builder: (context, _) => ExamCalendarPage(
            assessments: examAssessments(state),
            now: studyPlanNow,
            completedFor: (id) => completedPhaseIds(state, id),
            phasesFor: (id) => state.settingsState.assessmentStudyPhases[id],
            noteFor: (id) => state.settingsState.assessmentStudyNotes[id],
            attachmentsFor: (id) => decodeAssessmentAttachments(
                state.settingsState.assessmentStudyAttachments[id]),
            onProgressChanged: (id, completed) => actions.settingsActions
                .setAssessmentStudyProgress(
                    MapEntry(id, encodeCompletedPhaseIds(completed))),
            onPhasesChanged: (id, phases) => actions.settingsActions
                .setAssessmentStudyPhases(
                    MapEntry(id, encodeStudyPhases(phases))),
            onNoteChanged: (id, note) => actions.settingsActions
                .setAssessmentStudyNote(MapEntry(id, note)),
            onAttachmentsChanged: (id, attachments) => actions.settingsActions
                .setAssessmentStudyAttachments(
                    MapEntry(id, encodeAssessmentAttachments(attachments))),
          ),
        ),
      );
}
