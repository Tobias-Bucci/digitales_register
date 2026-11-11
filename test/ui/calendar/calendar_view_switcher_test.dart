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

/// The app bar of the page that is open, with the switcher as its title.
AppBar _appBarOf(WidgetTester tester, Type page) => tester.widget<AppBar>(
      find.descendant(of: find.byType(page), matching: find.byType(AppBar)),
    );

/// The glass header of the calendar, with the switcher as its title.
GlassPageHeader _calendarHeader(WidgetTester tester) =>
    tester.widget<GlassPageHeader>(
      find.descendant(
        of: find.byType(Calendar),
        matching: find.byType(GlassPageHeader),
      ),
    );

final _calendarHeaderSurface = find.byKey(const Key('calendar-app-header'));

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
    expect(
      tester.getSemantics(find.byType(CalendarViewSwitcher)),
      matchesSemantics(label: 'Kalender', isHeader: true),
    );
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
    final appBar = _appBarOf(tester, ExamCalendarPage);
    expect(appBar.bottom, isNull);
    expect(appBar.title, isA<CalendarViewSwitcher>());
    expect(find.byKey(const Key('exam-timeline-view')), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(CalendarViewSwitcher)),
      matchesSemantics(label: 'Prüfungskalender', isHeader: true),
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
    // The glass header of the calendar limits large text to 150 %, the plain
    // app bar of the exam calendar does not yet, so only the width is the same.
    expect(examRect.left, calendarRect.left);
    expect(examRect.right, calendarRect.right);
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
