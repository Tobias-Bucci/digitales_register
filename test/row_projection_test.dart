import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/container/calendar_card_container.dart';
import 'package:dr/container/calendar_detail_container.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

AbsenceGroup _group(int day, String note) => AbsenceGroup(
      (g) => g
        ..date = UtcDateTime(2026, 10, day)
        ..hours = 1
        ..minutes = 0
        ..note = note
        ..justified = AbsenceJustified.justified
        ..absences.replace([
          Absence(
            (a) => a
              ..date = UtcDateTime(2026, 10, day)
              ..hour = 1
              ..minutes = 50
              ..minutesCameTooLate = 0
              ..minutesLeftTooEarly = 0,
          ),
        ]),
    );

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('calendar rows', () {
    final day = UtcDateTime(2026, 10, 20);
    AppState withHours(List<String> subjects) => AppState(
          (b) => b
            ..settingsState.languageCode = 'en'
            ..calendarState.days[day] = buildCalendarDay(
              date: day,
              hours: [
                for (var i = 0; i < subjects.length; i++)
                  buildCalendarHour(
                      subject: subjects[i], fromHour: i + 1, toHour: i + 1),
              ],
            ),
        );

    Future<Store<AppState, AppStateBuilder, AppActions>> pumpDay(
        WidgetTester tester) async {
      final store =
          createStore(initialState: withHours(['Synthetic A', 'Synthetic B']));
      await pumpApp(tester,
          store: store,
          home: CalendarDetailItemContainer(date: day, isSidebar: false));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic B'), findsOneWidget);
      return store;
    }

    test('U09 the row mapper tolerates a shortened day', () {
      final row = CalendarCardContainer(hourIndex: 1, day: day);
      final connection = row.build(_FakeContext())
          as StoreConnection<AppState, AppActions, CalendarCardViewModel?>;
      // ignore: invalid_use_of_protected_member
      expect(connection.connect(withHours(['Synthetic A'])), isNull);
      // ignore: invalid_use_of_protected_member
      expect(connection.connect(AppState()), isNull);
      // ignore: invalid_use_of_protected_member
      expect(
          connection
              .connect(withHours(['Synthetic A', 'Synthetic B']))!
              .hour
              .subject,
          'Synthetic B');
    });

    for (final remaining in [
      ['Synthetic A'],
      <String>[],
    ]) {
      testWidgets('refreshing to ${remaining.length} lessons removes the rows',
          (tester) async {
        final store = await pumpDay(tester);
        await store.actions.mountAppState(withHours(remaining));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Synthetic B'), findsNothing);
        expect(find.text('Synthetic A'),
            remaining.isEmpty ? findsNothing : findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await store.dispose();
      });
    }

    testWidgets('a removed day leaves no stale rows', (tester) async {
      final store = await pumpDay(tester);
      await store.actions
          .mountAppState(AppState((b) => b..settingsState.languageCode = 'en'));
      // Without the day the page shows its (endless) loading indicator.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Synthetic B'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    });
  });

  group('absence rows', () {
    AppState withGroups(List<AbsenceGroup> groups) => AppState(
          (b) => b
            ..settingsState.languageCode = 'en'
            ..absencesState.absences.replace(groups),
        );

    testWidgets('a mounted row tolerates merged absence groups',
        (tester) async {
      final store = createStore(
          initialState:
              withGroups([_group(5, 'Synthetic first'), _group(6, 'Second')]));
      await pumpApp(tester,
          store: store,
          home: const Column(children: [
            AbsenceGroupContainer(group: 0),
            AbsenceGroupContainer(group: 1),
          ]));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);

      // The refresh regroups both absences into a single group.
      await store.actions.mountAppState(withGroups([_group(5, 'Merged')]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Merged'), findsOneWidget);
      expect(find.text('Second'), findsNothing);

      await store.actions.mountAppState(withGroups([]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Merged'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    });

    testWidgets('a row shows the group its new index points to',
        (tester) async {
      final store = createStore(
          initialState:
              withGroups([_group(5, 'Synthetic first'), _group(6, 'Second')]));
      var index = 0;
      late StateSetter setIndex;
      await pumpApp(tester, store: store,
          home: StatefulBuilder(builder: (context, setState) {
        setIndex = setState;
        return AbsenceGroupContainer(group: index);
      }));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic first'), findsOneWidget);

      // Only the row's own configuration changes, not the store.
      setIndex(() => index = 1);
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Synthetic first'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    });
  });
}

class _FakeContext extends Fake implements BuildContext {}
