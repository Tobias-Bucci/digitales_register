import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absences_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _monday = UtcDateTime(2026, 10, 19);
final _wednesday = UtcDateTime(2026, 10, 21);
final _friday = UtcDateTime(2026, 10, 23);
final _nextMonday = UtcDateTime(2026, 10, 26);

/// A day with [count] lessons; lesson i runs from (7 + i):[minute] for 45
/// minutes, so each day's labels are distinguishable by [minute].
CalendarDay _day(UtcDateTime date, int count, {int minute = 0}) =>
    buildCalendarDay(date: date, hours: [
      for (var i = 1; i <= count; i++)
        buildCalendarHour(
          subject: 'Synthetic math',
          fromHour: i,
          toHour: i,
          timeSpans: [
            buildTimeSpan(
              from: UtcDateTime(date.year, date.month, date.day, 7 + i, minute),
              to: UtcDateTime(
                  date.year, date.month, date.day, 7 + i, minute + 45),
            ),
          ],
        ),
    ]);

AppState _state(Map<UtcDateTime, CalendarDay> days) => AppState((b) => b
  ..settingsState.languageCode = 'en'
  ..absencesState.canEdit = true
  ..absencesState.statistic = AbsenceStatisticBuilder()
  ..calendarState.days.replace(days));

void main() {
  late List<Map<String, dynamic>> submitted;

  setUp(() async {
    submitted = [];
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 10, 19, 12));
  });

  tearDown(resetTestState);

  Future<Store<AppState, AppStateBuilder, AppActions>> openDialog(
      WidgetTester tester, Map<UtcDateTime, CalendarDay> days) async {
    final store = createStore(initialState: _state(days));
    addTearDown(store.dispose);
    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: AbsencesBody(
          state: store.state.absencesState,
          noInternet: false,
          onAddFutureAbsence: submitted.add,
          onRemoveFutureAbsence: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('Planned absence'));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> pickEndDay(WidgetTester tester, int day) async {
    await tester.tap(find.text('End date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$day').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  DropdownButton<int> dropdown(WidgetTester tester, {required bool end}) {
    final buttons = tester
        .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>));
    return end ? buttons.last : buttons.first;
  }

  List<int?> options(WidgetTester tester, {required bool end}) =>
      dropdown(tester, end: end).items!.map((item) => item.value).toList();

  Future<void> chooseEndHour(WidgetTester tester, int hour) async {
    await tester.tap(find.byType(DropdownButton<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(RegExp('^$hour \\(to ')).last);
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), 'Trip');
    await tester.enterText(find.byType(TextField).at(1), 'Parent');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(submitted, hasLength(1));
    return submitted.single['futureAbsence'] as Map<String, dynamic>;
  }

  testWidgets('Monday 8 to Friday 5 offers only Friday end periods',
      (tester) async {
    await openDialog(tester, {
      _monday: _day(_monday, 8, minute: 5),
      _friday: _day(_friday, 5, minute: 10),
    });
    expect(options(tester, end: true), [1, 2, 3, 4, 5, 6, 7, 8]);
    await chooseEndHour(tester, 8);

    await pickEndDay(tester, 23);

    expect(find.text('23.10.2026'), findsOneWidget);
    expect(options(tester, end: false), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(options(tester, end: true), [1, 2, 3, 4, 5]);
    // The Monday-only period 8 is revalidated to Friday's last period and the
    // label shows Friday's end time.
    expect(dropdown(tester, end: true).value, 5);
    expect(find.text('5 (12:55)'), findsOneWidget);
    expect(find.text('5 (12:50)'), findsNothing);

    final payload = await submit(tester);
    expect(payload['startDate'], '2026-10-19');
    expect(payload['endDate'], '2026-10-23');
    expect(payload['startTime'], 1);
    expect(payload['endTime'], 5);
  });

  testWidgets('Monday 5 to Friday 8 allows Friday period 8', (tester) async {
    await openDialog(tester, {
      _monday: _day(_monday, 5),
      _friday: _day(_friday, 8),
    });
    expect(options(tester, end: true), [1, 2, 3, 4, 5]);

    await pickEndDay(tester, 23);
    expect(options(tester, end: false), [1, 2, 3, 4, 5]);
    expect(options(tester, end: true), [1, 2, 3, 4, 5, 6, 7, 8]);
    await chooseEndHour(tester, 8);

    final payload = await submit(tester);
    expect(payload['endDate'], '2026-10-23');
    expect(payload['endTime'], 8);
  });

  testWidgets('end on a holiday without lessons uses the default bell times',
      (tester) async {
    await openDialog(tester, {
      _monday: _day(_monday, 3),
      _wednesday: buildCalendarDay(date: _wednesday),
    });
    await pickEndDay(tester, 21);

    // Neither the Monday schedule nor an empty list: the holiday has no
    // lessons and no other Wednesday is known, so the defaults apply.
    expect(options(tester, end: false), [1, 2, 3]);
    expect(options(tester, end: true), List.generate(10, (i) => i + 1));
  });

  testWidgets('end week is requested and its schedule replaces the weekday one',
      (tester) async {
    final store = await openDialog(tester, {
      _monday: _day(_monday, 8),
      _friday: _day(_friday, 5),
    });
    expect(store.state.calendarState.currentMonday, _monday);
    await chooseEndHour(tester, 8);

    await pickEndDay(tester, 26);

    // The next week was requested for the end date.
    expect(store.state.calendarState.currentMonday, _nextMonday);
    // Until it arrives, the end day falls back to the known Monday schedule.
    expect(options(tester, end: true), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(dropdown(tester, end: true).value, 8);

    // The loaded week has a shorter Monday; the selection is revalidated.
    store.replaceState(store.state.rebuild(
        (b) => b.calendarState.days.replace(BuiltMap<UtcDateTime, CalendarDay>({
              ...store.state.calendarState.days.toMap(),
              _nextMonday: _day(_nextMonday, 3, minute: 15),
            }))));
    await tester.pumpAndSettle();
    expect(options(tester, end: false), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(options(tester, end: true), [1, 2, 3]);
    expect(dropdown(tester, end: true).value, 3);
    expect(find.text('3 (11:00)'), findsOneWidget);

    final payload = await submit(tester);
    expect(payload['endDate'], '2026-10-26');
    expect(payload['endTime'], 3);
  });
}
