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

import 'dart:async';

import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/tutorial/design_choice.dart';
import 'package:dr/tutorial/intro_tour.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

/// The German headline of every step, in order.
const _titles = [
  'Willkommen!',
  'Alles auf einen Blick',
  'Immer in Reichweite',
  'Nichts verpassen',
  'Fächerfarben',
  'Ganz nach deinem Geschmack',
  'Wähle dein Design',
];

final _next = find.byKey(const Key('intro-next'));

/// Opens the tour over a plain page. [result] holds what it popped with.
class _Opened {
  bool? result;
  bool closed = false;
  final chosen = <bool>[];
}

Future<_Opened> _open(
  WidgetTester tester, {
  bool designChoicePending = false,
  bool legacyDesign = false,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final opened = _Opened();
  await pumpApp(
    tester,
    store: createStore(),
    themeMode: themeMode,
    home: const Scaffold(body: Text('Home')),
  );
  unawaited(Navigator.of(tester.element(find.text('Home')))
      .push(IntroTour.route(
    language: AppLanguage.de,
    onLanguageSelected: (_) {},
    legacyDesign: legacyDesign,
    designChoicePending: designChoicePending,
    onDesignChosen: opened.chosen.add,
  ))
      .then((value) {
    opened
      ..result = value
      ..closed = true;
  }));
  await tester.pumpAndSettle();
  return opened;
}

void _expectStep(WidgetTester tester, int step) {
  expect(find.text('Schritt $step von ${_titles.length}'), findsOneWidget);
  expect(find.text(_titles[step - 1]), findsOneWidget);
}

void main() {
  setUp(() => bootstrapTestEnvironment(fixedNow: fixtureNow));
  tearDown(resetTestState);

  test('the tour covers the main areas and ends with the design', () {
    expect(introTourPages, hasLength(_titles.length));
    expect(introTourPages.first.key, 'welcome');
    expect(introTourPages.last.key, 'design');
  });

  testWidgets('next and back walk through every step, then finish',
      (tester) async {
    final opened = await _open(tester);
    final semantics = tester.ensureSemantics();
    for (var step = 1; step <= _titles.length; step++) {
      _expectStep(tester, step);
      expect(tester.getSemantics(find.text(_titles[step - 1])),
          containsSemantics(isHeader: true),
          reason: 'the title of step $step is a heading');
      expect(
          tester.getSemantics(find.text('Schritt $step von ${_titles.length}')),
          containsSemantics(isLiveRegion: true),
          reason: 'the position is announced');
      if (step < _titles.length) {
        await tester.tap(_next);
        await tester.pumpAndSettle();
      }
    }
    expect(find.byType(DesignChoicePicker), findsOneWidget);
    expect(find.text("Los geht's"), findsOneWidget);

    for (var step = _titles.length; step > 1; step--) {
      await tester.tap(find.text('Zurück'));
      await tester.pumpAndSettle();
      _expectStep(tester, step - 1);
    }
    // Back is gone on the first step, also for screen readers.
    expect(find.semantics.byLabel('Zurück'), findsNothing);

    for (var step = 1; step < _titles.length; step++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
    }
    expect(find.semantics.byLabel('Überspringen'), findsNothing,
        reason: 'nothing left to skip on the last step');
    await tester.tap(_next);
    await tester.pumpAndSettle();
    expect(opened.result, isTrue);
    expect(opened.chosen, [false]);
    semantics.dispose();
  });

  testWidgets('the illustrations are not read out', (tester) async {
    await _open(tester);
    final semantics = tester.ensureSemantics();
    // Labels drawn inside the pictures of the notification and settings steps.
    for (var step = 1; step < _titles.length; step++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
      for (final label in [
        'Benachrichtigungen',
        'Nur ungelesene',
        'Einführung ansehen',
        'Extras',
        'Leuchtend',
      ]) {
        expect(find.semantics.byLabel(label), findsNothing,
            reason: '$label on step ${step + 1}');
      }
    }
    semantics.dispose();
  });

  testWidgets('skipping closes the tour once a design is chosen',
      (tester) async {
    final opened = await _open(tester);
    await tester.tap(_next);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsNothing);
    expect(opened.result, isFalse);
    expect(opened.chosen, isEmpty, reason: 'the design stays as it is');
  });

  testWidgets('skipping leads to the design while none is chosen',
      (tester) async {
    final opened = await _open(tester, designChoicePending: true);
    for (var step = 1; step < 4; step++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    _expectStep(tester, _titles.length);
    expect(opened.closed, isFalse);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Überspringen'))
            .onPressed,
        isNull);
  });

  for (final legacy in [false, true]) {
    testWidgets('finishing passes on the ${legacy ? 'legacy' : 'new'} design',
        (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final store = createStore(newDesign: !legacy);
      final service = TutorialService();
      await pumpApp(tester,
          store: store, home: const Scaffold(body: Text('Dashboard')));
      final starting = service.start(tester.element(find.text('Dashboard')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
      // Pick the other design than the one in use, then back again.
      await tester.tap(find
          .byKey(Key(legacy ? 'design-choice-new' : 'design-choice-legacy')));
      await tester.pumpAndSettle();
      await tester.tap(find
          .byKey(Key(legacy ? 'design-choice-legacy' : 'design-choice-new')));
      await tester.pumpAndSettle();
      await tester.tap(_next);
      await tester.pumpAndSettle();
      await starting;
      expect(find.byType(IntroTour), findsNothing);
      expect(store.state.settingsState.legacyDesign, legacy);
      expect(await service.designChoicePending(), isFalse);
      service.dispose();
      await store.dispose();
    });
  }

  testWidgets('the keyboard pages, finishes and skips', (tester) async {
    final opened = await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    _expectStep(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _expectStep(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    _expectStep(tester, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(opened.result, isFalse);
  });

  testWidgets('with reduced motion the step changes at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    _expectStep(tester, 2);
    // Without a slide, the new step is in place after a single frame.
    final title = tester.getRect(find.text(_titles[1]));
    expect(title.left, greaterThanOrEqualTo(0));
    expect(title.right, lessThanOrEqualTo(tester.view.physicalSize.width));
    final opacity = tester.widget<AnimatedOpacity>(find
        .ancestor(
            of: find.text(_titles[1]), matching: find.byType(AnimatedOpacity))
        .first);
    expect(opacity.opacity, 1);
    expect(opacity.duration, Duration.zero);
  });

  for (final (name, mode) in [
    ('light', ThemeMode.light),
    ('dark', ThemeMode.dark),
  ]) {
    for (final size in [
      const Size(360, 640),
      const Size(412, 915),
      const Size(1280, 800),
    ]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
            'every step fits ($name, ${size.width.toInt()}x'
            '${size.height.toInt()}, text $textScale)', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpApp(
            tester,
            store: createStore(),
            themeMode: mode,
            darkTheme: themeController.buildTheme(
                brightness: Brightness.dark, amoledMode: false),
            home: IntroTour(
              language: AppLanguage.de,
              onLanguageSelected: (_) {},
              designChoicePending: true,
            ),
          );
          await tester.pumpAndSettle();
          for (var step = 1; step <= _titles.length; step++) {
            expect(tester.takeException(), isNull, reason: 'step $step');
            final title = find.text(_titles[step - 1]);
            await tester.ensureVisible(title);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'step $step');
            final button = tester.getRect(_next);
            expect(button.bottom, lessThanOrEqualTo(size.height));
            expect(button.height, greaterThanOrEqualTo(48));
            if (step < _titles.length) {
              await tester.tap(_next);
              await tester.pumpAndSettle();
            }
          }
        });
      }
    }
  }

  testWidgets('the settings replay the tour', (tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore();
    await pumpApp(tester, store: store, home: SettingsPageContainer());
    await settleFor(tester);
    final entry = find.text('Einführung ansehen');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    expect(find.text('Die wichtigsten Funktionen in sieben kurzen Schritten'),
        findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(IntroTour), findsOneWidget);
    expect(tutorialService.active, isTrue);
    _expectStep(tester, 1);
    for (var step = 1; step < _titles.length; step++) {
      await tester.tap(_next);
      await tester.pumpAndSettle();
    }
    // A design was chosen before, so it is preselected and kept.
    expect(tester.getSemantics(find.byKey(const Key('design-choice-legacy'))),
        containsSemantics(isChecked: true));
    await tester.tap(_next);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsNothing);
    expect(tutorialService.active, isFalse);
    expect(store.state.settingsState.legacyDesign, isTrue);

    // And once more, skipped this time.
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsNothing);
    expect(tutorialService.active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.dispose();
  });
}
