import 'package:dr/assessment_attachments.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  testWidgets('week view shows multiple exams and opens their details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final firstAssessment = ExamAssessment(
      id: 'assessment-1',
      date: UtcDateTime(2026, 4, 20),
      subject: 'Deutsch',
      title: 'Lange Prüfung mit umfangreichem Stoff',
      material: null,
    );
    final secondAssessment = ExamAssessment(
      id: 'assessment-2',
      date: UtcDateTime(2026, 4, 20),
      subject: 'Mathematik',
      title: 'Trigonometrie',
      material: null,
    );

    await tester.pumpWidget(MaterialApp(
      home: ExamCalendarPage(
        assessments: [firstAssessment, secondAssessment],
        now: DateTime(2026, 4, 20),
        completedFor: (_) => <String>{},
        phasesFor: (_) => null,
        noteFor: (_) => null,
        attachmentsFor: (_) => const <AssessmentAttachment>[],
        onProgressChanged: (_, __) {},
        onPhasesChanged: (_, __) {},
        onNoteChanged: (_, __) {},
        onAttachmentsChanged: (_, __) {},
      ),
    ));

    await tester.tap(find.byKey(const Key('exam-calendar-week-view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('week-exam-assessment-1')), findsOneWidget);
    expect(find.byKey(const Key('week-exam-assessment-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('week-exam-assessment-2')));
    await tester.pumpAndSettle();
    expect(find.text('Prüfungsdetails'), findsOneWidget);
    expect(find.text('Trigonometrie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the phase editor keeps its text field valid',
      (tester) async {
    List<StudyPhase>? savedPhases;
    final assessment = ExamAssessment(
      id: 'assessment-1',
      date: UtcDateTime(2026, 4, 20),
      subject: 'Deutsch',
      title: 'Textanalyse',
      material: null,
    );

    await tester.pumpWidget(MaterialApp(
      home: ExamCalendarPage(
        assessments: [assessment],
        now: DateTime(2026, 4, 1),
        completedFor: (_) => <String>{},
        phasesFor: (_) => null,
        noteFor: (_) => null,
        attachmentsFor: (_) => const <AssessmentAttachment>[],
        onProgressChanged: (_, __) {},
        onPhasesChanged: (_, phases) => savedPhases = phases,
        onNoteChanged: (_, __) {},
        onAttachmentsChanged: (_, __) {},
      ),
    ));

    await tester.tap(find.text('Textanalyse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorbereitung starten').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Kapitel wiederholen');
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kapitel wiederholen'), findsOneWidget);
    expect(find.textContaining('Mittel'), findsWidgets);
    expect(savedPhases?.singleWhere((phase) => phase.id == 'start').title,
        'Kapitel wiederholen');
  });
}
