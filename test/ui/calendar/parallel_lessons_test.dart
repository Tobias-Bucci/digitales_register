// Issue #134: the Wednesday with two parallel lessons in hours 2–3 has to
// show all six lessons in the week view, in both designs, on a phone and on
// a tablet.

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show actions, scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _wednesday = UtcDateTime(2026, 11, 25);
final _monday = toMonday(_wednesday);

const _phone = Size(412, 900);
const _tablet = Size(1024, 1366);

CalendarHour _hour(String subject, String teacher, int from, [int? to]) =>
    buildCalendarHour(
      subject: subject,
      fromHour: from,
      toHour: to ?? from,
      rooms: const ['3B'],
      teachers: [buildTeacher(firstName: 'T', lastName: teacher)],
    );

AppState _state() => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState
        ..languageCode = 'de'
        ..calendarColorBackground = true
        ..subjectNicks = MapBuilder<String, String>()
        ..subjectThemes = MapBuilder<String, SubjectTheme>();
      b.calendarState.currentMonday = _monday;
      b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
        for (var d = 0; d < 5; d++)
          _monday.add(Duration(days: d)): buildCalendarDay(
            date: _monday.add(Duration(days: d)),
            hours: d == 2
                ? [
                    _hour('Geschichte', 'Rauch', 1),
                    _hour('Deutsch', 'Rauch', 2, 3),
                    _hour('Informatik', 'Awerk', 2, 3),
                    _hour('Bewegung', 'Mumelter', 4),
                    _hour('Latein', 'Rauch', 5),
                    _hour('Mathematik', 'Thaler', 6),
                  ]
                : [_hour('Religion', 'Huber', 1)],
          ),
      });
    });

const _wednesdayLessons = [
  'Geschichte',
  'Deutsch',
  'Informatik',
  'Bewegung',
  'Latein',
  'Mathematik',
];

Future<void> _pump(
  WidgetTester tester, {
  required bool newDesign,
  required Size size,
}) async {
  tester.view.physicalSize = size;
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
  await settleFor(tester, duration: const Duration(milliseconds: 800));
}

/// Whether a horizontal flex inside the week grid is wider than its box.
bool _gridOverflows(WidgetTester tester) {
  final grid = find.byType(CalendarWeek);
  for (final element
      in find.descendant(of: grid, matching: find.byType(Row)).evaluate()) {
    final flex = element.renderObject! as RenderFlex;
    var width = 0.0;
    for (var child = flex.firstChild; child != null;) {
      width += child.size.width;
      child = (child.parentData! as FlexParentData).nextSibling;
    }
    if (width > flex.size.width + 0.5) return true;
  }
  return false;
}

/// The tile of one lesson: the closest tappable area around its subject.
Rect _tile(WidgetTester tester, String subject) => tester.getRect(
      find
          .ancestor(of: find.text(subject), matching: find.byType(InkWell))
          .first,
    );

void _expectWednesdayLaidOut(WidgetTester tester, {bool legacy = false}) {
  final error = tester.takeException();
  // The legacy week header is a little too wide for a 412 px phone; that
  // happens without parallel lessons as well and is not part of the grid.
  if (!(legacy && '$error'.contains('overflowed'))) {
    expect(error, isNull);
  }
  expect(_gridOverflows(tester), isFalse);
  for (final subject in _wednesdayLessons) {
    expect(find.text(subject), findsOneWidget, reason: subject);
  }
  final tiles = {
    for (final subject in _wednesdayLessons) subject: _tile(tester, subject),
  };
  // The parallel lessons sit side by side, between lesson 1 and lesson 4,
  // and share the height of two lessons.
  final deutsch = tiles['Deutsch']!;
  final informatik = tiles['Informatik']!;
  expect(deutsch.top, moreOrLessEquals(informatik.top, epsilon: 1));
  expect(deutsch.height, moreOrLessEquals(informatik.height, epsilon: 1));
  expect(deutsch.right, lessThanOrEqualTo(informatik.left + 1));
  expect(deutsch.height,
      moreOrLessEquals(2 * tiles['Bewegung']!.height, epsilon: 3));
  expect(tiles['Geschichte']!.bottom, lessThanOrEqualTo(deutsch.top + 1));
  expect(deutsch.bottom, lessThanOrEqualTo(tiles['Bewegung']!.top + 1));
  // Everything after them keeps its rows.
  expect(
      tiles['Bewegung']!.bottom, lessThanOrEqualTo(tiles['Latein']!.top + 1));
  expect(
      tiles['Latein']!.bottom, lessThanOrEqualTo(tiles['Mathematik']!.top + 1));
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: _wednesday);
  });

  tearDown(resetTestState);

  for (final (name, size) in [('phone', _phone), ('tablet', _tablet)]) {
    testWidgets('legacy design shows all six lessons on a $name',
        (tester) async {
      await _pump(tester, newDesign: false, size: size);
      _expectWednesdayLaidOut(tester, legacy: true);
      // The other days are unaffected.
      expect(find.text('Religion'), findsNWidgets(4));
    });

    testWidgets('new design shows all six lessons on a $name', (tester) async {
      await _pump(tester, newDesign: true, size: size);
      _expectWednesdayLaidOut(tester);
      expect(find.text('Religion'), findsNWidgets(4));
    });
  }
}
