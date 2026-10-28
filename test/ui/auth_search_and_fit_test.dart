import 'dart:io';
import 'dart:math' as math;

import 'package:dr/app_state.dart';
import 'package:dr/ui/auth_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';
import 'auth_motion_test.dart' show field, host;

const query = 'Schulsprengel';

Finder get suggestions => find.byType(ListView);

ScrollPosition listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
        find.descendant(of: suggestions, matching: find.byType(Scrollable)))
    .position;

String firstSuggestion(WidgetTester tester) => tester
    .widgetList<Text>(
        find.descendant(of: suggestions, matching: find.byType(Text)))
    .first
    .data!;

void expectFirstSuggestionVisible(WidgetTester tester) {
  expect(listPosition(tester).pixels, 0);
  final list = tester.getRect(suggestions);
  final first = tester.getRect(find.text(firstSuggestion(tester)).last);
  expect(first.top, greaterThanOrEqualTo(list.top));
  expect(first.bottom, lessThanOrEqualTo(list.bottom));
}

bool schoolFieldFocused(WidgetTester tester) => tester
    .widget<EditableText>(find.descendant(
        of: field('Schule'), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

ScrollPhysics? pagePhysics(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(const ValueKey('auth-scroll')))
    .physics;

bool pageLocked(WidgetTester tester) =>
    pagePhysics(tester) is NeverScrollableScrollPhysics;

bool focused(WidgetTester tester, String label) => tester
    .widget<EditableText>(
        find.descendant(of: field(label), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

int focusedFields(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .where((editable) => editable.focusNode.hasFocus)
    .length;

/// Slides a keyboard of [height] in (or out, towards 0) over a few frames,
/// like the platform reports it.
Future<void> slideKeyboard(WidgetTester tester, double from, double to) async {
  for (var step = 1; step <= 6; step++) {
    tester.view.viewInsets =
        FakeViewPadding(bottom: from + (to - from) * step / 6);
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pumpAndSettle();
}

ScrollPosition pagePosition(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
            of: find.byKey(const ValueKey('auth-scroll')),
            matching: find.byType(Scrollable))
        .first)
    .position;

/// Real Roboto metrics, so fit checks match an Android phone rather than the
/// test font's square glyphs.
Future<void> loadRoboto(WidgetTester tester) => tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT'] ??
          File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      final loader = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        final file = File('$fonts/roboto-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())));
        }
      }
      await loader.load();
    });

Future<void> pumpPhone(
  WidgetTester tester, {
  required Size size,
  EdgeInsets padding = EdgeInsets.zero,
  double textScale = 1,
  List<String> accounts = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(
      left: padding.left,
      top: padding.top,
      right: padding.right,
      bottom: padding.bottom);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(buildTestApp(
    store: createStore(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: host(ValueNotifier(
            AppState((b) => b.loginState.otherAccounts.addAll(accounts)))),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AuthLayout.debugResetKeyboardMemory();
    return bootstrapTestEnvironment();
  });
  tearDown(resetTestState);

  group('school suggestions', () {
    testWidgets('each query starts at the first result', (tester) async {
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pumpAndSettle();
      // More results than fit: the list has to scroll.
      expect(listPosition(tester).maxScrollExtent, greaterThan(0));
      expectFirstSuggestionVisible(tester);

      // Scroll down and move the keyboard highlight, then refine the query.
      await tester.drag(suggestions, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(listPosition(tester).pixels, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.enterText(field('Schule'), '$query V');
      await tester.pumpAndSettle();
      expectFirstSuggestionVisible(tester);
      // Enter takes the best match, not a stale highlight.
      final best = firstSuggestion(tester);
      // Submitting the field (Enter / "next") selects the highlight.
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Schule')).controller!.text, best);
    });

    testWidgets('dragging the list on a phone scrolls it and keeps it open',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pumpAndSettle();
      final page = pagePosition(tester).pixels;

      // A touch drag (the default pointer kind) inside the list.
      final gesture = await tester.startGesture(tester.getCenter(suggestions));
      for (var step = 0; step < 6; step++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(listPosition(tester).pixels, greaterThan(0));
      expect(schoolFieldFocused(tester), isTrue);
      expect(suggestions, findsOneWidget);
      expect(pagePosition(tester).pixels, page);
      // The drag picked nothing.
      expect(tester.widget<TextField>(field('Schule')).controller!.text, query);
    });

    testWidgets('the list stays above the keyboard', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pumpAndSettle();
      expect(
          tester.getRect(suggestions).bottom, lessThanOrEqualTo(844 - 300.0));
    });
  });

  group('first-run fit', () {
    for (final phone in [
      (
        name: 'Android 392x850',
        size: const Size(392, 850),
        padding: const EdgeInsets.only(top: 24, bottom: 48)
      ),
      (
        name: 'iPhone 390x844',
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47, bottom: 34)
      ),
      (
        name: 'small Android 360x740',
        size: const Size(360, 740),
        padding: const EdgeInsets.only(top: 24, bottom: 48)
      ),
      (
        name: 'large Android 412x915',
        size: const Size(412, 915),
        padding: const EdgeInsets.only(top: 24, bottom: 48)
      ),
    ]) {
      testWidgets('${phone.name} fits without scrolling', (tester) async {
        await loadRoboto(tester);
        await pumpPhone(tester, size: phone.size, padding: phone.padding);
        expect(tester.takeException(), isNull);
        expect(pagePosition(tester).maxScrollExtent, 0);
        // Not even a few pixels to drag, no bounce or glow.
        expect(pageLocked(tester), isTrue);
        final column = tester.getRect(find
            .descendant(
                of: find.byKey(const ValueKey('auth-scroll')),
                matching: find.byType(Column))
            .first);
        expect(column.height,
            lessThanOrEqualTo(pagePosition(tester).viewportDimension - 4));
        // Controls keep their minimum sizes.
        expect(tester.getSize(find.byType(ElevatedButton)).height, 50);
        for (final label in ['Schule', 'Benutzername', 'Passwort']) {
          expect(tester.getSize(field(label)).height, greaterThanOrEqualTo(48));
        }

        // With the keyboard up the page scrolls again.
        await slideKeyboard(tester, 0, 300);
        expect(pageLocked(tester), isFalse);
        await slideKeyboard(tester, 300, 0);
        expect(pageLocked(tester), isTrue);
      });
    }

    for (final scenario in [
      // Screens under 560 px of usable height already had the short
      // header (56 px icon) before the fit logic existed.
      (
        name: '320x568',
        size: const Size(320, 568),
        scale: 1.0,
        accounts: const <String>[],
        icon: 56.0
      ),
      (
        name: 'text scale 1.6',
        size: const Size(392, 850),
        scale: 1.6,
        accounts: const <String>[],
        icon: 80.0
      ),
      (
        name: 'saved accounts',
        size: const Size(392, 850),
        scale: 1.0,
        accounts: const ['maria.muster', 'max.muster'],
        icon: 80.0
      ),
    ]) {
      testWidgets('${scenario.name} keeps the comfortable layout and scrolls',
          (tester) async {
        await loadRoboto(tester);
        await pumpPhone(tester,
            size: scenario.size,
            padding: const EdgeInsets.only(top: 24, bottom: 48),
            textScale: scenario.scale,
            accounts: scenario.accounts);
        expect(tester.takeException(), isNull);
        expect(pagePosition(tester).maxScrollExtent, greaterThan(0));
        expect(pageLocked(tester), isFalse);
        // No tier was applied: the icon keeps its regular size.
        expect(tester.getSize(find.byType(Image)).height, scenario.icon);
        await tester.ensureVisible(find.text('Feedback senden'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('suggestion list and keyboard', () {
    Future<void> openList(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pump();
    }

    testWidgets('first opening already has the final height', (tester) async {
      await openList(tester);
      // The keyboard slides in while the list is open.
      await slideKeyboard(tester, 0, 300);
      final first = tester.getRect(suggestions);
      expect(first.bottom, lessThanOrEqualTo(844 - 300.0));

      // Leave the field (keyboard stays for the next field), come back.
      FocusManager.instance.primaryFocus!.nextFocus();
      await tester.pumpAndSettle();
      expect(suggestions, findsNothing);
      await tester.tap(field('Schule'));
      await tester.pumpAndSettle();
      expect(tester.getRect(suggestions).height, first.height);
      expect(tester.getRect(suggestions).top, first.top);
    });

    testWidgets('moving focus to another field closes the list',
        (tester) async {
      await openList(tester);
      await tester.pumpAndSettle();
      expect(suggestions, findsOneWidget);
      tester
          .widget<EditableText>(find.descendant(
              of: field('Benutzername'), matching: find.byType(EditableText)))
          .focusNode
          .requestFocus();
      // A programmatic request applies in a microtask (a tap applies before
      // the frame); the very next frame must not show the list any more.
      await tester.idle();
      await tester.pump();
      expect(suggestions, findsNothing);
    });

    testWidgets('Tab closes the list and coming back does not reopen it',
        (tester) async {
      await openList(tester);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(suggestions, findsNothing);
      expect(focused(tester, 'Schule'), isFalse);

      // Back into the field without typing or tapping (Shift+Tab would
      // first stop at the "Adresse manuell eingeben" link shown now).
      tester
          .widget<EditableText>(find.descendant(
              of: field('Schule'), matching: find.byType(EditableText)))
          .focusNode
          .requestFocus();
      await tester.pumpAndSettle();
      expect(focused(tester, 'Schule'), isTrue);
      expect(suggestions, findsNothing);
      // Typing opens it again.
      await tester.enterText(field('Schule'), '$query V');
      await tester.pumpAndSettle();
      expect(suggestions, findsOneWidget);
    });

    testWidgets('tapping outside closes the list', (tester) async {
      await openList(tester);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(suggestions, findsNothing);
      expect(focused(tester, 'Schule'), isFalse);
    });

    testWidgets('closing the keyboard closes the list', (tester) async {
      await openList(tester);
      await slideKeyboard(tester, 0, 300);
      expect(suggestions, findsOneWidget);
      await slideKeyboard(tester, 300, 0);
      expect(suggestions, findsNothing);
      expect(focused(tester, 'Schule'), isFalse);
    });
  });

  group('moving between fields', () {
    testWidgets('Next hands focus on without dropping the keyboard',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.tap(field('Schule'));
      await tester.pumpAndSettle();
      tester.testTextInput.log.clear();

      for (final next in ['Benutzername', 'Passwort']) {
        await tester.testTextInput.receiveAction(TextInputAction.next);
        // Exactly one field is focused in every frame of the hand-off.
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(focusedFields(tester), 1);
        }
        expect(focused(tester, next), isTrue);
      }
      expect(
          tester.testTextInput.log
              .where((call) => call.method == 'TextInput.hide'),
          isEmpty);
    });

    testWidgets('a field covered by the keyboard glides into view',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.tap(field('Benutzername'));
      await slideKeyboard(tester, 0, 420);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      // Mid-way through the 250 ms reveal the page is still moving.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = pagePosition(tester).pixels;
      await tester.pumpAndSettle();
      expect(focused(tester, 'Passwort'), isTrue);
      expect(pagePosition(tester).pixels, greaterThanOrEqualTo(midway));
      // Just into view above the keyboard, not to the top. (Flutter keeps
      // room for the selection handle below the caret, so the gap is a
      // little over the 24 px scroll padding.)
      const keyboardTop = 844 - 420.0;
      final password = tester.getRect(field('Passwort'));
      expect(password.bottom, lessThanOrEqualTo(keyboardTop - 16));
      expect(password.bottom, greaterThanOrEqualTo(keyboardTop - 56));
      expect(password.top, greaterThan(keyboardTop / 2));
    });

    testWidgets('Next on an open list picks the best match and moves on',
        (tester) async {
      await tester.pumpWidget(buildTestApp(
          store: createStore(), home: host(ValueNotifier(AppState()))));
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pumpAndSettle();
      final best = firstSuggestion(tester);
      tester.testTextInput.log.clear();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Schule')).controller!.text, best);
      expect(suggestions, findsNothing);
      expect(focused(tester, 'Benutzername'), isTrue);
      expect(
          tester.testTextInput.log
              .where((call) => call.method == 'TextInput.hide'),
          isEmpty);
    });
  });

  group('school search without page scrolling', () {
    Future<void> pumpPhoneLogin(WidgetTester tester,
        {bool reducedMotion = false}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(392, 850);
      // Status bar only: on a device the navigation bar's padding drops to
      // zero while the keyboard (which covers it) is up.
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestApp(
          store: createStore(),
          home: host(ValueNotifier(AppState()), reducedMotion: reducedMotion)));
      await tester.pumpAndSettle();
    }

    double spaceBelowSchool(WidgetTester tester, double keyboard) =>
        850 - keyboard - tester.getRect(field('Schule')).bottom - 16;

    testWidgets('focusing the school field never scrolls the page',
        (tester) async {
      await pumpPhoneLogin(tester);
      await tester.tap(field('Schule'));
      await tester.pump();
      for (var step = 1; step <= 6; step++) {
        tester.view.viewInsets = FakeViewPadding(bottom: 300 * step / 6);
        await tester.pump(const Duration(milliseconds: 40));
        expect(pagePosition(tester).pixels, 0);
      }
      await tester.pumpAndSettle();
      await tester.enterText(field('Schule'), query);
      await tester.pumpAndSettle();
      expect(pagePosition(tester).pixels, 0);
      expect(find.byType(AuthAppIcon), findsOneWidget);
    });

    testWidgets('the list fills the space between field and keyboard',
        (tester) async {
      await pumpPhoneLogin(tester);
      await tester.tap(field('Schule'));
      await slideKeyboard(tester, 0, 300);
      for (final pass in [1, 2]) {
        await tester.enterText(field('Schule'), query);
        await tester.pumpAndSettle();
        final list = tester.getRect(suggestions);
        // Height = keyboard top - field bottom - 8 px gap - 8 px margin
        // (capped at six rows).
        expect(
            list.height,
            moreOrLessEquals(math.min(spaceBelowSchool(tester, 300), 276),
                epsilon: 0.5),
            reason: 'pass $pass');
        expect(list.bottom, lessThanOrEqualTo(850 - 300.0));
        // Leave and come back: same size.
        FocusManager.instance.primaryFocus!.nextFocus();
        await tester.pumpAndSettle();
        await tester.tap(field('Schule'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('the header folds away only when fewer than 4 rows fit',
        (tester) async {
      await pumpPhoneLogin(tester);
      await tester.tap(field('Schule'));
      // A small keyboard leaves room for 4+ rows: nothing changes.
      await slideKeyboard(tester, 0, 200);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(spaceBelowSchool(tester, 200), greaterThanOrEqualTo(4 * 44 + 12));
      expect(find.byType(AuthAppIcon), findsOneWidget);

      // A tall keyboard would leave fewer: the header folds, the field
      // moves up and the list gets the room, without any scrolling.
      final before = tester.getRect(field('Schule')).top;
      await slideKeyboard(tester, 200, 420);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(AuthAppIcon), findsNothing);
      expect(find.text('Melde dich mit deinem Schulkonto an.'), findsNothing);
      expect(tester.getRect(field('Schule')).top, lessThan(before));
      expect(pagePosition(tester).pixels, 0);

      // Leaving the field restores it; the field that now has focus stays
      // (or is scrolled just) above the keyboard.
      FocusManager.instance.primaryFocus!.nextFocus();
      await tester.pumpAndSettle();
      expect(find.byType(AuthAppIcon), findsOneWidget);
      expect(focused(tester, 'Benutzername'), isTrue);
      expect(tester.getRect(field('Benutzername')).bottom,
          lessThanOrEqualTo(850 - 420.0 - 16));
    });

    testWidgets('closing the keyboard restores the header', (tester) async {
      await pumpPhoneLogin(tester);
      await tester.tap(field('Schule'));
      await slideKeyboard(tester, 0, 420);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(AuthAppIcon), findsNothing);
      await slideKeyboard(tester, 420, 0);
      await tester.pumpAndSettle();
      expect(find.byType(AuthAppIcon), findsOneWidget);
    });

    testWidgets('with reduced motion the header swaps without animating',
        (tester) async {
      await pumpPhoneLogin(tester, reducedMotion: true);
      await tester.tap(field('Schule'));
      await slideKeyboard(tester, 0, 420);
      // The decision waits for the keyboard to settle (80 ms), then the
      // header is gone within a short fade, without sliding or resizing.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(AuthAppIcon), findsNothing);
    });
  });
}
