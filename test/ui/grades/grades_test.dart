import 'package:dr/app_state.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('shows circular loading state when there are no grades yet',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.gradesState
          ..loading = true
          ..semester = Semester.first.toBuilder()
          ..subjects.clear(),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(primarySwatch: Colors.deepOrange),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows linear loading state when grades already exist',
      (tester) async {
    final store =
        createStore(initialState: buildGradesPageState(loading: true));

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(primarySwatch: Colors.deepOrange),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AnimatedLinearProgressIndicator), findsOneWidget);
  });

  testWidgets('opening a subject and sorting by type reveals grouped grades',
      (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(primarySwatch: Colors.deepOrange),
    );
    await settleFor(tester);

    expect(find.text('Dritte Schularbeit'), findsNothing);

    await tester.tap(find.text('Fach1'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Dritte Schularbeit'), findsOneWidget);

    await tester.tap(find.text('Noten nach Art sortieren'));
    await tester.pump();
    await settleFor(tester);

    expect(find.byType(GradeTypeWidget), findsNWidgets(4));
  });

  testWidgets('competences render as star icons', (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(primarySwatch: Colors.deepOrange),
    );
    await settleFor(tester);

    await tester.tap(find.text('Fach1'));
    await tester.pump();
    await settleFor(tester);

    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_border), findsNWidgets(2));
  });

  testWidgets('favorite subject filter only keeps matching subjects',
      (tester) async {
    final store = createStore(
      initialState: buildGradesPageState(
        favoriteSubjects: const <String>['Fach1'],
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(primarySwatch: Colors.deepOrange),
    );
    await settleFor(tester);

    expect(find.byType(FavoriteSubjectFilter), findsOneWidget);
    expect(find.text('Fach2'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fach1'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Fach1'), findsWidgets);
    expect(find.text('Fach2'), findsNothing);
  });

  testWidgets('failing grades are highlighted with an error badge',
      (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: GradeWidget(
          grade: buildGradeDetail(
            id: 99,
            date: fixtureNow,
            grade: 400,
            name: 'Schularbeit',
          ),
          colorGrades: true,
        ),
      ),
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
    );
    await settleFor(tester);

    final textWidget = tester.widget<Text>(find.text('4'));
    expect(textWidget.style?.fontWeight, FontWeight.w700);
    expect(
      find.ancestor(of: find.text('4'), matching: find.byType(DecoratedBox)),
      findsOneWidget,
    );
  });

  testWidgets('grades are not colorized by default on the grades page',
      (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: const GradesPageContainer(),
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
    );
    await settleFor(tester);

    expect(find.text('Noten farbig anzeigen'), findsOneWidget);

    final colorSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Noten farbig anzeigen'),
    );
    expect(colorSwitch.value, isFalse);

    await tester.tap(find.text('Fach2'));
    await tester.pump();
    await settleFor(tester);

    expect(
      find.ancestor(of: find.text('4'), matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });
}
