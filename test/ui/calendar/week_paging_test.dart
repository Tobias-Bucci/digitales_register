// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show actions, scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

// #180: "next week" jumped some users to 2033. The animation to the next
// page runs to the pixels of that page at the width it started with; when the
// week view changed width meanwhile (the detail sidebar of a wide screen
// sliding in or out, a resized or rotated window), it ended hundreds of weeks
// away.
final _today = UtcDateTime(2026, 10, 21);
final _monday = toMonday(_today);
final _nextMonday = _monday.add(const Duration(days: 7));

const _wide = Size(1280, 800);

final _selection = CalendarSelection(
  (b) => b
    ..date = _monday
    ..hour = 1,
);

AppState _state() => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.calendarState.currentMonday = _monday;
      b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
        for (var d = 0; d < 5; d++)
          _monday.add(Duration(days: d)): buildCalendarDay(
            date: _monday.add(Duration(days: d)),
            hours: [buildCalendarHour(subject: 'Deutsch', toHour: 2)],
          ),
      });
    });

Future<Store<AppState, AppStateBuilder, AppActions>> _pumpCalendar(
  WidgetTester tester, {
  required bool newDesign,
}) async {
  tester.view.physicalSize = _wide;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(),
    newDesign: newDesign,
    appActions: actions,
  );
  if (newDesign) {
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    scaffoldKey!.currentState!
        .selectContentWidget(CalendarContainer(), Pages.calendar);
  } else {
    await pumpApp(tester, store: store, home: CalendarContainer());
  }
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _nextWeek({required bool newDesign}) => newDesign
    ? find.byKey(const Key('calendar-next-week'))
    // The week bar comes before the chevron of the detail sidebar.
    : find.widgetWithIcon(TextButton, Icons.chevron_right).first;

/// Taps "next week" and, a frame into the page animation, runs [meanwhile].
Future<void> _nextWeekWhile(
  WidgetTester tester, {
  required bool newDesign,
  required void Function() meanwhile,
}) async {
  await tester.tap(_nextWeek(newDesign: newDesign));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  meanwhile();
  await settleFor(tester, duration: const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: _today);
  });

  tearDown(resetTestState);

  for (final newDesign in [true, false]) {
    final design = newDesign ? 'new design' : 'Legacy';

    group(design, () {
      testWidgets('next week while the detail sidebar opens', (tester) async {
        final store = await _pumpCalendar(tester, newDesign: newDesign);

        await _nextWeekWhile(
          tester,
          newDesign: newDesign,
          meanwhile: () => store.actions.calendarActions.select(_selection),
        );

        expect(store.state.calendarState.currentMonday, _nextMonday);
        expect(tester.takeException(), isNull);
      });

      testWidgets('next week while the detail sidebar closes', (tester) async {
        final store = await _pumpCalendar(tester, newDesign: newDesign);
        await store.actions.calendarActions.select(_selection);
        await settleFor(tester, duration: const Duration(seconds: 1));

        await _nextWeekWhile(
          tester,
          newDesign: newDesign,
          meanwhile: () => store.actions.calendarActions.select(null),
        );

        expect(store.state.calendarState.currentMonday, _nextMonday);
      });

      testWidgets('next week while the window gets narrower', (tester) async {
        final store = await _pumpCalendar(tester, newDesign: newDesign);

        await _nextWeekWhile(
          tester,
          newDesign: newDesign,
          meanwhile: () => tester.view.physicalSize = const Size(900, 800),
        );

        expect(store.state.calendarState.currentMonday, _nextMonday);
      });

      testWidgets('each tap turns exactly one week', (tester) async {
        final store = await _pumpCalendar(tester, newDesign: newDesign);

        for (var week = 1; week <= 6; week++) {
          await tester.tap(_nextWeek(newDesign: newDesign));
          await settleFor(tester, duration: const Duration(milliseconds: 600));
          expect(
            store.state.calendarState.currentMonday,
            _monday.add(Duration(days: 7 * week)),
          );
        }
      });
    });
  }
}
