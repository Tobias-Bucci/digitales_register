import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  test('legacy saved selection without spans keeps automatic sizing', () {
    final source = SettingsState(
        (b) => b.dashboardItems = ListBuilder(['absences', 'holidays']));
    final encoded = (serializers.serialize(source) as List).toList();
    final index = encoded.indexOf('dashboardItemSpans');
    encoded.removeRange(index, index + 2);
    final loaded = serializers.deserialize(encoded) as SettingsState;
    expect(loaded.dashboardItems.toList(), ['absences', 'holidays']);
    expect(loaded.dashboardItemSpans, isEmpty);
    expect(DashboardItemWidth.fromSpan(loaded.dashboardItemSpans['absences']),
        DashboardItemWidth.automatic);
  });

  test('layout, order and selection persist in one settings update', () async {
    final store = createStore(withMiddleware: true);
    await store.actions.settingsActions.setDashboardConfiguration(
      DashboardConfiguration(
          items: ['absences', 'holidays'],
          spans: {'absences': 2, 'holidays': 1, 'gradingDeadline': 2}),
    );
    final loaded = await SettingsPersistenceService().load();
    expect(loaded?.dashboardItems.toList(), ['absences', 'holidays']);
    expect(loaded?.dashboardItemSpans.toMap(),
        {'absences': 2, 'holidays': 1, 'gradingDeadline': 2});
    await store.actions.settingsActions.dashboardItems(BuiltList(['holidays']));
    await store.actions.settingsActions
        .dashboardItems(BuiltList(['holidays', 'absences']));
    expect(store.state.settingsState.dashboardItemSpans['absences'], 2);
    await store.actions.settingsActions.setDashboardConfiguration(
      DashboardConfiguration(items: defaultDashboardItems),
    );
    expect((await SettingsPersistenceService().load())?.dashboardItemSpans,
        isEmpty);
  });

  test('unrecognized spans and IDs safely fall back to automatic sizing', () {
    final config = DashboardConfiguration(
        items: ['holidays', 'unknown'],
        spans: {'holidays': 999, 'absences': -1, 'unknown': 2});
    expect(config.items, ['holidays']);
    expect(config.spans, isEmpty);
    expect(DashboardItemWidth.fromSpan(null), DashboardItemWidth.automatic);
    expect(DashboardItemWidth.fromSpan(999), DashboardItemWidth.automatic);
  });

  test('legacy settings without a configuration get the existing cards', () {
    final encoded = (serializers.serialize(SettingsState()) as List).toList();
    final index = encoded.indexOf('dashboardItems');
    encoded.removeRange(index, index + 2);
    final settings = serializers.deserialize(encoded) as SettingsState;
    expect(settings.dashboardItems.toList(), defaultDashboardItems);
  });

  test(
      'unknown and duplicate IDs are ignored, preserving order and empty lists',
      () {
    expect(
        resolveDashboardItems(['absences', 'future', 'holidays', 'absences']),
        [DashboardItem.absences, DashboardItem.holidays]);
    expect(resolveDashboardItems([]), isEmpty);
  });

  test('hide, add, reorder and reset update the existing Redux settings',
      () async {
    final store = createStore();
    await store.actions.settingsActions
        .dashboardItems(BuiltList(['gradingDeadline']));
    expect(
        store.state.settingsState.dashboardItems.toList(), ['gradingDeadline']);
    await store.actions.settingsActions
        .dashboardItems(BuiltList(['absences', 'gradingDeadline', 'holidays']));
    expect(store.state.settingsState.dashboardItems.first, 'absences');
    await store.actions.settingsActions
        .dashboardItems(BuiltList(['unknown', 'holidays', 'holidays']));
    expect(store.state.settingsState.dashboardItems.toList(), ['holidays']);
    await store.actions.settingsActions
        .dashboardItems(BuiltList(defaultDashboardItems));
    expect(store.state.settingsState.dashboardItems.toList(),
        defaultDashboardItems);
  });

  test('configuration is persisted by middleware and reloaded after restart',
      () async {
    final store = createStore(withMiddleware: true);
    await store.actions.settingsActions
        .dashboardItems(BuiltList(['absences', 'holidays']));
    final loaded = await SettingsPersistenceService().load();
    expect(loaded?.dashboardItems.toList(), ['absences', 'holidays']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(globalSettingsPreferenceKey),
        contains('dashboardItems'));
    await store.actions.settingsActions.dashboardItems(BuiltList<String>());
    expect(
        (await SettingsPersistenceService().load())?.dashboardItems, isEmpty);
  });

  test('absence loading and failure retain cached data; malformed data is safe',
      () async {
    final store = createStore(
        initialState: AppState((b) => b.absencesState.statistic.counter = 7));
    await store.actions.absencesActions.load();
    expect(store.state.absencesState.loading, isTrue);
    await store.actions.absencesActions.notLoaded();
    expect(store.state.absencesState.loading, isFalse);
    expect(store.state.absencesState.loadFailed, isTrue);
    expect(store.state.absencesState.statistic?.counter, 7);
    for (final payload in [
      null,
      {},
      {
        'statistics': {},
        'absences': [null],
        'futureAbsences': []
      }
    ]) {
      await store.actions.absencesActions.loaded(payload);
      expect(store.state.absencesState.loading, isFalse);
      expect(store.state.absencesState.loadFailed, isTrue);
      expect(store.state.absencesState.statistic?.counter, 7);
    }
    await store.actions.absencesActions.loaded({
      'statistics': {'counter': 0, 'notJustified': 0},
      'absences': [],
      'futureAbsences': [],
    });
    expect(store.state.absencesState.loadFailed, isFalse);
    expect(store.state.absencesState.statistic?.counter, 0);
  });
}
