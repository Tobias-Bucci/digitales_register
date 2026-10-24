import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/dashboard_register_cards.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() => bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 20)));
  tearDown(resetTestState);

  AppState gradeState() => AppState((b) {
        b.gradesState.semester.replace(Semester.first);
        b.gradesState.subjects = ListBuilder([
          buildSubject(name: 'Mathematik', gradesAll: {
            Semester.first: BuiltList([
              buildGradeAll(date: UtcDateTime(2026, 4, 18), grade: 500),
              buildGradeAll(
                  date: UtcDateTime(2026, 4, 19),
                  grade: 600,
                  weightPercentage: 300),
              buildGradeAll(
                  date: UtcDateTime(2026, 4, 20), grade: 100, cancelled: true),
            ]),
            Semester.second: BuiltList([
              buildGradeAll(date: UtcDateTime(2026, 5, 1), grade: 900),
            ]),
          }),
          buildSubject(name: 'Deutsch', gradesAll: {
            Semester.first: BuiltList([
              buildGradeAll(date: UtcDateTime(2026, 4, 1), grade: 1000),
            ]),
          }),
        ]);
        b.settingsState.ignoreForGradesAverage = ListBuilder(['deutsch']);
        b.settingsState.colorGrades = true;
      });

  testWidgets(
      'average respects weights, exclusions and semester; colors follow settings',
      (tester) async {
    final store = createStore(initialState: gradeState());
    await pumpApp(tester,
        store: store, home: const Scaffold(body: DashboardGradeCard()));
    expect(find.text('5,75'), findsOneWidget);
    final badge = tester.widget<GradeBadge>(find.byType(GradeBadge));
    expect(badge.hundredths, 575);
    expect(badge.colorized, isTrue);
    await store.actions.settingsActions.colorGrades(false);
    await tester.pump();
    expect(
        tester.widget<GradeBadge>(find.byType(GradeBadge)).colorized, isFalse);
  });

  testWidgets(
      'recent grade ignores cancelled and missing values in selected semester',
      (tester) async {
    final store = createStore(
        initialState: gradeState().rebuild((b) {
      final subject = b.gradesState.subjects[0];
      b.gradesState.subjects[0] = subject.rebuild((s) {
        s.gradesAll[Semester.first] = BuiltList([
          ...subject.basicGrades(Semester.first)!,
          buildGradeAll(date: UtcDateTime(2026, 4, 21), grade: 0)
              .rebuild((g) => g.grade = null),
        ]);
      });
      b.noInternet = true;
    }));
    await pumpApp(tester,
        store: store,
        home: const Scaffold(body: DashboardGradeCard(recent: true)));
    expect(find.text('6'), findsOneWidget);
    expect(find.textContaining('Mathematik'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(tester.widget<GradeBadge>(find.byType(GradeBadge)).hundredths, 600);
  });

  testWidgets('missing grades offer loading route; loading keeps cached grades',
      (tester) async {
    final store = createStore();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: DashboardGradeCard()));
    expect(find.text('Keine Noten verfügbar'), findsOneWidget);
    expect(find.textContaining('Noten öffnen'), findsOneWidget);
    expect(
        tester
            .widget<DashboardSummaryCard>(find.byType(DashboardSummaryCard))
            .onTap,
        isNotNull);
    store.replaceState(AppState((b) => b.gradesState.loading = true));
    await settleFor(tester);
    expect(find.byType(DashboardLoadingCard), findsOneWidget);
    store.replaceState(
        gradeState().rebuild((b) => b.gradesState.loading = true));
    await settleFor(tester);
    expect(find.text('5,75'), findsOneWidget);
    expect(find.byType(DashboardLoadingCard), findsNothing);
  });

  testWidgets(
      'next assessment includes today, advances with clock and opens calendar',
      (tester) async {
    appClock.setDemoMode(true);
    await appClock.setSimulatedDate(DateTime(2026, 4, 20));
    final store = createStore(initialState: AppState((b) {
      b.dashboardState.allDays = ListBuilder([
        for (final day in [19, 20, 21])
          buildDay(date: UtcDateTime(2026, 4, day), homework: [
            buildHomework(
                id: day,
                title: 'Test',
                subtitle: 'Test $day',
                type: HomeworkType.gradeGroup),
          ]),
      ]);
    }));
    await pumpApp(tester,
        store: store,
        home: const Scaffold(body: DashboardNextAssessmentCard()));
    expect(find.text('Test 20'), findsOneWidget);
    expect(find.textContaining('Heute'), findsOneWidget);
    await appClock.setSimulatedDate(DateTime(2026, 4, 21));
    await tester.pump();
    expect(find.text('Test 21'), findsOneWidget);
    await tester.tap(find.byType(DashboardSummaryCard));
    await settleFor(tester);
    expect(find.byType(ExamCalendarPage), findsOneWidget);
  });

  testWidgets('new cards stay optional and persist order and width',
      (tester) async {
    final store = createStore(withMiddleware: true);
    await pumpApp(tester,
        store: store,
        home: const Scaffold(
            body: SingleChildScrollView(
                child: DashboardOverview(
                    timeline:
                        SchoolTimeline(holidays: [], gradeDeadlines: [])))));
    expect(find.byType(DashboardGradeCard), findsNothing);
    expect(find.byType(DashboardNextAssessmentCard), findsNothing);
    await store.actions.settingsActions.setDashboardConfiguration(
        DashboardConfiguration(
            items: ['recentGrade', 'nextAssessment', 'gradeAverage'],
            spans: {'recentGrade': 2, 'gradeAverage': 1}));
    await settleFor(tester);
    expect(find.byType(DashboardGradeCard), findsNWidgets(2));
    expect(find.byType(DashboardNextAssessmentCard), findsOneWidget);
    final loaded = await SettingsPersistenceService().load();
    expect(loaded!.dashboardItems.toList(),
        ['recentGrade', 'nextAssessment', 'gradeAverage']);
    expect(loaded.dashboardItemSpans.toMap(),
        {'recentGrade': 2, 'gradeAverage': 1});
  });

  for (final language in ['de', 'it', 'en', 'lld']) {
    testWidgets('populated grade cards fit narrow enlarged text in $language',
        (tester) async {
      tester.view.physicalSize = const Size(280, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(
          initialState: gradeState().rebuild((b) {
        b.settingsState.languageCode = language;
        b.settingsState.dashboardItems =
            ListBuilder(['gradeAverage', 'recentGrade', 'nextAssessment']);
      }));
      await pumpApp(tester,
          store: store,
          themeMode: ThemeMode.dark,
          home: const MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: DashboardOverview(
                          timeline: SchoolTimeline(
                              holidays: [], gradeDeadlines: []))))));
      await settleFor(tester);
      expect(find.byType(GradeBadge), findsNWidgets(2));
      expect(find.byType(DashboardSummaryCard), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
}
