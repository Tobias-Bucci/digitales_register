import 'dart:async';
import 'package:dr/app_clock.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';

/// Uses the real exam UI when there are no upcoming exams to explain.
class TutorialExamExample extends StatefulWidget {
  const TutorialExamExample({super.key});
  @override
  State<TutorialExamExample> createState() => _TutorialExamExampleState();
}

class _TutorialExamExampleState extends State<TutorialExamExample> {
  Set<String> completed = {};
  String? phases;
  String? note;
  List<AssessmentAttachment> attachments = [];
  @override
  void dispose() {
    // Only copies explicitly imported into this disposable example.
    for (final attachment in attachments) {
      unawaited(
          removeAssessmentAttachment(attachment).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExamCalendarPage(
        assessments: [
          ExamAssessment(
            id: 'tutorial-example',
            date:
                UtcDateTime.makeUtc(appClock.now.add(const Duration(days: 7))),
            subject: null,
            title: tutorialService.text('practice'),
            material: tutorialService.text('example'),
            type: 'CW',
          )
        ],
        now: appClock.now,
        completedFor: (_) => completed,
        phasesFor: (_) => phases,
        noteFor: (_) => note,
        attachmentsFor: (_) => attachments,
        onProgressChanged: (_, value) {
          if (mounted) setState(() => completed = {...value});
        },
        onPhasesChanged: (_, value) {
          if (mounted) setState(() => phases = encodeStudyPhases(value));
        },
        onNoteChanged: (_, value) {
          note = value;
        },
        onAttachmentsChanged: (_, value) {
          attachments = value;
        },
      );
}
