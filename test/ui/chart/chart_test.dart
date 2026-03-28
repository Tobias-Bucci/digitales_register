import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    resetTestState();
  });

  testWidgets('tapping the chart reveals the selected grade details', (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: const Center(
        child: SizedBox(
          width: 900,
          height: 700,
          child: Material(
            child: GradesChartContainer(isFullscreen: true),
          ),
        ),
      ),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    expect(
      find.text('Tippe auf das Diagramm, um Details zu sehen'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(750, 200));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    expect(find.text('Fach1 – Schularbeit3: 7+'), findsOneWidget);
    expect(find.text('4. Januar'), findsOneWidget);
  });

  testWidgets('changing the legend clears the selected chart item', (tester) async {
    final store = createStore(initialState: buildGradesPageState());

    await pumpApp(
      tester,
      store: store,
      home: const Center(
        child: SizedBox(
          width: 900,
          height: 700,
          child: Material(child: GradesChartPage()),
        ),
      ),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    await tester.tapAt(const Offset(750, 200));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    expect(find.text('Fach1 – Schularbeit3: 7+'), findsOneWidget);
    expect(find.text('Legende'), findsOneWidget);

    await tester.tap(find.text('Legende'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    await tester.tapAt(const Offset(510, 515));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 300));

    expect(
      find.text('Tippe auf das Diagramm, um Details zu sehen'),
      findsOneWidget,
    );
    expect(find.text('Fach1 – Schularbeit3: 7+'), findsNothing);
  });
}
