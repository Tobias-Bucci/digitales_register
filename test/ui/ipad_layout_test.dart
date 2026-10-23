import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/main.dart' show actions;
import 'package:dr/ui/calendar_detail.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/messages.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

const _windowSizes = [
  Size(768, 1024), // iPad portrait
  Size(1024, 768), // iPad landscape
  Size(834, 1194), // 11-inch portrait
  Size(1194, 834), // 11-inch landscape
  Size(1024, 1366), // 13-inch portrait
  Size(1366, 1024), // 13-inch landscape
  Size(720, 1024), // Sidebar breakpoint
  Size(375, 1024), // Narrow Split View / window
];

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  for (final page in ['grades', 'messages', 'calendar']) {
    testWidgets('$page keeps navigation and content across iPad window sizes',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = _windowSizes.first;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final monday = UtcDateTime(2021, 1, 25);
      final store = createStore(
          appActions: actions,
          initialState: buildGradesPageState().rebuild((b) {
            b.settingsState
              ..showCalendarNicksBar = false
              ..showCalendarSubstituteBar = false;
            b.calendarState
              ..currentMonday = monday
              ..days = MapBuilder({
                for (var day = 0; day < 5; day++)
                  monday.add(Duration(days: day)): buildCalendarDay(
                      date: monday.add(Duration(days: day)),
                      hours: [buildCalendarHour(subject: 'Mathematik')]),
              });
          }));
      final scaffold = GlobalKey<ResponsiveScaffoldState<String>>();
      final content = switch (page) {
        'grades' => const GradesPageContainer(),
        'messages' => MessagesPage(
            state: MessagesState((b) => b.messages = ListBuilder([
                  buildMessage(subject: 'iPad Nachricht'),
                ])),
            noInternet: false,
            onOpenFile: (_) {},
            onMarkAsRead: (_) {},
            onArchive: (_) {},
            onReply: (_, __) {},
          ),
        _ => CalendarContainer(),
      };
      await pumpApp(tester,
          store: store,
          home: ResponsiveScaffold<String>(
            key: scaffold,
            navKey: GlobalKey<NavigatorState>(),
            homeId: 'home',
            homeBody: const Text('Dashboard'),
            homeAppBar: AppBar(title: const Text('Register')),
            drawerBuilder: (select, home, selected, tablet) => SizedBox(
              width: 68,
              child: Material(
                child: ListTile(
                  title: const Icon(Icons.school),
                  onTap: () => select(content, page),
                ),
              ),
            ),
          ));
      await tester.tap(find.byIcon(Icons.school));
      await tester.pumpAndSettle();
      if (page == 'messages') {
        await tester.tap(find.text('iPad Nachricht'));
        await tester.pumpAndSettle();
      }

      final pageElement = tester.element(find.byWidget(content));
      for (final size in _windowSizes) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$page at $size');
        expect(scaffold.currentState!.tabletMode,
            size.width >= tabletLayoutBreakpoint);
        expect(scaffold.currentState!.currentSelected, page);
        expect(tester.element(find.byWidget(content)), same(pageElement));
        if (page != 'calendar') {
          final width = tester.getSize(find.byType(ReadableContent)).width;
          final listWidth = tester.getSize(find.byType(ListView).last).width;
          expect(listWidth, lessThanOrEqualTo(960));
          expect(listWidth, lessThanOrEqualTo(width));
        }
        if (page == 'messages') {
          expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
        }
        // Exercise a real modal above the nested navigator at every size.
        final context = tester.element(find.byWidget(content));
        showDialog<void>(
          context: context,
          builder: (_) => const InfoDialog(
              title: Text('Information'), content: Text('iPad Dialog')),
        );
        await tester.pumpAndSettle();
        final dialog = tester.getRect(find.byType(AlertDialog));
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(size.width));
        await tester.tap(find.descendant(
            of: find.byType(AlertDialog), matching: find.byIcon(Icons.close)));
        await tester.pumpAndSettle();
      }
      scaffold.currentState!.goHome();
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
    });
  }

  testWidgets('calendar details are visible on initial wide layout',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        Expanded(child: Text('Stundenplan')),
        RightSidebar(show: true, child: Text('Stundendetails')),
      ]),
    ));
    expect(tester.getSize(find.byType(RightSidebar)).width, 350);
    expect(find.text('Stundendetails').hitTestable(), findsOneWidget);
  });

  testWidgets('grade averages grow with large text in a narrow iPad window',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 1024);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester,
        store: createStore(initialState: buildGradesPageState()),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: GradesPageContainer(),
        ));
    await tester.pumpAndSettle();
    final label = find.text('Zeugnisdurchschnitt');
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final row = find.ancestor(of: label, matching: find.byType(Row)).first;
    expect(tester.getSize(row).height, greaterThan(48));
    expect(tester.getRect(label).height,
        lessThanOrEqualTo(tester.getRect(row).height));
    expect(tester.takeException(), isNull);
  });
}
