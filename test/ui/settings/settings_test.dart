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

import 'package:dr/app_state.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    await themeController.setThemePreference(AppThemePreference.system);
  });

  tearDown(resetTestState);

  Future<void> useLargeSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'accent picker saves and reopens the exact custom color in dark mode',
      (tester) async {
    await useLargeSurface(tester);
    const original = Color(0xFF0000FF);
    const selected = Color(0xFFFF00FF);
    await themeController.setContrastColor(original);
    addTearDown(() => themeController.setContrastColor(defaultContrastColor));
    final store = createStore(
      initialState: AppState(
        (b) => b.settingsState.languageCode = AppLanguage.en.code,
      ),
    );
    // Deliberately use a different theme accent to ensure the picker and swatch
    // read the stored selection rather than a derived or transitional theme.
    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
      themeMode: ThemeMode.dark,
      darkTheme:
          ThemeData(colorSchemeSeed: Colors.green, brightness: Brightness.dark),
    );
    await settleFor(tester);
    final tile = find.byKey(const Key('settings-contrast-color-tile'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    Color swatchColor() {
      final container = tester.widget<ListTile>(tile).trailing! as Container;
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(swatchColor(), original);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<ColorPicker>(find.byType(ColorPicker)).pickerColor,
        original);
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(selected);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Select'));
    await tester.pumpAndSettle();
    expect(themeController.contrastColor, selected);
    expect(swatchColor(), selected);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(contrastColorPreferenceKey), selected.toARGB32());
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<ColorPicker>(find.byType(ColorPicker)).pickerColor,
        selected);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(themeController.contrastColor, selected);
  });

  Future<void> scrollToText(WidgetTester tester, String text) async {
    for (var i = 0; i < 10 && find.text(text).evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(600, 1200), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('shows the compact settings groups on the main page',
      (tester) async {
    await useLargeSurface(tester);
    final store = createStore(
      initialState: AppState(
        (b) => b.settingsState.languageCode = AppLanguage.en.code,
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);

    await scrollToText(tester, 'Dashboard');
    expect(find.text('Dashboard'), findsOneWidget);

    await scrollToText(tester, 'Calendar');
    expect(find.text('Calendar'), findsOneWidget);

    await scrollToText(tester, 'Advanced');
    expect(find.text('Advanced'), findsOneWidget);

    expect(find.text('Restore default abbreviations'), findsNothing);
    expect(find.text('Add primary teacher'), findsNothing);
    expect(find.text('Exclude subjects from the grade average'), findsNothing);
    expect(find.byKey(const Key('settings-demo-date-picker')), findsNothing);
    expect(
      find.byKey(const Key('settings-demo-assessment-range')),
      findsNothing,
    );
    expect(find.byKey(const Key('settings-demo-clear-cache')), findsNothing);
  });

  testWidgets('shows simulated date controls only for the demo guest',
      (tester) async {
    await useLargeSurface(tester);
    appClock.setDemoMode(true);
    final store = createStore(
      initialState: AppState(
        (b) => b
          ..url = ''
          ..loginState.username = 'demo'
          ..settingsState.languageCode = AppLanguage.en.code,
      ),
    );

    await pumpApp(tester, store: store, home: SettingsPageContainer());
    await settleFor(tester);

    expect(find.text('Simulated date'), findsOneWidget);
    expect(find.byKey(const Key('settings-demo-date-picker')), findsOneWidget);
    expect(find.byKey(const Key('settings-demo-date-start')), findsOneWidget);
    expect(find.byKey(const Key('settings-demo-date-end')), findsOneWidget);
    expect(find.byKey(const Key('settings-demo-date-reset')), findsOneWidget);
    expect(
      find.byKey(const Key('settings-demo-assessment-range')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-demo-clear-cache')), findsOneWidget);
  });
}
