import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/credits_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

/// The general thank-you of the page (#152), which thanks nobody by name.
const creditsThanks = {
  'de': 'Danke für euer Feedback, eure Zeit, eure Ideen und eure '
      'Unterstützung. Ohne euch wäre diese App nicht das, was sie heute ist.',
  'en': 'Thank you for your feedback, your time, your ideas and your support. '
      'Without you, this app would not be what it is today.',
  'it': 'Grazie per il vostro feedback, il vostro tempo, le vostre idee e il '
      'vostro sostegno. Senza di voi questa app non sarebbe quella che è oggi.',
  'lld': 'Dilan por vost feedback, vost tëmp, vostes idees y vost sostëgn. '
      "Zënza de vos ne foss chësta app nia chël ch'ara é encö.",
};

/// No card of a single person: no avatar with initials, no name.
void expectNoPersonCard() {
  expect(find.byType(CircleAvatar), findsNothing);
  expect(find.textContaining('Gabriel'), findsNothing);
  expect(find.text('GA'), findsNothing);
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('credits are the last settings entry and open the page',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(
      tester,
      store: createStore(
        initialState: AppState(
          (b) => b.settingsState.languageCode = AppLanguage.en.code,
        ),
      ),
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    final tile = find.byKey(const Key('settings-credits-tile'));
    await tester.scrollUntilVisible(tile, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.extentAfter, lessThan(200));

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(CreditsPage), findsOneWidget);
    expect(find.text('Thank you!'), findsOneWidget);
    expect(find.text(creditsThanks['en']!), findsOneWidget);
    expectNoPersonCard();
  });

  for (final language in AppLanguage.values) {
    for (final (name, mode, amoled) in [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('amoled', ThemeMode.dark, true),
    ]) {
      testWidgets('credits page renders (${language.code}, $name)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
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
          home: const CreditsPage(),
        );
        await settleFor(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(creditsThanks[language.code]!), findsOneWidget);
        expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Card),
            matching: find.text(creditsThanks[language.code]!),
          ),
          findsOneWidget,
        );
        expectNoPersonCard();
        expect(find.textContaining('credits.'), findsNothing);
      });
    }
  }

  for (final (name, size) in [
    ('narrow phone', const Size(320, 640)),
    ('wide window', const Size(1280, 800)),
  ]) {
    testWidgets('legacy credits fit a $name at text scale 2', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester,
        store: createStore(
          initialState: AppState(
            (b) => b.settingsState.languageCode = AppLanguage.lld.code,
          ),
        ),
        home: const CreditsPage(),
      );
      await settleFor(tester);
      expect(tester.takeException(), isNull);
      final text = tester.getRect(find.text(creditsThanks['lld']!));
      expect(text.width, lessThanOrEqualTo(560));
      expect((text.center.dx - size.width / 2).abs(), lessThan(1));
    });
  }
}
