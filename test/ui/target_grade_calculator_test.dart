import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fixtures.dart';
import '../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);
  const longName =
      'Fächerübergreifender Lernbereich Gesellschaftliche Bildung und Angewandte Naturwissenschaften';
  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'subject dropdown fits long names at width $width and text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = createStore(
            initialState: AppState((b) => b.gradesState.subjects =
                ListBuilder<Subject>([buildSubject(name: longName)])));
        await pumpApp(tester,
            store: store, home: const TargetGradeCalculator());
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('target-calculator-subject')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(longName).last);
        await tester.pumpAndSettle();
        expect(find.text(longName), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      });
    }
  }

  testWidgets('grades that do not count are left out like everywhere else',
      (tester) async {
    final date = UtcDateTime(2026, 10, 5);
    // (8.00 * 100 + 6.50 * 50) / 150 = 7.50; 0 %, negative and cancelled
    // grades do not count toward the subject average either.
    final store = createStore(
        initialState: AppState((b) => b
          ..gradesState.semester = Semester.first.toBuilder()
          ..gradesState.subjects = ListBuilder<Subject>([
            buildSubject(id: 7, name: 'Mathematik', gradesAll: {
              Semester.first: BuiltList<GradeAll>([
                buildGradeAll(date: date, grade: 800),
                buildGradeAll(date: date, grade: 650, weightPercentage: 50),
                buildGradeAll(date: date, grade: 1000, weightPercentage: 0),
                buildGradeAll(date: date, grade: 400, weightPercentage: -50),
                buildGradeAll(date: date, grade: 300, cancelled: true),
              ]),
            }),
          ])));
    addTearDown(store.dispose);
    await pumpApp(tester, store: store, home: const TargetGradeCalculator());
    await tester.tap(find.byKey(const Key('target-calculator-subject')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematik').last);
    await tester.pumpAndSettle();

    expect(store.state.gradesState.subjects.single.average(Semester.first),
        750);
    expect(find.textContaining('Aktueller Durchschnitt: 7,50'), findsOneWidget);
    expect(find.textContaining('· -50%'), findsNothing);
  });

  group('refreshed subject list', () {
    final date = UtcDateTime(2026, 10, 5);
    Subject math(List<int> values, {int? id = 7, String name = 'Mathematik'}) =>
        buildSubject(id: id, name: name, gradesAll: {
          Semester.first: BuiltList<GradeAll>([
            for (final value in values) buildGradeAll(date: date, grade: value),
          ]),
        });
    AppState stateWith(List<Subject> subjects) => AppState((b) => b
      ..gradesState.subjects = ListBuilder<Subject>(subjects)
      ..gradesState.semester = Semester.first.toBuilder());

    Future<Store<AppState, AppStateBuilder, AppActions>> selectMath(
        WidgetTester tester, List<Subject> subjects) async {
      final store = createStore(initialState: stateWith(subjects));
      addTearDown(store.dispose);
      await pumpApp(tester, store: store, home: const TargetGradeCalculator());
      await tester.tap(find.byKey(const Key('target-calculator-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematik').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Aktueller Durchschnitt: 6'), findsOneWidget);
      return store;
    }

    Subject? selectedSubject(WidgetTester tester) => tester
        .widget<DropdownButton<Subject>>(find.byType(DropdownButton<Subject>))
        .value;

    for (final (label, id) in [('id', 7), ('name', null)]) {
      testWidgets('a refreshed subject with the same $label stays selected',
          (tester) async {
        final store = await selectMath(tester, [
          math([600], id: id)
        ]);

        final refreshed = math([600, 800], id: id);
        store.replaceState(
            stateWith([buildSubject(name: 'Deutsch'), refreshed]));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(selectedSubject(tester), refreshed);
        // The calculation uses the refreshed grades, not the stale instance.
        expect(
            find.textContaining('Aktueller Durchschnitt: 7'), findsOneWidget);
        expect(find.textContaining('· 100%'), findsNWidgets(2));
      });
    }

    testWidgets('a removed subject clears the selection and its grades',
        (tester) async {
      final store = await selectMath(tester, [
        math([600]),
        buildSubject(id: 8, name: 'Deutsch')
      ]);

      store.replaceState(stateWith([buildSubject(id: 8, name: 'Deutsch')]));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(selectedSubject(tester), isNull);
      expect(find.textContaining('Aktueller Durchschnitt'), findsNothing);
    });
  });
}
