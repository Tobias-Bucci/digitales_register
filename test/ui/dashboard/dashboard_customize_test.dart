import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/ui/dashboard_customize_dialog.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);
  const emptyTimeline = SchoolTimeline(holidays: [], gradeDeadlines: []);

  testWidgets('offline absences retain cached statistics', (tester) async {
    await pumpApp(tester,
        store: createStore(),
        home: DashboardAbsencesCard(
          noInternet: true,
          state: AbsencesState((b) => b.statistic
            ..counter = 5
            ..notJustified = 1),
        ));
    expect(find.text('5 Absenzen'), findsOneWidget);
    expect(find.text('Offline – gespeicherte Daten'), findsOneWidget);
    expect(find.byType(DashboardLoadingCard), findsNothing);
  });

  testWidgets('enabled absences load through the existing middleware',
      (tester) async {
    final pending = Completer<Object?>();
    final mock = MockWrapper();
    when(() => mock.noInternet).thenReturn(false);
    when(() => mock.send('api/student/dashboard/absences'))
        .thenAnswer((_) => pending.future);
    wrapper = mock;
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) {
          b.loginState.loggedIn = true;
          b.settingsState.dashboardItems = ListBuilder(['absences']);
        }));
    await pumpApp(tester,
        store: store,
        home: Scaffold(body: DashboardOverview(timeline: emptyTimeline)));
    await settleFor(tester);
    expect(find.byType(DashboardLoadingCard), findsOneWidget);
    pending.complete({
      'statistics': {'counter': 9, 'notJustified': 2},
      'absences': [],
      'futureAbsences': []
    });
    await settleFor(tester);
    expect(find.text('9 Absenzen'), findsOneWidget);
    expect(find.text('2 nicht entschuldigt'), findsOneWidget);
    verify(() => mock.send('api/student/dashboard/absences')).called(1);
  });

  testWidgets('failed absence loading stops the skeleton and supports retry',
      (tester) async {
    final mock = MockWrapper();
    var attempts = 0;
    when(() => mock.noInternet).thenReturn(false);
    when(() => mock.send('api/student/dashboard/absences'))
        .thenAnswer((_) async {
      attempts++;
      if (attempts == 1) throw StateError('connection failed');
      return {
        'statistics': {'counter': 0, 'notJustified': 0},
        'absences': [],
        'futureAbsences': []
      };
    });
    wrapper = mock;
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) {
          b.loginState.loggedIn = true;
          b.settingsState.dashboardItems = ListBuilder(['absences']);
        }));
    await pumpApp(tester,
        store: store,
        home: Scaffold(body: DashboardOverview(timeline: emptyTimeline)));
    await settleFor(tester);
    expect(store.state.absencesState.loadFailed, isTrue);
    expect(find.byType(DashboardLoadingCard), findsNothing);
    await tester.tap(find.byType(DashboardSummaryCard));
    await settleFor(tester);
    expect(attempts, 2);
    expect(find.text('0 Absenzen'), findsOneWidget);
    expect(store.state.absencesState.loadFailed, isFalse);
  });

  testWidgets('saving from the dashboard applies the selection and persists it',
      (tester) async {
    final store = createStore(withMiddleware: true);
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    await tester.tap(find.byTooltip('Dashboard anpassen'));
    await settleFor(tester);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Absenzen'));
    await tester.tap(find.widgetWithText(ListTile, 'Absenzen'));
    await tester.tap(find.text('Speichern'));
    await settleFor(tester);
    expect(find.byType(DashboardCustomizeDialog), findsNothing);
    expect(store.state.settingsState.dashboardItems.toList(),
        ['holidays', 'gradingDeadline', 'absences']);
    expect((await SettingsPersistenceService().load())?.dashboardItems.toList(),
        ['holidays', 'gradingDeadline', 'absences']);
  });

  testWidgets('a save error retains the draft for retry', (tester) async {
    var attempts = 0;
    await pumpApp(tester,
        store: createStore(),
        home: Scaffold(
          body: DashboardCustomizeDialog(
              items: defaultDashboardItems,
              onSave: (items) async {
                attempts++;
                if (attempts == 1) throw StateError('write failed');
              }),
        ));
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(find.byType(DashboardCustomizeDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('holidays')), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(attempts, 2);
  });

  testWidgets('nullable dashboard fields keep entries and filter functional',
      (tester) async {
    final store = createStore(
        initialState: AppState((b) => b.dashboardState
          ..blacklist = null
          ..allDays = null
          ..loading = true));
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardLoadingCard), findsOneWidget);
    await tester.tap(find.text('Filter'));
    await settleFor(tester);
    expect(find.text('Leere Tage anzeigen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single card fills the available dashboard width',
      (tester) async {
    final store = createStore(
        initialState: AppState(
            (b) => b.settingsState.dashboardItems = ListBuilder(['absences'])));
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: SizedBox(
                width: 600,
                child: DashboardOverview(timeline: emptyTimeline))));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('dashboard-item-absences')))
            .width,
        600);
  });

  testWidgets('Italian dark theme supports editing and absence data',
      (tester) async {
    final store = createStore(initialState: AppState((b) {
      b.settingsState.languageCode = 'it';
      b.settingsState.dashboardItems = ListBuilder(['absences']);
      b.absencesState.statistic
        ..counter = 4
        ..notJustified = 1;
    }));
    await pumpApp(tester,
        store: store, themeMode: ThemeMode.dark, home: DaysContainer());
    await settleFor(tester);
    expect(find.text('4 assenze'), findsOneWidget);
    await tester.tap(find.byTooltip('Personalizza dashboard'));
    await settleFor(tester);
    expect(find.byType(DashboardCustomizeDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor hides, adds, drags, resets and saves cards',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String>? saved;
    await pumpApp(tester,
        store: createStore(),
        home: Scaffold(
            body: DashboardCustomizeDialog(
          items: defaultDashboardItems,
          onSave: (items) async {
            saved = items.items;
          },
        )));
    await settleFor(tester);
    await tester.tap(find.byTooltip('Ausblenden').first);
    await tester.pump();
    expect(find.byKey(const ValueKey('holidays')), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Ferien'));
    await tester.tap(find.widgetWithText(ListTile, 'Ferien'));
    await tester.pump();
    expect(find.byKey(const ValueKey('holidays')), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Absenzen'));
    await tester.tap(find.widgetWithText(ListTile, 'Absenzen'));
    await tester.pump();
    final handle = find.descendant(
        of: find.byKey(const ValueKey('absences')),
        matching: find.byIcon(Icons.drag_handle_rounded));
    final target =
        tester.getTopLeft(find.byKey(const ValueKey('gradingDeadline')));
    final start = tester.getCenter(handle);
    final destination = Offset(start.dx, target.dy - 60);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    for (var step = 1; step <= 25; step++) {
      await gesture.moveTo(start + (destination - start) * (step / 25));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settleFor(tester);
    expect(
        tester.getCenter(find.byKey(const ValueKey('absences'))).dy,
        lessThan(tester
            .getCenter(find.byKey(const ValueKey('gradingDeadline')))
            .dy));
    await tester.tap(find.text('Standard wiederherstellen'));
    await tester.pump();
    expect(find.byKey(const ValueKey('absences')), findsNothing);
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(saved, defaultDashboardItems);
  });

  testWidgets('cancel leaves the current configuration unchanged',
      (tester) async {
    final store = createStore();
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    await tester.tap(find.byTooltip('Dashboard anpassen'));
    await settleFor(tester);
    await tester.tap(find.byTooltip('Ausblenden').first);
    await tester.tap(find.text('Abbrechen'));
    await settleFor(tester);
    expect(store.state.settingsState.dashboardItems.toList(),
        defaultDashboardItems);
  });

  testWidgets('saved order controls rendering and all cards can be hidden',
      (tester) async {
    final store = createStore(
        initialState: AppState((b) => b.settingsState.dashboardItems =
            ListBuilder(
                ['absences', 'gradingDeadline', 'unknown', 'holidays'])));
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: SingleChildScrollView(
                child: DashboardOverview(timeline: emptyTimeline))));
    await settleFor(tester);
    final keys = tester
        .widgetList<SizedBox>(find.byWidgetPredicate((widget) =>
            widget is SizedBox &&
            widget.key.toString().contains('dashboard-item-')))
        .map((widget) => widget.key)
        .toList();
    expect(keys, [
      const ValueKey('dashboard-item-absences'),
      const ValueKey('dashboard-item-gradingDeadline'),
      const ValueKey('dashboard-item-holidays')
    ]);
    await store.actions.settingsActions.dashboardItems(BuiltList<String>());
    await tester.pump();
    expect(find.byType(DashboardSummaryCard), findsNothing);
  });

  for (final entry in <String, AbsencesState>{
    'missing': AbsencesState(),
    'nullable': AbsencesState((b) => b.statistic.replace(AbsenceStatistic())),
    'empty': AbsencesState((b) => b.statistic
      ..counter = 0
      ..notJustified = 0),
    'populated': AbsencesState((b) => b.statistic
      ..counter = 12
      ..notJustified = 3),
    'loading': AbsencesState((b) => b.loading = true),
    'error': AbsencesState((b) => b.loadFailed = true),
  }.entries) {
    testWidgets('absences handle ${entry.key} data', (tester) async {
      await pumpApp(tester,
          store: createStore(),
          home: DashboardAbsencesCard(state: entry.value));
      await settleFor(tester);
      expect(tester.takeException(), isNull);
      if (entry.key == 'loading')
        expect(find.byType(DashboardLoadingCard), findsOneWidget);
      if (entry.key == 'empty') expect(find.text('0 Absenzen'), findsOneWidget);
      if (entry.key == 'populated') {
        expect(find.text('12 Absenzen'), findsOneWidget);
        expect(find.text('3 nicht entschuldigt'), findsOneWidget);
      }
    });
  }

  for (final width in [280.0, 360.0, 720.0]) {
    testWidgets('all widgets fit width $width with enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(
          initialState: AppState((b) => b.settingsState.dashboardItems =
              ListBuilder(DashboardItem.values.map((item) => item.id))));
      await pumpApp(tester,
          store: store,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: DashboardOverview(timeline: emptyTimeline))),
          ));
      await settleFor(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DashboardSummaryCard), findsNWidgets(3));
    });
  }
}
