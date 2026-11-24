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

// The Legacy side drawer with large text (#148): its items grow with the
// text, long labels wrap to two lines and end with an ellipsis, and nothing
// is cut. The normal size and the collapsed tablet sidebar stay as they were.

import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';
import '../support/test_harness.dart';

const _labelKeys = [
  'sidebar.grades',
  'sidebar.absences',
  'sidebar.calendar',
  'sidebar.examCalendar',
  'sidebar.classRegister',
  'sidebar.courseMaterials',
  'sidebar.homework',
  'sidebar.certificate',
  'sidebar.messages',
  'sidebar.settings',
  'sidebar.logout',
];

class _Calls {
  int settings = 0;
  int logout = 0;
}

Sidebar _sidebar(_Calls calls,
        {required bool tabletMode, bool expanded = false}) =>
    Sidebar(
      tabletMode: tabletMode,
      drawerExpanded: expanded,
      onDrawerExpansionChange: (_) {},
      username: 'Anna Beispiel',
      userIcon: null,
      goHome: () {},
      // A long label is the selected one.
      currentSelected: Pages.examCalendar,
      showGrades: () {},
      showAbsences: () {},
      showCalendar: () {},
      showExamCalendar: () {},
      showClassRegister: () {},
      showCourseMaterials: () {},
      showHomeworkSummary: () {},
      showCertificate: () {},
      showMessages: () {},
      showProfile: () {},
      showSettings: () => calls.settings++,
      logout: () => calls.logout++,
      otherAccounts: const <String>[],
      selectAccount: (_) {},
      addAccount: () {},
      removeCurrentAccount: () {},
      passwordSavingEnabled: true,
    );

/// The drawer as the app shows it: the phone drawer of the scaffold, or the
/// sidebar beside the page on a tablet.
Future<_Calls> _pumpSidebar(
  WidgetTester tester, {
  required Size size,
  required double scale,
  String languageCode = 'de',
  ThemeMode themeMode = ThemeMode.light,
  bool? expanded,
}) async {
  await loadRoboto(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final calls = _Calls();
  final tabletMode = expanded != null;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    buildTestApp(
      store: createStore(
        initialState:
            AppState((b) => b.settingsState.languageCode = languageCode),
        withMiddleware: true,
      ),
      themeMode: themeMode,
      appNavigatorKey: GlobalKey<NavigatorState>(),
      messengerKey: GlobalKey<ScaffoldMessengerState>(),
      home: tabletMode
          ? Scaffold(
              body: Row(children: [
                _sidebar(calls, tabletMode: true, expanded: expanded),
                const Expanded(child: SizedBox()),
              ]),
            )
          : Scaffold(
              key: scaffoldKey,
              drawer: _sidebar(calls, tabletMode: false),
              body: const SizedBox(),
            ),
    ),
  );
  // The page appears once the translations are loaded.
  await tester.pumpAndSettle();
  if (!tabletMode) scaffoldKey.currentState!.openDrawer();
  await tester.pumpAndSettle();
  return calls;
}

List<String> _labels(WidgetTester tester) {
  final l10n = tester.element(find.byType(Sidebar)).l10n;
  return [for (final key in _labelKeys) l10n.text(key)];
}

/// The tappable area of the item that shows [label].
Rect _tile(WidgetTester tester, Finder label) => tester
    .getRect(find.ancestor(of: label, matching: find.byType(InkWell)).first);

Finder _label(String text) => find.descendant(
    of: find.byType(CollapsibleSidebar), matching: find.text(text));

/// Every label is shown whole or ends with an ellipsis after two lines, lies
/// inside its item, and its icon sits beside the first line.
Future<void> _expectReadable(WidgetTester tester, String reason) async {
  expect(tester.takeException(), isNull, reason: reason);
  final list = find.descendant(
      of: find.byType(CollapsibleSidebar), matching: find.byType(Scrollable));
  for (final text in _labels(tester)) {
    final label = _label(text);
    await tester.dragUntilVisible(label, list.first, const Offset(0, -60));
    await tester.pumpAndSettle();
    final why = '$reason, "$text"';
    final widget = tester.widget<Text>(label);
    expect(widget.maxLines, 2, reason: why);
    expect(widget.overflow, TextOverflow.ellipsis, reason: why);

    final tile = _tile(tester, label);
    final rect = tester.getRect(label);
    expect(rect.top, greaterThanOrEqualTo(tile.top - 0.5), reason: why);
    expect(rect.bottom, lessThanOrEqualTo(tile.bottom + 0.5), reason: why);
    expect(rect.right, lessThanOrEqualTo(tile.right + 0.5), reason: why);

    final paragraph = tester.renderObject<RenderParagraph>(label);
    // The text needs no more height than its box gets: no line is cut off.
    expect(paragraph.getMaxIntrinsicHeight(rect.width),
        lessThanOrEqualTo(rect.height + 0.5),
        reason: why);
    const start = TextPosition(offset: 0);
    final firstLine = rect.top +
        paragraph.getOffsetForCaret(start, Rect.zero).dy +
        paragraph.getFullHeightForCaret(start) / 2;
    final icon = tester.getRect(find
        .descendant(
          of: find.ancestor(of: label, matching: find.byType(Row)).first,
          matching: find.byType(Icon),
        )
        .first);
    expect(icon.center.dy, moreOrLessEquals(firstLine, epsilon: 1),
        reason: why);
  }
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  group('phone drawer', () {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('is readable at $width px and text size $scale',
            (tester) async {
          await _pumpSidebar(tester, size: Size(width, 760), scale: scale);
          await _expectReadable(tester, '$width, $scale');
        });
      }
    }

    // The case of the issue: a narrow phone at text size 2 and 3.
    for (final code in const ['de', 'en', 'it', 'lld']) {
      for (final (scale, themeMode) in [
        (2.0, ThemeMode.light),
        (3.0, ThemeMode.dark),
      ]) {
        testWidgets(
            'is readable at 320 px in $code, text size $scale '
            '($themeMode)', (tester) async {
          await _pumpSidebar(tester,
              size: const Size(320, 640),
              scale: scale,
              languageCode: code,
              themeMode: themeMode);
          expect(Theme.of(tester.element(find.byType(Sidebar))).brightness,
              themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
          await _expectReadable(tester, '$code, $scale');
        });
      }
    }

    testWidgets('keeps its size at the normal text size', (tester) async {
      await _pumpSidebar(tester, size: const Size(411, 900), scale: 1);

      for (final text in _labels(tester)) {
        final label = _label(text);
        final tile = _tile(tester, label);
        expect(tile.height, 42, reason: text);
        expect(tile.width, 250, reason: text);
        final icon = tester.getRect(find
            .descendant(
              of: find.ancestor(of: label, matching: find.byType(Row)).first,
              matching: find.byType(Icon),
            )
            .first);
        expect(icon.left - tile.left, 8, reason: text);
        expect(icon.center.dy, moreOrLessEquals(tile.center.dy), reason: text);
        expect(tester.getRect(label).center.dy,
            moreOrLessEquals(tile.center.dy, epsilon: 0.5),
            reason: text);
      }
      final selected =
          find.byKey(const ValueKey('collapsible-sidebar-selected-box'));
      expect(tester.getSize(selected), const Size(250, 42));
      final account = tester.getRect(find
          .ancestor(
            of: find.text('Anna Beispiel'),
            matching: find.byWidgetPredicate((widget) =>
                widget.runtimeType.toString() == 'CollapsibleItemWidget'),
          )
          .first);
      expect(account.height, 56);
    });

    testWidgets('the selected box covers a grown item', (tester) async {
      await _pumpSidebar(tester, size: const Size(320, 900), scale: 3);

      final label = _label(_labels(tester)[3]);
      final selected =
          find.byKey(const ValueKey('collapsible-sidebar-selected-box'));
      expect(tester.getRect(selected), _tile(tester, label));
      expect(tester.getSize(selected).height, greaterThan(42));
    });

    testWidgets('the full labels stay available to screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSidebar(tester,
          size: const Size(320, 640), scale: 3, languageCode: 'lld');

      final list = find.descendant(
          of: find.byType(CollapsibleSidebar),
          matching: find.byType(Scrollable));
      for (final text in _labels(tester)) {
        await tester.dragUntilVisible(
            _label(text), list.first, const Offset(0, -60));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(text), findsWidgets, reason: text);
      }
      semantics.dispose();
    });

    testWidgets('scrolls to the last items in a landscape phone at size 3',
        (tester) async {
      final calls =
          await _pumpSidebar(tester, size: const Size(640, 320), scale: 3);
      expect(tester.takeException(), isNull);

      final labels = _labels(tester);
      final list = find.descendant(
          of: find.byType(CollapsibleSidebar),
          matching: find.byType(Scrollable));
      for (final (text, count) in [
        (labels[9], () => calls.settings),
        (labels[10], () => calls.logout),
      ]) {
        await tester.dragUntilVisible(
            _label(text), list.first, const Offset(0, -60));
        await tester.pumpAndSettle();
        await tester.tap(_label(text));
        await tester.pumpAndSettle();
        expect(count(), 1, reason: text);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet sidebar', () {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('expanded is readable at text size $scale', (tester) async {
        await _pumpSidebar(tester,
            size: const Size(1024, 768), scale: scale, expanded: true);
        await _expectReadable(tester, 'tablet, $scale');
      });

      testWidgets('collapsed keeps its square items at text size $scale',
          (tester) async {
        await _pumpSidebar(tester,
            size: const Size(1024, 768), scale: scale, expanded: false);
        expect(tester.takeException(), isNull);

        final selected =
            find.byKey(const ValueKey('collapsible-sidebar-selected-box'));
        expect(tester.getSize(selected), const Size(42, 42));
        for (final text in _labels(tester)) {
          final tile = _tile(tester, _label(text));
          expect(tile.size, const Size(42, 42), reason: text);
        }
      });
    }
  });
}
