import 'dart:convert';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/tutorial/design_choice.dart';
import 'package:dr/tutorial/intro_tour.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

/// The preferences an earlier version leaves behind: the intro was seen and
/// the settings were saved, but no design was ever chosen.
Map<String, Object> _updatedFrom({required bool legacyDesign}) => {
      TutorialService.seenKey: true,
      'lastObservedAppVersion': '2.0.0',
      globalSettingsPreferenceKey: jsonEncode(serializers
          .serialize(SettingsState((b) => b..legacyDesign = legacyDesign))),
    };

Future<void> _showDashboard(
  WidgetTester tester,
  Store<AppState, AppStateBuilder, AppActions> store,
) =>
    pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Dashboard')));

Future<void> _offer(WidgetTester tester, TutorialService service) async {
  final offering = service.maybeOffer(tester.element(find.text('Dashboard')));
  await tester.pumpAndSettle();
  // Lets the preference reads finish in tests that show nothing.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
  if (!service.active) await offering;
}

void main() {
  setUp(() => bootstrapTestEnvironment(
      fixedNow: fixtureNow, sharedPreferences: const {}));
  tearDown(resetTestState);

  testWidgets('a new installation chooses at the end of the intro',
      (tester) async {
    final service = TutorialService();
    final store = createStore(newDesign: true);
    await _showDashboard(tester, store);
    await _offer(tester, service);

    expect(find.byType(IntroTour), findsOneWidget);
    expect(find.byType(DesignChoiceScreen), findsNothing);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignChoicePicker), findsOneWidget);
    expect(find.text('Empfohlen'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('design-choice-new'))),
        containsSemantics(isChecked: true),
        reason: 'new installations start with the new design selected');

    await tester.tap(find.byKey(const Key('design-choice-legacy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('intro-next')));
    await tester.pumpAndSettle();

    expect(find.byType(IntroTour), findsNothing);
    expect(store.state.settingsState.legacyDesign, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(TutorialService.designChoiceKey), isTrue);
    expect(prefs.getBool(TutorialService.seenKey), isTrue);
    service.dispose();
    await store.dispose();
  });

  for (final legacy in [true, false]) {
    testWidgets(
        'an update asks once on its own screen, keeping '
        '${legacy ? 'Legacy' : 'New'} selected', (tester) async {
      SharedPreferences.setMockInitialValues(
          _updatedFrom(legacyDesign: legacy));
      final settings = await settingsPersistenceService.load();
      expect(settings!.legacyDesign, legacy);
      final store = createStore(
          appActions: app.actions,
          withMiddleware: true,
          initialState: AppState((b) => b.settingsState.replace(settings)),
          newDesign: !legacy);
      final service = TutorialService();
      await _showDashboard(tester, store);
      await _offer(tester, service);

      expect(find.byType(IntroTour), findsNothing,
          reason: 'people who updated do not get the whole intro again');
      expect(find.byType(DesignChoiceScreen), findsOneWidget);
      expect(
          find.text(
              legacy ? 'Legacy-Design verwenden' : 'Neues Design verwenden'),
          findsOneWidget);
      expect(
          tester.getSemantics(find.byKey(
              Key(legacy ? 'design-choice-legacy' : 'design-choice-new'))),
          containsSemantics(isChecked: true));

      await tester.tap(find.byKey(const Key('design-choice-confirm')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byType(DesignChoiceScreen), findsNothing);
      expect(store.state.settingsState.legacyDesign, legacy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(TutorialService.designChoiceKey), isTrue);

      // The same run, back on the dashboard.
      await _offer(tester, service);
      expect(find.byType(DesignChoiceScreen), findsNothing);

      // The next start of the app.
      final nextStart = TutorialService();
      await _offer(tester, nextStart);
      expect(find.byType(DesignChoiceScreen), findsNothing);
      expect(find.byType(IntroTour), findsNothing);

      // A later update: another version, and the flag is all that counts.
      await prefs.setString('lastObservedAppVersion', '9.9.9');
      final laterVersion = TutorialService();
      await _offer(tester, laterVersion);
      expect(find.byType(DesignChoiceScreen), findsNothing);
      expect(find.byType(IntroTour), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      for (final s in [service, nextStart, laterVersion]) {
        s.dispose();
      }
      await store.dispose();
    });
  }

  testWidgets('switching on the update screen is saved with the settings',
      (tester) async {
    SharedPreferences.setMockInitialValues(_updatedFrom(legacyDesign: true));
    final settings = await settingsPersistenceService.load();
    final store = createStore(
        appActions: app.actions,
        withMiddleware: true,
        initialState: AppState((b) => b.settingsState.replace(settings!)));
    final service = TutorialService();
    await _showDashboard(tester, store);
    await _offer(tester, service);

    await tester.tap(find.byKey(const Key('design-choice-new')));
    await tester.pumpAndSettle();
    expect(find.text('Neues Design verwenden'), findsOneWidget);
    await tester.tap(find.byKey(const Key('design-choice-confirm')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(store.state.settingsState.legacyDesign, isFalse);
    final stored = await tester.runAsync(settingsPersistenceService.load);
    expect(stored!.legacyDesign, isFalse,
        reason: 'the design survives a restart');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(TutorialService.designChoiceKey), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await store.dispose();
  });

  testWidgets('closing without a choice asks again on the next start only',
      (tester) async {
    SharedPreferences.setMockInitialValues(_updatedFrom(legacyDesign: false));
    final store = createStore(newDesign: true);
    final service = TutorialService();
    await _showDashboard(tester, store);
    await _offer(tester, service);
    expect(find.byType(DesignChoiceScreen), findsOneWidget);

    // System back, like an app that is closed in the middle of the choice.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DesignChoiceScreen), findsNothing);
    expect(await service.designChoicePending(), isTrue);

    await _offer(tester, service);
    expect(find.byType(DesignChoiceScreen), findsNothing,
        reason: 'not again in the same run');

    final nextStart = TutorialService();
    await _offer(tester, nextStart);
    expect(find.byType(DesignChoiceScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('design-choice-confirm')));
    await tester.pumpAndSettle();
    expect(await nextStart.designChoicePending(), isFalse);
    service.dispose();
    nextStart.dispose();
    await store.dispose();
  });

  testWidgets('an intro that was stopped before the end asks on its own',
      (tester) async {
    final store = createStore(newDesign: true);
    final service = TutorialService();
    await _showDashboard(tester, store);
    await _offer(tester, service);
    expect(find.byType(IntroTour), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsNothing);

    final nextStart = TutorialService();
    await _offer(tester, nextStart);
    expect(find.byType(IntroTour), findsNothing);
    expect(find.byType(DesignChoiceScreen), findsOneWidget);
    service.dispose();
    nextStart.dispose();
    await store.dispose();
  });

  testWidgets('replaying the intro keeps the design and can be skipped',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      TutorialService.seenKey: true,
      TutorialService.designChoiceKey: true,
    });
    final store = createStore();
    final service = TutorialService();
    await _showDashboard(tester, store);
    final replay = service.start(tester.element(find.text('Dashboard')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    await replay;
    expect(find.byType(IntroTour), findsNothing);
    expect(store.state.settingsState.legacyDesign, isTrue);
    service.dispose();
    await store.dispose();
  });

  for (final (name, mode) in [
    ('light', ThemeMode.light),
    ('dark', ThemeMode.dark),
  ]) {
    for (final size in [
      const Size(320, 560),
      const Size(390, 844),
      const Size(1024, 700),
    ]) {
      for (final textScale in [1.0, 1.6]) {
        testWidgets(
            'the update screen fits ($name, '
            '${size.width.toInt()}x${size.height.toInt()}, text $textScale)',
            (tester) async {
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
            home: const DesignChoiceScreen(legacyDesign: true),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final button =
              tester.getRect(find.byKey(const Key('design-choice-confirm')));
          expect(button.bottom, lessThanOrEqualTo(size.height));
          expect(button.height, greaterThanOrEqualTo(48));
          for (final key in ['design-choice-new', 'design-choice-legacy']) {
            final card = tester.getRect(find.byKey(Key(key)));
            expect(card.width, greaterThanOrEqualTo(48));
            expect(card.height, greaterThanOrEqualTo(48));
          }
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });
      }
    }
  }
}
