import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/calendar_view_switcher.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart' show Pages;
import 'package:dr/ui/calendar.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 10, 20);

AppState _state() => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>([
        buildDay(date: _today),
      ]);
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://franziskanergymnasium.digitalesregister.it';
      b.noInternet = true;
      // The helper bars are not what these tests look at.
      b.settingsState
        ..showCalendarSubstituteBar = false
        ..showCalendarNicksBar = false;
      b.calendarState.currentMonday = toMonday(_today);
    });

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  bool newDesign = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final store = createStore(
    initialState: _state(),
    newDesign: newDesign,
    withMiddleware: true,
  );
  await pumpApp(tester, store: store, home: DaysContainer());
  await settleFor(tester);
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(seconds: 1));

/// Lets the timers of the middleware run out after a test that navigates.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

Pages _current() => scaffoldKey!.currentState!.currentSelected;

final _switcher = find.byKey(const Key('calendar-view-switcher'));

/// The glass header of [page], with the switcher as its title.
GlassPageHeader _headerOf(WidgetTester tester, Type page) =>
    tester.widget<GlassPageHeader>(
      find.descendant(
        of: find.byType(page),
        matching: find.byType(GlassPageHeader),
      ),
    );

GlassPageHeader _calendarHeader(WidgetTester tester) =>
    _headerOf(tester, Calendar);

final _calendarHeaderSurface = find.byKey(const Key('calendar-app-header'));

/// The header nodes in the glass header of the page that is open.
List<SemanticsNode> _headerNodes(WidgetTester tester, Finder surface) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isHeader) {
      nodes.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(surface));
  return nodes;
}

/// The page title is one heading, and both segments stay buttons in it.
void _expectOneHeading(WidgetTester tester, Finder surface, String title) {
  final headers = _headerNodes(tester, surface)
      .where((node) => node.label == title)
      .toList();
  expect(headers, hasLength(1));
  for (final segment in [false, true]) {
    expect(
      tester.getSemantics(find.byKey(ValueKey('glass-segment-$segment'))),
      isSemantics(isButton: true, hasTapAction: true, isHeader: false),
    );
  }
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('the view switcher is the title row of both calendar pages',
      (tester) async {
    await _pump(tester, size: const Size(412, 915));
    await tester.tap(find.byKey(const ValueKey('app-navigation-calendar')));
    await _settle(tester);

    expect(_current(), Pages.calendar);
    expect(_calendarHeader(tester).bottom, isNull);
    expect(_calendarHeader(tester).titleWidget, isA<CalendarViewSwitcher>());
    expect(
      find.descendant(of: _calendarHeaderSurface, matching: _switcher),
      findsOneWidget,
    );
    expect(find.text('Kalender'), findsOneWidget);
    _expectOneHeading(tester, _calendarHeaderSurface, 'Kalender');
    final calendarRect = tester.getRect(_switcher);
    expect(calendarRect.height, lessThanOrEqualTo(56));

    // Away from the current week, the way back is an icon next to it.
    final currentWeek = find.byKey(const Key('calendar-current-week'));
    expect(currentWeek, findsNothing);
    // The arrow of the week header (the first one), to the next week.
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await _settle(tester);
    expect(currentWeek, findsOneWidget);
    expect(tester.getRect(_switcher), calendarRect);
    await tester.tap(currentWeek);
    await _settle(tester);
    expect(currentWeek, findsNothing);

    await tester.tap(find.byKey(const ValueKey('glass-segment-true')));
    await _settle(tester);

    expect(_current(), Pages.examCalendar);
    final examHeader = _headerOf(tester, ExamCalendarPage);
    expect(examHeader.bottom, isNull);
    expect(examHeader.titleWidget, isA<CalendarViewSwitcher>());
    expect(find.byKey(const Key('exam-timeline-view')), findsOneWidget);
    _expectOneHeading(
      tester,
      find.byKey(const Key('exam-calendar-app-header')),
      'Prüfungskalender',
    );
    // It does not jump when switching pages.
    expect(tester.getRect(_switcher), calendarRect);

    await tester.tap(find.byKey(const ValueKey('glass-segment-false')));
    await _settle(tester);

    expect(_current(), Pages.calendar);
    expect(_calendarHeader(tester).bottom, isNull);
    expect(tester.takeException(), isNull);
    await _finish(tester);
  });

  testWidgets('the switcher fits a 320 px phone with large text',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 2);
    await tester.tap(find.byKey(const ValueKey('app-navigation-calendar')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final calendarRect = tester.getRect(_switcher);
    final calendarBar = tester.getRect(_calendarHeaderSurface);
    expect(calendarRect.left, greaterThanOrEqualTo(calendarBar.left));
    expect(calendarRect.right, lessThanOrEqualTo(calendarBar.right));

    await tester.tap(find.byKey(const ValueKey('glass-segment-true')));
    await _settle(tester);

    expect(_current(), Pages.examCalendar);
    expect(tester.takeException(), isNull);
    final examRect = tester.getRect(_switcher);
    // Both pages share the glass header, so nothing moves.
    expect(examRect, calendarRect);
    // The actions keep their room next to the switcher.
    final timelineButton =
        tester.getRect(find.byKey(const Key('exam-timeline-view')));
    expect(examRect.right, lessThanOrEqualTo(timelineButton.left));
    await _finish(tester);
  });

  testWidgets('legacy keeps the plain title and no switcher', (tester) async {
    await pumpApp(
      tester,
      store: createStore(initialState: _state()),
      home: CalendarContainer(),
    );
    await settleFor(tester);
    expect(_switcher, findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Kalender'),
      ),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('calendar-open-exam-calendar')), findsOneWidget);
  });
}
