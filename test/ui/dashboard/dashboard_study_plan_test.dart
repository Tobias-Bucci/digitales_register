import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/dashboard_study_plan.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() => bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 20)));
  tearDown(resetTestState);

  testWidgets('optional card shows today and saved custom phase progress',
      (tester) async {
    appClock.setDemoMode(true);
    await appClock.setSimulatedDate(DateTime(2026, 4, 20));
    final store = createStore(initialState: AppState((b) {
      b.settingsState.dashboardItems = ListBuilder(['studyPlan']);
      b.settingsState.assessmentStudyPhases['assessment-7'] =
          '[{"id":"custom","title":"Lesen","date":"2026-04-20"}]';
      b.settingsState.assessmentStudyProgress['assessment-7'] = 'custom';
      b.dashboardState.allDays = ListBuilder([
        for (final day in [19, 20, 21])
          buildDay(date: UtcDateTime(2026, 4, day), homework: [
            buildHomework(
              id: day == 20 ? 7 : day,
              title: 'Test',
              subtitle: 'Prüfung $day',
              type: HomeworkType.gradeGroup,
            ),
          ]),
      ]);
    }));
    await pumpApp(tester,
        store: store,
        home: const Scaffold(
            body: DashboardOverview(
                timeline: SchoolTimeline(holidays: [], gradeDeadlines: []))));
    expect(find.text('Prüfung 20'), findsOneWidget);
    expect(find.textContaining('1 von 1 Lernphasen erledigt'), findsOneWidget);
    expect(find.text('Prüfung 19'), findsNothing);
    await tester.tap(find.text('Lernplan'));
    await settleFor(tester);
    expect(find.byType(ExamCalendarPage), findsOneWidget);
  });

  testWidgets('card stays optional and is available with no upcoming exams',
      (tester) async {
    final store = createStore();
    const overview = Scaffold(
        body: DashboardOverview(
            timeline: SchoolTimeline(holidays: [], gradeDeadlines: [])));
    await pumpApp(tester, store: store, home: overview);
    expect(find.byType(DashboardStudyPlanCard), findsNothing);
    await store.actions.settingsActions.setDashboardConfiguration(
        DashboardConfiguration(items: ['studyPlan']));
    await settleFor(tester);
    expect(find.text('Keine anstehenden Prüfungen'), findsOneWidget);
    await store.actions.settingsActions
        .setDashboardConfiguration(DashboardConfiguration(items: []));
    await settleFor(tester);
    expect(find.byType(DashboardStudyPlanCard), findsNothing);
  });
}
