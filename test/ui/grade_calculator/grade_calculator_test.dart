import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('weighted calculator rounds 6.9375 to 6.94', (tester) async {
    await pumpApp(tester, store: createStore(), home: const GradeCalculator());
    for (final values in [('6', '1'), ('7', '15')]) {
      await tester.tap(find.descendant(
        of: find.byType(values.$1 == '6' ? Greeting : FloatingActionButton),
        matching: find.text('Note hinzufügen'),
      ));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(InfoDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, values.$1);
      await tester.enterText(fields.last, values.$2);
      await tester.pump();
      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();
    }
    expect(find.text('6,94'), findsOneWidget);
    expect(find.text('6,93'), findsNothing);
  });

  testWidgets('shows the welcome screen before any grade is entered',
      (tester) async {
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: const GradeCalculator(),
    );

    expect(find.textContaining('Um zu beginnen'), findsOneWidget);
    expect(find.text('Note hinzufügen'), findsOneWidget);
    expect(find.text('Noten importieren'), findsOneWidget);
  });

  testWidgets('greeting scrolls when the tutorial leaves little height',
      (tester) async {
    tester.view.physicalSize = const Size(384, 382);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore();

    await pumpApp(tester, store: store, home: const GradeCalculator());
    expect(tester.takeException(), isNull);

    final scrollable = find.descendant(
      of: find.byType(Greeting),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.scrollUntilVisible(
      find.descendant(
        of: find.byType(Greeting),
        matching: find.byIcon(Icons.track_changes),
      ),
      80,
      scrollable: scrollable,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a grade updates the average and shows the grade list',
      (tester) async {
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: const GradeCalculator(),
    );

    await tester.tap(find.text('Note hinzufügen'));
    await tester.pump();
    await settleFor(tester);

    expect(find.byType(InfoDialog), findsOneWidget);

    await tester.enterText(
      find.ancestor(of: find.text('Note'), matching: find.byType(TextField)),
      '9/10',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Gewichtung'),
        matching: find.byType(TextField),
      ),
      '32',
    );
    await tester.pump();

    await tester.tap(find.text('Hinzufügen'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.byType(GradesList), findsOneWidget);
    expect(find.text('1 Note'), findsOneWidget);
    expect(find.text('9,50'), findsOneWidget);
  });

  testWidgets('can scroll back to the first grade after adding many grades',
      (tester) async {
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: const GradeCalculator(),
    );

    Future<void> addGrade(String grade, {required bool first}) async {
      if (!first) {
        await tester.scrollUntilVisible(
          find.byType(GradeTile).last,
          50,
          scrollable: find
              .descendant(
                of: find.byType(GradesList),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }

      await tester.tap(
        find.descendant(
          of: find.byType(first ? Greeting : FloatingActionButton),
          matching: find.text('Note hinzufügen'),
        ),
      );
      await tester.pump();
      await settleFor(tester);

      await tester.enterText(
        find
            .ancestor(of: find.text('Note'), matching: find.byType(TextField))
            .last,
        grade,
      );
      await tester.enterText(
        find
            .ancestor(
              of: find.text('Gewichtung'),
              matching: find.byType(TextField),
            )
            .last,
        '32',
      );
      await tester.pump();
      await tester.tap(find.text('Hinzufügen'));
      await tester.pump();
      await settleFor(tester);
    }

    for (var i = 0; i < 11; i++) {
      await addGrade(i.toString(), first: i == 0);
    }

    expect(find.text('0'), findsNothing);
    expect(find.text('10'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('0'),
      -50,
      scrollable: find
          .descendant(
            of: find.byType(GradesList),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(find.text('0'), findsOneWidget);
  });

  group('import', () {
    GradeAll grade(int? value, {bool cancelled = false, int day = 1}) =>
        buildGradeAll(
          date: UtcDateTime(2026, 4, day),
          grade: value ?? 0,
          cancelled: cancelled,
        ).rebuild((b) => b..grade = value);

    Subject subject(List<GradeAll> grades) => buildSubject(
          id: 77,
          name: 'Mathematik',
          gradesAll: {Semester.first: BuiltList(grades)},
        );

    Future<Store<AppState, AppStateBuilder, AppActions>> openImport(
      WidgetTester tester,
      List<GradeAll> grades,
    ) async {
      final store = createStore(
        initialState: AppState(
          (b) => b..gradesState.subjects.replace([subject(grades)]),
        ),
      );
      addTearDown(store.dispose);
      await pumpApp(tester, store: store, home: const GradeCalculator());
      await tester.tap(find.byIcon(Icons.save_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<Subject>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematik').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(RadioListTile<Semester>).first);
      await tester.pumpAndSettle();
      return store;
    }

    ElevatedButton importButton(WidgetTester tester) =>
        tester.widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Importieren'));

    testWidgets('unknown-only grades are skipped with feedback',
        (tester) async {
      await openImport(tester, [grade(null), grade(400, cancelled: true)]);

      expect(tester.takeException(), isNull);
      expect(find.text('1 Einträge ohne Zahlenwert wurden nicht importiert'),
          findsOneWidget);
      expect(
        find.text('Für dieses Fach sind in diesem Zeitraum keine Noten '
            'verfügbar'),
        findsOneWidget,
      );
      expect(importButton(tester).onPressed, isNull);
    });

    testWidgets('mixed grades import only the numeric uncancelled ones',
        (tester) async {
      await openImport(tester, [
        grade(700, day: 3),
        grade(null, day: 2),
        grade(400, cancelled: true, day: 1),
      ]);

      expect(tester.takeException(), isNull);
      expect(find.text('1 Einträge ohne Zahlenwert wurden nicht importiert'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Importieren'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(GradesList), findsOneWidget);
      expect(find.text('1 Note'), findsOneWidget);
      expect(find.text('7,00'), findsOneWidget);
    });

    testWidgets('refreshed and removed subjects keep the page usable',
        (tester) async {
      final store = await openImport(tester, [grade(null)]);
      expect(importButton(tester).onPressed, isNull);

      store.replaceState(
          store.state.rebuild((b) => b.gradesState.subjects.replace([
                subject([grade(null), grade(800, day: 2)])
              ])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(importButton(tester).onPressed, isNotNull);

      store.replaceState(store.state
          .rebuild((b) => b.gradesState.subjects.replace(<Subject>[])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Fach auswählen'), findsOneWidget);
      expect(importButton(tester).onPressed, isNull);
    });
  });
}
