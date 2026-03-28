import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/ui/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
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
    });

    testWidgets('adds a subject nick', (tester) async {
      final store = createStore(
        initialState: AppState((b) => b.settingsState.scrollToSubjectNicks = true),
      );

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField).first, 'Fach1');
      await tester.enterText(find.byType(TextField).last, 'F1');
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

      await tester.scrollUntilVisible(find.text('Fächerkürzel'), 200);
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

  group('grades average ignore list', () {
    testWidgets('adds and removes an ignored subject', (tester) async {
      final store = createStore();

      await pumpApp(
        tester,
        store: store,
        home: SettingsPageContainer(),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('Fächer aus dem Notendurchschnitt ausschließen'),
        150,
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

      await tester.enterText(find.byType(TextField), 'Fach1');
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
      await settleFor(tester, duration: const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(find.text('Fokusfächer verwalten'), 150);
      tester.widget<IconButton>(
        find.ancestor(
          of: find.descendant(
            of: find.ancestor(
              of: find.text('Fokusfächer verwalten'),
              matching: find.byType(ListTile),
            ),
            matching: find.byIcon(Icons.add),
          ),
          matching: find.byType(IconButton),
        ),
      ).onPressed!();
      await tester.pump();
      await settleFor(tester);

      expect(find.byType(InfoDialog), findsOneWidget);
      expect(find.text('Fokusfach hinzufügen'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Fach1');
      await tester.pump();
      await tester.tap(find.text('Fertig'));
      await tester.pump();
      await settleFor(tester);

      expect(
        store.state.settingsState.favoriteSubjects,
        BuiltList<String>(const <String>['Fach1']),
      );

      await tester.scrollUntilVisible(find.text('Fach1'), 100);
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
      await settleFor(tester, duration: const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(find.text('Fokusfächer verwalten'), 150);

      final addButton = tester.widget<IconButton>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Fokusfächer verwalten'),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(IconButton),
        ),
      );

      expect(addButton.onPressed, isNull);
    });
  });
}
