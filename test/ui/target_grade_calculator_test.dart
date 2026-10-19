import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/target_grade_calculator.dart';
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
}
