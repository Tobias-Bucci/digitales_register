import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/grade_statistics.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'support/fixtures.dart';

void main() {
  tzdata.initializeTimeZones();
  setUpAll(() => initializeDateFormatting('de'));
  for (final zone in ['Europe/Rome', 'America/New_York']) {
    testWidgets('exam page separates past/today/tomorrow in $zone',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: ExamCalendarPage(
          assessments: [
            for (final day in [16, 17, 18])
              ExamAssessment(
                  id: '$day',
                  date: UtcDateTime(2026, 10, day),
                  subject: 'Math',
                  title: 'Exam $day',
                  material: null)
          ],
          now: tz.TZDateTime(tz.getLocation(zone), 2026, 10, 17),
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
      expect(find.text('Exam 16'), findsNothing);
      expect(find.text('Exam 17'), findsOneWidget);
      expect(find.text('Exam 18'), findsOneWidget);
      expect(find.text('Heute'), findsOneWidget);
      expect(find.text('Morgen'), findsOneWidget);
      expect(find.text('Vergangene Prüfungen (1)'), findsOneWidget);
      await tester.tap(find.text('Vergangene Prüfungen (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Exam 16'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final zone in ['Europe/Rome', 'UTC', 'America/New_York']) {
    final location = zone == 'UTC' ? tz.UTC : tz.getLocation(zone);
    for (final date in [
      DateTime.utc(2026, 10, 17),
      DateTime.utc(2026, 1, 17),
      DateTime.utc(2026, 3, 29),
      DateTime.utc(2026, 3, 30),
      DateTime.utc(2026, 10, 25),
      DateTime.utc(2026, 10, 26),
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 11, 1),
      DateTime.utc(2028, 2, 29),
      DateTime.utc(2028, 3, 1),
    ]) {
      final today = tz.TZDateTime(location, date.year, date.month, date.day);
      test('calendar differences and study plan: $zone $date', () {
        expect(calendarDate(today), date);
        for (final offset in [-10, -1, 0, 1, 10]) {
          final examDay = date.add(Duration(days: offset));
          final assessment = ExamAssessment(
            id: 'exam',
            date: UtcDateTime.makeUtc(examDay),
            subject: 'Math',
            title: 'Test',
            material: null,
          );
          expect(assessment.daysUntil(today), offset);
          expect(
              countdownLabel(assessment.daysUntil(today)),
              offset < 0
                  ? 'Vergangen'
                  : offset == 0
                      ? 'Heute'
                      : offset == 1
                          ? 'Morgen'
                          : 'Noch $offset Tage');
          for (final phase in studyPhases(assessment, today)) {
            expect(
                calendarDate(phase.date).isBefore(calendarDate(today)), false);
            if (offset > 0) {
              expect(calendarDate(phase.date).isBefore(examDay), true);
            }
          }
        }
      });
      // Four grades, with today's grade needed to pass the reliability gate.
      // Tomorrow's grade must be excluded even at local midnight in UTC minus.
      test('history/forecast/statistics agree: $zone $date', () {
        final grades = [
          for (final offset in [-3, -2, -1, 0, 1])
            buildGradeAll(
                date: UtcDateTime.makeUtc(date.add(Duration(days: offset))),
                grade: offset == 1 ? 1000 : 700),
        ];
        final subject = buildSubject(name: 'Math', gradesAll: {
          Semester.first: BuiltList<GradeAll>(grades),
          Semester.second: BuiltList<GradeAll>(grades),
        });
        final history = compareGradeSemesters(
            subjects: [subject],
            currentSemester: Semester.second,
            previousSemester: Semester.first,
            ignoredSubjects: [],
            now: today)!;
        final stats = calculateGradeStatistics(
            subjects: [subject],
            semester: Semester.first,
            ignoredSubjects: [],
            now: today);
        final forecast = calculateGradeForecast(
            subjects: [subject],
            semester: Semester.first,
            ignoredSubjects: [],
            now: today)!;
        expect(history.currentAverage, 700);
        expect(history.previousAverage, 700);
        expect(stats.subjectAverages.single.average, 700);
        expect(forecast.currentAverage, 700);
        expect(forecast.gradeCount, 4);
        expect(forecast.distinctDates, 4);
        expect(forecast.isReliable, true);
      });
    }
  }
  test('native local and UTC values retain their calendar components', () {
    expect(calendarDate(DateTime(2026, 10, 17)), DateTime.utc(2026, 10, 17));
    expect(
        calendarDaysBetween(UtcDateTime(2026, 10, 16), DateTime(2026, 10, 17)),
        -1);
  });
}
