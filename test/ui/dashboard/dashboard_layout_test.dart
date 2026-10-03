import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/ui/dashboard_customize_dialog.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

const _timeline = SchoolTimeline(holidays: [], gradeDeadlines: []);

Finder _card(String id) => find.byKey(ValueKey('dashboard-item-$id'));

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  Future<void> pumpLayout(
    WidgetTester tester, {
    required List<String> items,
    Map<String, int> spans = const {},
    double width = 800,
    double scale = 1,
    String language = 'de',
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore(
        initialState: AppState((b) => b.settingsState
          ..dashboardItems = ListBuilder(items)
          ..dashboardItemSpans = MapBuilder(spans)
          ..languageCode = language));
    await pumpApp(tester,
        store: store,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: SingleChildScrollView(
                  child: DashboardOverview(timeline: _timeline))),
        ));
    await settleFor(tester);
  }

  testWidgets('two half-width cards share a row', (tester) async {
    await pumpLayout(tester,
        items: defaultDashboardItems,
        spans: {'holidays': 1, 'gradingDeadline': 1});
    final first = tester.getRect(_card('holidays'));
    final second = tester.getRect(_card('gradingDeadline'));
    expect(first.width, 395);
    expect(second.width, 395);
    expect(second.top, first.top);
    expect(second.height, first.height);
    expect(second.left - first.right, 10);
    expect(second.right, 800);
  });

  for (final scenario in [
    (320.0, 1.0, 'de'),
    (360.0, 1.15, 'de'),
    (393.4, 1.2, 'it'),
  ]) {
    testWidgets(
        'holidays and absences share a row in the actual phone dashboard $scenario',
        (tester) async {
      tester.view.physicalSize = Size(scenario.$1, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(initialState: AppState((b) {
        b.settingsState
          ..languageCode = scenario.$3
          ..dashboardItems = ListBuilder(['holidays', 'absences'])
          ..dashboardItemSpans = MapBuilder({'holidays': 1, 'absences': 1});
        b.absencesState.statistic
          ..counter = 12
          ..notJustified = 3;
      }));
      await pumpApp(tester,
          store: store,
          home: Builder(
              builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scenario.$2)),
                  child: DaysContainer())));
      await settleFor(tester);
      final holiday = tester.getRect(_card('holidays'));
      final absences = tester.getRect(_card('absences'));
      expect(absences.top, holiday.top);
      expect(absences.height, holiday.height);
      expect(absences.left, closeTo(holiday.right + 10, 0.001));
      expect(holiday.width, lessThan(scenario.$1 / 2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'phone editor saves and reloads holidays and absences side by side',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore(
        withMiddleware: true,
        initialState: AppState((b) => b.settingsState.dashboardItems =
            ListBuilder(['holidays', 'absences'])));
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    await tester.tap(find.byTooltip('Dashboard anpassen'));
    await settleFor(tester);
    for (final id in ['holidays', 'absences']) {
      final choice = find.byKey(ValueKey('dashboard-width-$id-1'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
    }
    await tester.tap(find.text('Speichern'));
    await settleFor(tester);
    expect(tester.getTopLeft(_card('absences')).dy,
        tester.getTopLeft(_card('holidays')).dy);
    final saved = await SettingsPersistenceService().load();
    expect(saved?.dashboardItemSpans.toMap(), {'holidays': 1, 'absences': 1});
    final restored = createStore(
        initialState:
            AppState((b) => b.settingsState.replace(saved ?? SettingsState())));
    await pumpApp(tester,
        store: restored,
        home: KeyedSubtree(
            key: const ValueKey('restored-phone-dashboard'),
            child: DaysContainer()));
    await settleFor(tester);
    expect(tester.getTopLeft(_card('absences')).dy,
        tester.getTopLeft(_card('holidays')).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-width cards stack using all available space',
      (tester) async {
    await pumpLayout(tester,
        items: defaultDashboardItems,
        spans: {'holidays': 2, 'gradingDeadline': 2});
    final first = tester.getRect(_card('holidays'));
    final second = tester.getRect(_card('gradingDeadline'));
    expect(first.width, 800);
    expect(second.width, 800);
    expect(second.top, first.bottom + 10);
  });

  testWidgets(
      'third automatic card fills its row and shares the half cards height',
      (tester) async {
    await pumpLayout(tester,
        items: [...defaultDashboardItems, 'absences'],
        spans: {'holidays': 1, 'gradingDeadline': 1});
    final holiday = tester.getRect(_card('holidays'));
    final deadline = tester.getRect(_card('gradingDeadline'));
    final absences = tester.getRect(_card('absences'));
    expect(deadline.top, holiday.top);
    expect(deadline.height, holiday.height);
    expect(absences.top, holiday.bottom + 10);
    expect(absences.width, 800);
    expect(absences.height, holiday.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'card heights remain unchanged across automatic, half and full width',
      (tester) async {
    double? previousHeight;
    final ids = DashboardItem.values.map((item) => item.id).toList();
    final store = createStore(
        initialState:
            AppState((b) => b.settingsState.dashboardItems = ListBuilder(ids)));
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: SingleChildScrollView(
                child: DashboardOverview(timeline: _timeline))));
    for (final mode in DashboardItemWidth.values) {
      await store.actions.settingsActions.setDashboardConfiguration(
          DashboardConfiguration(
              items: ids, spans: {for (final id in ids) id: mode.span}));
      await settleFor(tester);
      final sizes = ids.map((id) => tester.getSize(_card(id))).toList();
      final expectedWidth = switch (mode) {
        DashboardItemWidth.full => 800.0,
        DashboardItemWidth.half => 395.0,
        DashboardItemWidth.automatic => 260.0,
      };
      for (final size in sizes) {
        expect(size.width, expectedWidth);
        previousHeight ??= size.height;
        expect(size.height, previousHeight);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('full card followed by two half cards forms two rows',
      (tester) async {
    await pumpLayout(tester,
        items: ['absences', ...defaultDashboardItems],
        spans: {'absences': 2, 'holidays': 1, 'gradingDeadline': 1});
    final full = tester.getRect(_card('absences'));
    final first = tester.getRect(_card('holidays'));
    final second = tester.getRect(_card('gradingDeadline'));
    expect(full.width, 800);
    expect(first.top, full.bottom + 10);
    expect(second.top, first.top);
    expect(first.width, 395);
    expect(second.width, 395);
  });

  testWidgets('half/full/half preserves order without filling earlier gaps',
      (tester) async {
    await pumpLayout(tester,
        items: ['holidays', 'absences', 'gradingDeadline'],
        spans: {'absences': 2, 'holidays': 1, 'gradingDeadline': 1});
    final first = tester.getRect(_card('holidays'));
    final full = tester.getRect(_card('absences'));
    final last = tester.getRect(_card('gradingDeadline'));
    expect(first.width, 395);
    expect(full.top, first.bottom + 10);
    expect(full.width, 800);
    expect(last.top, full.bottom + 10);
    expect(last.width, 395);
  });

  testWidgets('an explicit half width remains half for a single card',
      (tester) async {
    await pumpLayout(tester, items: ['absences'], spans: {'absences': 1});
    expect(tester.getSize(_card('absences')).width, 395);
  });

  testWidgets('automatic and half widths share a row beside full cards',
      (tester) async {
    await pumpLayout(tester,
        items: ['absences', ...defaultDashboardItems],
        spans: {'absences': 2, 'holidays': 1});
    expect(tester.getSize(_card('gradingDeadline')).width, 395);
    expect(tester.getTopLeft(_card('gradingDeadline')).dy,
        tester.getTopLeft(_card('holidays')).dy);
  });

  for (final scenario in [(240.0, 1.0), (480.0, 2.0)]) {
    testWidgets('half widths stack safely at width/scale $scenario',
        (tester) async {
      await pumpLayout(tester,
          items: defaultDashboardItems,
          spans: {'holidays': 1, 'gradingDeadline': 1},
          width: scenario.$1,
          scale: scenario.$2);
      expect(tester.getSize(_card('holidays')).width, scenario.$1);
      expect(tester.getSize(_card('gradingDeadline')).width, scenario.$1);
      expect(tester.getTopLeft(_card('gradingDeadline')).dy,
          greaterThan(tester.getTopLeft(_card('holidays')).dy));
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['de', 'it']) {
    testWidgets(
        'long $language card text fits requested widths and large fonts',
        (tester) async {
      await pumpLayout(tester,
          items: ['holidays', 'gradingDeadline', 'absences'],
          spans: {'holidays': 1, 'gradingDeadline': 1, 'absences': 2},
          width: 720,
          scale: 2,
          language: language);
      expect(find.byType(DashboardSummaryCard), findsNWidgets(3));
      expect(tester.getSize(_card('holidays')).width, 355);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor saves chosen widths', (tester) async {
    DashboardConfiguration? saved;
    await pumpApp(tester,
        store: createStore(),
        home: Scaffold(
          body: DashboardCustomizeDialog(
              items: defaultDashboardItems,
              spans: const {'holidays': 1},
              onSave: (config) async {
                saved = config;
              }),
        ));
    await tester.tap(find.byKey(const ValueKey('dashboard-width-holidays-2')));
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(saved?.spans, {'holidays': 2});
    expect(saved?.items, defaultDashboardItems);
  });

  testWidgets('dashboard editor applies and persists widths through Redux',
      (tester) async {
    final store = createStore(withMiddleware: true);
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: SingleChildScrollView(
          child: Column(children: const [
            DashboardCustomizeButton(),
            DashboardOverview(timeline: _timeline)
          ]),
        )));
    await tester.tap(find.byTooltip('Dashboard anpassen'));
    await settleFor(tester);
    await tester.tap(find.byKey(const ValueKey('dashboard-width-holidays-2')));
    await tester.tap(find.text('Speichern'));
    await settleFor(tester);
    expect(store.state.settingsState.dashboardItemSpans['holidays'], 2);
    final loaded = await SettingsPersistenceService().load();
    expect(loaded?.dashboardItemSpans['holidays'], 2);
    expect(tester.getSize(_card('holidays')).width, 800);
    expect(tester.getSize(_card('gradingDeadline')).width, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset clears draft widths and saves the automatic defaults',
      (tester) async {
    DashboardConfiguration? saved;
    await pumpApp(tester,
        store: createStore(),
        home: Scaffold(
          body: DashboardCustomizeDialog(
              items: ['absences', 'holidays'],
              spans: const {'absences': 2, 'holidays': 1},
              onSave: (config) async {
                saved = config;
              }),
        ));
    await tester.ensureVisible(find.text('Standard wiederherstellen'));
    await tester.tap(find.text('Standard wiederherstellen'));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    expect(saved?.items, defaultDashboardItems);
    expect(saved?.spans, isEmpty);
  });

  for (final language in ['de', 'it']) {
    testWidgets('width editor fits narrow screens in $language with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(
          initialState:
              AppState((b) => b.settingsState.languageCode = language));
      await pumpApp(tester,
          store: store,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
                body: DashboardCustomizeDialog(
                    items: defaultDashboardItems, onSave: (_) async {})),
          ));
      await settleFor(tester);
      expect(tester.takeException(), isNull);
      final chip = find.byKey(const ValueKey('dashboard-width-holidays-1'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (320.0, false),
    (800.0, false),
    (320.0, true),
    (800.0, true)
  ]) {
    final width = scenario.$1;
    testWidgets(
        'empty dashboard has identical padding at $width, favorites=${scenario.$2}',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(
          initialState: AppState(
              (b) => b.settingsState.dashboardItems = ListBuilder<String>()));
      await pumpApp(tester,
          store: store,
          home: Scaffold(
              body: SingleChildScrollView(
            child: DashboardHeader(
                future: true,
                onSwitchFuture: () {},
                favoriteSubjects: scenario.$2 ? const ['Mathematik'] : const [],
                selectedFavoriteSubject: null,
                onFavoriteSubjectChanged: (_) {},
                showEmptyDays: true,
                onShowEmptyDaysChanged: (_) {},
                subjectThemes: BuiltMap(),
                schoolTimeline: _timeline,
                openCalendarAt: (_) async {},
                editGradeDeadline: (_) async {}),
          )));
      await settleFor(tester);
      final box =
          tester.getRect(find.byKey(const ValueKey('dashboard-header-box')));
      final controls = tester
          .getRect(find.byKey(const ValueKey('dashboard-header-controls')));
      expect(controls.top - box.top, 7);
      expect(box.bottom - controls.bottom, 7);
      expect(box.height, controls.height + 14);
      expect(find.byType(SchoolCountdownOverview), findsNothing);
      expect(find.byType(FavoriteSubjectFilter),
          scenario.$2 ? findsOneWidget : findsNothing);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Vergangenheit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
