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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  final settingsList = find.byType(ListView);

  setUp(() async {
    await bootstrapTestEnvironment();
    await themeController.setThemePreference(AppThemePreference.system);
  });

  tearDown(resetTestState);

  group('subject nicks', () {
    testWidgets('scrollToSubjectNicks opens the add dialog immediately',
        (tester) async {
      final store = createStore(
        initialState: AppState((b) => b.settingsState.scrollToSubjectNicks = true),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 400));

      expect(find.byType(InfoDialog), findsOneWidget);
      expect(find.text('Kürzel hinzufügen'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('adds a subject nick', (tester) async {
      final store = createStore();

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 400));

      await tester.scrollUntilVisible(
        find.text('Fächerkürzel'),
        200,
        scrollable: settingsList,
      );
      await tester.tap(find.text('Fächerkürzel'));
      await tester.pumpAndSettle();
      tester.widget<IconButton>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Fächerkürzel'),
            matching: find.byType(ExpansionTile),
          ),
          matching: find.byType(IconButton),
        ).first,
      ).onPressed!();
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).at(0), 'Fach1');
      await tester.enterText(find.byType(EditableText).at(1), 'F1');
      await tester.pump();
      await tester.tap(find.text('Fertig'));
      await tester.pump();
      await settleFor(tester);

      expect(store.state.settingsState.subjectNicks['Fach1'], 'F1');
    });

    testWidgets('removes an existing subject nick', (tester) async {
      final store = createStore(
        initialState: AppState(
          (b) => b.settingsState.subjectNicks =
              MapBuilder<String, String>(<String, String>{'Fach1': 'F1'}),
        ),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 400));

      await tester.scrollUntilVisible(
        find.text('Fächerkürzel'),
        200,
        scrollable: settingsList,
      );
      await tester.tap(find.text('Fächerkürzel'));
      await tester.pump();
      await settleFor(tester);

      expect(find.text('Fach1'), findsOneWidget);
      final deleteButton = find.ancestor(
        of: find.descendant(
          of: find.ancestor(of: find.text('Fach1'), matching: find.byType(ListTile)),
          matching: find.byIcon(Icons.delete),
        ),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(deleteButton).onPressed!();
      await tester.pump();
      await settleFor(tester);

      expect(store.state.settingsState.subjectNicks['Fach1'], isNull);
    });
  });

  group('calendar sync', () {
    testWidgets('shows the Android-only calendar sync toggle', (tester) async {
      isAndroidOverride = () => true;
      final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = 'en'),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      await tester.scrollUntilVisible(
        find.text('Sync school items to calendar'),
        150,
        scrollable: settingsList,
      );

      expect(find.text('Sync school items to calendar'), findsOneWidget);
    });

    testWidgets('hides the calendar sync toggle on non-Android platforms',
        (tester) async {
      isAndroidOverride = () => false;
      final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = 'en'),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      expect(find.text('Sync school items to calendar'), findsNothing);
    });

    testWidgets('disabling calendar sync opens the keep/remove dialog',
        (tester) async {
      isAndroidOverride = () => true;
      final store = createStore(
        initialState: AppState((b) {
          b.settingsState
            ..languageCode = 'en'
            ..calendarSyncEnabled = true;
        }),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      await tester.scrollUntilVisible(
        find.text('Sync school items to calendar'),
        150,
        scrollable: settingsList,
      );
      await tester.tap(find.text('Sync school items to calendar'));
      await tester.pump();
      await settleFor(tester);

      expect(find.text('Turn off calendar sync?'), findsOneWidget);
      expect(find.text('Keep events'), findsOneWidget);
      expect(find.text('Remove events'), findsOneWidget);
    });
  });

  group('theme selection', () {
    testWidgets('selected radio follows the active theme preference',
        (tester) async {
      final store = createStore();

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      Finder activeThemeGroup(String themeName) {
        return find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString().startsWith('RadioGroup') &&
              (widget as dynamic).groupValue.toString() == '_Theme.$themeName',
        );
      }

      expect(activeThemeGroup('followDevice'), findsOneWidget);

      await themeController.setThemePreference(AppThemePreference.light);
      await tester.pumpAndSettle();

      expect(themeController.themePreference, AppThemePreference.light);
      expect(activeThemeGroup('light'), findsOneWidget);
      expect(activeThemeGroup('followDevice'), findsNothing);

      await themeController.setThemePreference(AppThemePreference.dark);
      await tester.pumpAndSettle();

      expect(themeController.themePreference, AppThemePreference.dark);
      expect(activeThemeGroup('dark'), findsOneWidget);
      expect(activeThemeGroup('light'), findsNothing);
    });
  });

  group('grades average ignore list', () {
    testWidgets('adds and removes an ignored subject', (tester) async {
      final store = createStore();

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      await tester.scrollUntilVisible(
        find.text('Fächer aus dem Notendurchschnitt ausschließen'),
        150,
        scrollable: settingsList,
      );
      tester.widget<IconButton>(
        find.ancestor(
          of: find.descendant(
            of: find.ancestor(
              of: find.text('Fächer aus dem Notendurchschnitt ausschließen'),
              matching: find.byType(ListTile),
            ),
            matching: find.byIcon(Icons.add),
          ),
          matching: find.byType(IconButton),
        ),
      ).onPressed!();
      await tester.pump();
      await settleFor(tester);

      await tester.enterText(find.byType(EditableText).first, 'Fach1');
      await tester.pump();
      await tester.tap(find.text('Fertig'));
      await tester.pump();
      await settleFor(tester);

      expect(
        store.state.settingsState.ignoreForGradesAverage,
        BuiltList<String>(const <String>['Fach1']),
      );

      tester.widget<IconButton>(
        find.ancestor(
          of: find.descendant(
            of: find.ancestor(of: find.text('Fach1'), matching: find.byType(ListTile)),
            matching: find.byIcon(Icons.close),
          ),
          matching: find.byType(IconButton),
        ),
      ).onPressed!();
      await tester.pump();
      await settleFor(tester);

      expect(store.state.settingsState.ignoreForGradesAverage, isEmpty);
    });
  });

  group('favorite subjects', () {
    testWidgets('adds and removes a favorite subject', (tester) async {
      final store = createStore(initialState: buildStateWithSubjects());

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      await tester.scrollUntilVisible(
        find.text('Fokusfächer verwalten'),
        150,
        scrollable: settingsList,
      );
      tester.widget<IconButton>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Fokusfächer verwalten').last,
            matching: find.byType(ListTile),
          ),
          matching: find.byType(IconButton),
        ),
      ).onPressed!();
      await tester.pump();
      await settleFor(tester);

      expect(find.byType(InfoDialog), findsOneWidget);
      expect(find.text('Fokusfächer verwalten'), findsWidgets);

      await tester.enterText(find.byType(EditableText).first, 'Fach1');
      await tester.pump();
      await tester.tap(find.text('Fertig'));
      await tester.pump();
      await settleFor(tester);

      expect(
        store.state.settingsState.favoriteSubjects,
        BuiltList<String>(const <String>['Fach1']),
      );

      await tester.scrollUntilVisible(
        find.text('Fach1'),
        100,
        scrollable: settingsList,
      );
      tester.widget<IconButton>(
        find.descendant(
          of: find.ancestor(of: find.text('Fach1').last, matching: find.byType(ListTile)),
          matching: find.byType(IconButton),
        ),
      ).onPressed!();
      await tester.pump();
      await settleFor(tester);

      expect(store.state.settingsState.favoriteSubjects, isEmpty);
    });

    testWidgets('disables adding duplicates once all favorite subjects are used',
        (tester) async {
      final store = createStore(
        initialState: buildStateWithSubjects(
          favoriteSubjects: const <String>['Fach1'],
        ),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester);

      await tester.scrollUntilVisible(
        find.text('Fokusfächer verwalten'),
        150,
        scrollable: settingsList,
      );

      final addButton = tester.widget<IconButton>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Fokusfächer verwalten').last,
            matching: find.byType(ListTile),
          ),
          matching: find.byType(IconButton),
        ),
      );

      expect(addButton.onPressed, isNull);
    });
  });

  testWidgets('stores language selection immediately', (tester) async {
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    await tester.scrollUntilVisible(
      find.text('Sprache auswählen'),
      150,
      scrollable: settingsList,
    );
    await tester.tap(find.byType(DropdownButton<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Englisch').last);
    await tester.pumpAndSettle();

    expect(store.state.settingsState.languageCode, AppLanguage.en.code);
    expect(find.text('Einstellungen'), findsOneWidget);
  });
}
