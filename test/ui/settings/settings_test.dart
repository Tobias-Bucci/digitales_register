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
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/subject_swatch_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('accent colors are chosen from the curated accents',
      (tester) async {
    await useLargeSurface(tester);
    addTearDown(() => themeController.setAccent(AppAccent.blue));
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
    expect(themeController.accent, AppAccent.blue);
    final violet = find.byKey(const Key('accent-violet'));
    await tester.ensureVisible(violet);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Violet'), findsOneWidget);
    await tester.tap(violet);
    await tester.pumpAndSettle();
    expect(themeController.accent, AppAccent.violet);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(accentPreferenceKey), 'violet');
    expect(tester.getSemantics(violet), containsSemantics(isSelected: true));
  });

  testWidgets('subject colors are chosen from the curated palette swatches',
      (tester) async {
    await useLargeSurface(tester);
    final store = createStore(
      initialState: AppState(
        (b) => b
          ..settingsState.languageCode = AppLanguage.en.code
          ..settingsState.subjectThemes['Mathematik'] = SubjectTheme(
            (t) => t
              ..color = AppPalette.subjectSwatches.first.toARGB32()
              ..thick = 2,
          ),
      ),
    );
    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
      themeMode: ThemeMode.dark,
    );
    await settleFor(tester);
    expect(find.byKey(const Key('settings-contrast-color-tile')), findsNothing);
    final tile = find.byKey(const Key('settings-subject-colors-tile'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematik'));
    await tester.pumpAndSettle();

    expect(find.byType(SubjectSwatchPicker), findsOneWidget);
    expect(find.byTooltip('Blue'), findsOneWidget);
    await tester.tap(find.byTooltip('Teal'));
    await tester.pumpAndSettle();

    expect(find.byType(SubjectSwatchPicker), findsNothing);
    expect(
      store.state.settingsState.subjectThemes['Mathematik']!.color,
      const Color(0xFF13948A).toARGB32(),
    );
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
