import 'package:dr/app_selectors.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('page and dashboard count entries despite a stale zero summary',
      (tester) async {
    final store = createStore();
    addTearDown(store.dispose);
    store.actions.absencesActions.loaded({
      'statistics': {'counter': 4, 'notJustified': 0},
      'absences': [
        {
          'date': '2026-10-01',
          'justified': '2',
          'group': [
            for (var i = 1; i <= 4; i++)
              {
                'id': i,
                'date': '2026-10-01',
                'hour': i,
                'minutes': 50,
                'minutes_begin': 0,
                'minutes_end': 0,
                'justified': <Object>[2, ' 3 ', 1.0, 'forSchool'][i - 1],
              },
          ],
        },
      ],
      'futureAbsences': [],
    });
    expect(store.state.absencesState.loadFailed, isFalse);
    expect(
        appSelectors
            .absenceStatistics(store.state.absencesState)
            .statistic
            .notJustified,
        2);

    await pumpApp(tester, store: store, home: const AbsencesPageContainer());
    await tester.tap(find.text('Statistik'));
    await settleFor(tester);
    final metric = find
        .ancestor(
            of: find.text('Nicht entschuldigt'), matching: find.byType(Column))
        .first;
    expect(
        find.descendant(of: metric, matching: find.text('2')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpApp(tester,
        store: store,
        home: DashboardAbsencesCard(state: store.state.absencesState));
    await settleFor(tester);
    expect(find.text('4 Absenzen'), findsOneWidget);
    expect(find.text('2 nicht entschuldigt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
