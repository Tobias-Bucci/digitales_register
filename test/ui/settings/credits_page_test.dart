import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/credits_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

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
    expect(find.text('Gabriel Albarello'), findsOneWidget);
    expect(find.text('GA'), findsOneWidget);
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
        expect(find.text('Gabriel Albarello'), findsOneWidget);
        expect(find.textContaining('credits.'), findsNothing);
      });
    }
  }
}
