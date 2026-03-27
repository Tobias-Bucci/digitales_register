// Copyright (C) 2021 Michael Debertol
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
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/ui/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

AppState _settingsStateWithSubjects({
  List<String> subjects = const ["Fach1"],
  List<String> favoriteSubjects = const [],
}) {
  return AppState(
    (b) {
      b.gradesState.subjects = ListBuilder(
        subjects
            .map(
              (subject) => Subject(
                (b) => b
                  ..name = subject
                  ..gradesAll = MapBuilder()
                  ..grades = MapBuilder()
                  ..observations = MapBuilder(),
              ),
            )
            .toList(),
      );
      b.settingsState.favoriteSubjects = ListBuilder(favoriteSubjects);
    },
  );
}

void main() {
  testGoldens(
    'scrolls to grades settings',
    (tester) async {
      final widget = ReduxProvider(
        store: Store<AppState, AppStateBuilder, AppActions>(
          ReducerBuilder<AppState, AppStateBuilder>().build(),
          AppState((b) => b.settingsState.scrollToGrades = true),
          AppActions(),
        ),
        child: MaterialApp(
          home: SettingsPageContainer(),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SettingsPageContainer),
        matchesGoldenFile("scrolled_to_grades.png"),
      );
    },
  );

  group("subject nicks", () {
    testWidgets(
      'scrolls to subject nicks and adds one directly',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState((b) => b.settingsState.scrollToSubjectNicks = true),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();

        // a dialog should be opened
        expect(find.byType(InfoDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(InfoDialog),
            matching: find.text("Kürzel hinzufügen"),
          ),
          findsOneWidget,
        );
        // text box should already be focused
        tester.testTextInput.enterText("Fach1");
        expect(find.byType(TextField), findsNWidgets(2));
        await tester.enterText(
          find.descendant(
            of: find.byType(InfoDialog),
            matching: find.byType(TextField).last,
          ),
          "F1",
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text("Fertig"));
        expect(store.state.settingsState.subjectNicks["Fach1"], "F1");
      },
    );
    testWidgets(
      'adds a subject nick',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState(),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text("Fächerkürzel"), 200);
        final subjectNicksHeader = find.widgetWithText(
          ListTile,
          "Fächerkürzel",
        );
        tester.widget<ListTile>(subjectNicksHeader).onTap!();
        await tester.pumpAndSettle();
        final addButton = find.ancestor(
          of: find.byIcon(Icons.add).last,
          matching: find.byType(IconButton),
        );
        await tester.ensureVisible(addButton);
        tester.widget<IconButton>(addButton).onPressed!();
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();

        // a dialog should be opened
        expect(find.byType(InfoDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(InfoDialog),
            matching: find.text("Kürzel hinzufügen"),
          ),
          findsOneWidget,
        );
        // text box should already be focused
        tester.testTextInput.enterText("Fach1");
        expect(find.byType(TextField), findsNWidgets(2));
        await tester.enterText(
            find.descendant(
              of: find.byType(InfoDialog),
              matching: find.byType(TextField).last,
            ),
            "F1");
        await tester.pumpAndSettle();
        await tester.tap(find.text("Fertig"));
        expect(store.state.settingsState.subjectNicks["Fach1"], "F1");
      },
    );
    testWidgets(
      'removes a subject nick',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState(
            (b) {
              b.settingsState.subjectNicks = MapBuilder(
                {
                  "Fach1": "f1",
                },
              );
            },
          ),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text("Fächerkürzel"), 200);
        final subjectNicksHeader = find.widgetWithText(
          ListTile,
          "Fächerkürzel",
        );
        tester.widget<ListTile>(subjectNicksHeader).onTap!();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text("Fach1"));
        final nickTile = find.ancestor(
          of: find.text("Fach1"),
          matching: find.byType(ListTile),
        );
        expect(nickTile, findsOneWidget);
        expect(
          find.descendant(
            of: nickTile,
            matching: find.text("Fach1"),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: nickTile,
            matching: find.text(
              "f1",
            ),
          ),
          findsOneWidget,
        );
        final deleteButton = find.ancestor(
          of: find.descendant(
            of: nickTile,
            matching: find.byIcon(Icons.delete),
          ),
          matching: find.byType(IconButton),
        );
        await tester.ensureVisible(deleteButton);
        tester.widget<IconButton>(deleteButton).onPressed!();
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        expect(store.state.settingsState.subjectNicks["Fach1"], null);
      },
    );
    testWidgets(
      'edits a subject nick',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState(
            (b) {
              b.settingsState.subjectNicks = MapBuilder(
                {
                  "Fach1": "f1",
                },
              );
            },
          ),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text("Fächerkürzel"), 200);
        final subjectNicksHeader = find.widgetWithText(
          ListTile,
          "Fächerkürzel",
        );
        tester.widget<ListTile>(subjectNicksHeader).onTap!();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text("Fach1"));
        final nickTile = find.ancestor(
          of: find.text("Fach1"),
          matching: find.byType(ListTile),
        );
        expect(nickTile, findsOneWidget);
        expect(
          find.descendant(
            of: nickTile,
            matching: find.text("Fach1"),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: nickTile,
            matching: find.text(
              "f1",
            ),
          ),
          findsOneWidget,
        );
        final editButton = find.ancestor(
          of: find.descendant(
            of: nickTile,
            matching: find.byIcon(Icons.edit),
          ),
          matching: find.byType(IconButton),
        );
        await tester.ensureVisible(editButton);
        tester.widget<IconButton>(editButton).onPressed!();
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        final dialog = find.byType(InfoDialog);
        expect(dialog, findsOneWidget);

        expect(
          find.descendant(of: dialog, matching: find.text("Fach")),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text("Fach1")),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text("Kürzel")),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialog, matching: find.text("f1")),
          findsOneWidget,
        );

        // Deleting the nick should disable the save button

        await tester.enterText(find.text("f1"), "");

        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ElevatedButton>(
                find.descendant(
                  of: dialog,
                  matching: find.byType(
                    ElevatedButton,
                  ),
                ),
              )
              .enabled,
          isFalse,
        );

        await tester.enterText(find.text(""), "new_nick");
        await tester.pumpAndSettle();

        await tester.tap(find.text("Fertig"));

        await tester.pumpAndSettle();
        expect(store.state.settingsState.subjectNicks["Fach1"], "new_nick");
      },
    );
  });

  group("grades average ignore-list", () {
    testWidgets(
      'adds an item',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState(),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text("Fächer aus dem Notendurchschnitt ausschließen"),
          150,
        );
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.ancestor(
                of: find.text("Fächer aus dem Notendurchschnitt ausschließen"),
                matching: find.byType(ListTile)),
            matching: find.byIcon(Icons.add),
          ),
        );
        await tester.pumpAndSettle();

        // a dialog should be opened
        expect(find.byType(InfoDialog), findsOneWidget);
        // the text box should already be focused
        tester.testTextInput.enterText("Fach1");
        await tester.pumpAndSettle();
        expect(
          store.state.settingsState.ignoreForGradesAverage,
          <String>[].toBuiltList(),
        );
        await tester.tap(find.text("Fertig"));
        expect(
          store.state.settingsState.ignoreForGradesAverage,
          ["Fach1"].toBuiltList(),
        );
      },
    );
    testWidgets(
      'removes an item',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          AppState(
            (b) => b.settingsState.ignoreForGradesAverage = ListBuilder(
              <String>["Fach1"],
            ),
          ),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text("Fächer aus dem Notendurchschnitt ausschließen"),
          150,
        );
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.ancestor(
                of: find.text("Fach1"), matching: find.byType(ListTile)),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          store.state.settingsState.ignoreForGradesAverage,
          <String>[].toBuiltList(),
        );
      },
    );
  });

  group("favorite subjects", () {
    testWidgets(
      'adds a favorite subject',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          _settingsStateWithSubjects(),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text("Fokusfächer verwalten"),
          150,
        );
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text("Fokusfächer verwalten"),
              matching: find.byType(ListTile),
            ),
            matching: find.byIcon(Icons.add),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InfoDialog), findsOneWidget);
        expect(find.text("Fokusfach hinzufügen"), findsOneWidget);

        tester.testTextInput.enterText("Fach1");
        await tester.pumpAndSettle();
        await tester.tap(find.text("Fertig"));
        await tester.pumpAndSettle();

        expect(
          store.state.settingsState.favoriteSubjects,
          ["Fach1"].toBuiltList(),
        );
      },
    );

    testWidgets(
      'blocks duplicate favorite subjects by disabling add',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          _settingsStateWithSubjects(favoriteSubjects: const ["Fach1"]),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text("Fokusfächer verwalten"),
          150,
        );

        final addButton = tester.widget<IconButton>(
          find.descendant(
            of: find.ancestor(
              of: find.text("Fokusfächer verwalten"),
              matching: find.byType(ListTile),
            ),
            matching: find.byType(IconButton),
          ),
        );

        expect(addButton.onPressed, isNull);
      },
    );

    testWidgets(
      'removes a favorite subject',
      (tester) async {
        final store = Store<AppState, AppStateBuilder, AppActions>(
          appReducerBuilder.build(),
          _settingsStateWithSubjects(favoriteSubjects: const ["Fach1"]),
          AppActions(),
        );
        final widget = ReduxProvider(
          store: store,
          child: MaterialApp(
            home: SettingsPageContainer(),
          ),
        );
        await tester.pumpWidget(widget);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text("Fokusfächer verwalten"),
          150,
        );
        await tester.scrollUntilVisible(
          find.text("Fach1"),
          100,
        );
        final subjectTile = find.ancestor(
          of: find.text("Fach1").last,
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(
            of: subjectTile,
            matching: find.byType(IconButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          store.state.settingsState.favoriteSubjects,
          <String>[].toBuiltList(),
        );
      },
    );
  });
}
