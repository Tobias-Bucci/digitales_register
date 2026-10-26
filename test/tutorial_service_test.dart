import 'package:dr/app_language_controller.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/theme_controller.dart';
import 'package:dr/tutorial/intro_tour.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_harness.dart';
import 'support/fixtures.dart';

void main() {
  setUp(() => bootstrapTestEnvironment(
      fixedNow: fixtureNow, sharedPreferences: const {}));
  tearDown(resetTestState);

  for (final history in <Map<String, Object>>[
    {'tutorial.v2.offered': true},
    {'tutorial.v2.completed.dashboard': true},
    {'tutorial.v2.progress': 40},
  ]) {
    test('users of the old tour are not offered the intro: $history',
        () async {
      SharedPreferences.setMockInitialValues(history);
      final tour = TutorialService();
      expect(await tour.shouldOffer(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('tutorial.v2.')),
          isEmpty);
      expect(prefs.getBool(TutorialService.seenKey), isTrue);
      expect(await tour.shouldOffer(), isFalse);
      tour.dispose();
    });
  }

  test('new installations are offered the intro once', () async {
    final tour = TutorialService();
    expect(await tour.shouldOffer(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(TutorialService.seenKey, true);
    expect(await tour.shouldOffer(), isFalse);
    tour.dispose();
  });

  test('the intro stays short and focused', () {
    expect(introTourPages.map((p) => p.key),
        ['welcome', 'dashboard', 'grades', 'calendar', 'settings']);
  });

  for (final language in AppLanguage.values) {
    test('every intro text is translated in ${language.code}', () async {
      final l10n = await AppLocalizations.load(language.locale);
      for (final page in introTourPages) {
        for (final suffix in ['title', 'body']) {
          final key = 'tutorial.page.${page.key}.$suffix';
          expect(l10n.text(key), isNot(key));
          expect(l10n.text(key).trim(), isNotEmpty);
          if (suffix == 'body') {
            // Short texts: at most two sentences per page.
            expect(
              RegExp(r'[.!?](\s|$)').allMatches(l10n.text(key)).length,
              lessThanOrEqualTo(2),
              reason: key,
            );
          }
        }
      }
      for (final key in [
        'skip',
        'back',
        'next',
        'finish',
        'progress',
        'language.label',
      ]) {
        expect(l10n.text('tutorial.$key'), isNot('tutorial.$key'));
      }
    });
  }

  testWidgets('an idle dashboard shows the intro without a tap; skip ends it',
      (tester) async {
    final tour = TutorialService();
    final store = createStore();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Dashboard')));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    tour.scheduleOffer(tester.element(find.text('Dashboard')));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'adding a post-frame callback alone leaves an idle UI waiting');
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsOneWidget);
    expect(tour.active, isTrue);
    expect(find.text('Willkommen!'), findsOneWidget);
    expect(find.text('Schritt 1 von 5'), findsOneWidget);

    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    expect(find.byType(IntroTour), findsNothing);
    expect(tour.active, isFalse);
    expect(await tour.shouldOffer(), isFalse);
    tour.dispose();
    store.dispose();
  });

  testWidgets('next, back and finish walk through all pages', (tester) async {
    final tour = TutorialService();
    final store = createStore();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Dashboard')));
    final starting = tour.start(tester.element(find.text('Dashboard')));
    await tester.pumpAndSettle();

    final next = find.byKey(const Key('intro-next'));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 5'), findsOneWidget);
    expect(find.text('Alles auf einen Blick'), findsOneWidget);
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 1 von 5'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(find.text('Schritt 5 von 5'), findsOneWidget);
    expect(find.text("Los geht's"), findsOneWidget);
    await tester.tap(next);
    await tester.pumpAndSettle();
    await starting;
    expect(find.byType(IntroTour), findsNothing);
    expect(tour.active, isFalse);
    tour.dispose();
    store.dispose();
  });

  testWidgets('choosing a language on the first page applies it',
      (tester) async {
    final store = createStore(appActions: app.actions, withMiddleware: true);
    final tour = TutorialService();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Home')));
    final starting = tour.start(tester.element(find.text('Home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Italiano'));
    await tester.pumpAndSettle();
    expect(store.state.settingsState.languageCode, 'it');
    expect(appLanguageController.language, AppLanguage.it);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();
    await starting;
    await tester.pumpWidget(const SizedBox.shrink());
    tour.dispose();
    store.dispose();
  });

  for (final language in AppLanguage.values) {
    for (final (name, mode, amoled) in [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('amoled', ThemeMode.dark, true),
    ]) {
      for (final size in [const Size(320, 560), const Size(1024, 700)]) {
        testWidgets(
            'every page fits (${language.code}, $name, '
            '${size.width.toInt()}x${size.height.toInt()})', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpApp(
            tester,
            store: createStore(
              initialState: AppState(
                (b) => b.settingsState.languageCode = language.code,
              ),
            ),
            themeMode: mode,
            darkTheme: themeController.buildTheme(
              brightness: Brightness.dark,
              amoledMode: amoled,
            ),
            home: IntroTour(language: language, onLanguageSelected: (_) {}),
          );
          await tester.pumpAndSettle();
          for (var page = 0; page < introTourPages.length; page++) {
            expect(tester.takeException(), isNull, reason: 'page $page');
            final button = tester.getRect(find.byKey(const Key('intro-next')));
            expect(button.bottom, lessThanOrEqualTo(size.height));
            expect(button.height, greaterThanOrEqualTo(48));
            if (page < introTourPages.length - 1) {
              await tester.tap(find.byKey(const Key('intro-next')));
              await tester.pumpAndSettle();
            }
          }
        });
      }
    }
  }
}
