import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

ExamAssessment exam(String id, int month, int day) => ExamAssessment(
      id: id,
      date: UtcDateTime(2026, month, day),
      subject: 'Mathematik',
      title: id,
      material: null,
    );

Future<void> openTimeline(WidgetTester tester, List<ExamAssessment> assessments,
    {double scale = 1, Locale locale = const Locale('de')}) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: ExamCalendarPage(
      assessments: assessments,
      now: DateTime(2026, 10, 24, 22),
      completedFor: (_) => {},
      phasesFor: (_) => null,
      noteFor: (_) => null,
      attachmentsFor: (_) => [],
      onProgressChanged: (_, __) {},
      onPhasesChanged: (_, __) {},
      onNoteChanged: (_, __) {},
      onAttachmentsChanged: (_, __) {},
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('exam-timeline-view')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets(
      'today includes multiple assessments, excludes the past and opens details',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openTimeline(tester, [
      exam('Yesterday', 10, 23),
      exam('Today A', 10, 24),
      exam('Today B', 10, 24),
    ]);
    expect(find.text('Today A'), findsOneWidget);
    expect(find.text('Today B'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
    expect(
        find.bySemanticsLabel(RegExp('.*Heute, 2 Prüfungen')), findsOneWidget);
    expect(
        tester.getSize(find.byKey(const Key('timeline-day-2026-10-24'))).width,
        tester.getSize(find.byKey(const Key('timeline-day-2026-10-25'))).width);
    await tester.ensureVisible(find.text('Today B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today B'));
    await tester.pumpAndSettle();
    expect(find.text('Prüfungsdetails'), findsOneWidget);
    Navigator.of(tester.element(find.text('Prüfungsdetails'))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exam-timeline')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'distant assessments across years are reachable and weeks remain proportional',
      (tester) async {
    final distant = ExamAssessment(
      id: 'far',
      date: UtcDateTime(2027, 1, 5),
      subject: null,
      title: 'January exam',
      material: null,
    );
    await openTimeline(tester, [distant, exam('Tomorrow', 10, 25)]);
    expect(find.text('Keine Prüfungen an diesem Tag'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timeline-day-2026-10-25')));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timeline-day-2026-10-26')));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsNothing);
    expect(find.text('Keine Prüfungen an diesem Tag'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timeline-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timeline-next-assessment')));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timeline-next-assessment')));
    await tester.pumpAndSettle();
    expect(find.text('January exam'), findsOneWidget);
    expect(find.byKey(const Key('timeline-day-2027-01-05')), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('timeline-next')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('timeline-previous')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline-day-2026-12-26')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timeline-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timeline-day-2026-10-24')), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('timeline-previous')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list and calendar stay available after using the timeline',
      (tester) async {
    await openTimeline(tester, [exam('Tomorrow', 10, 25)]);
    await tester.tap(find.byKey(const Key('exam-timeline-view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exam-timeline')), findsNothing);
    expect(find.text('Tomorrow'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exam-calendar-week-view')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('week-exam-Tomorrow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('empty timeline fits a small screen with large text in $locale',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openTimeline(tester, [exam('Past', 10, 23)],
          scale: 2, locale: locale);
      expect(find.text('Past'), findsNothing);
      expect(
          tester
              .widget<IconButton>(find.byKey(const Key('timeline-next')))
              .onPressed,
          isNull);
      await tester.drag(
          find.byKey(const Key('exam-timeline')), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
