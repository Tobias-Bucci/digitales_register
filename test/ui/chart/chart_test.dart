import 'package:built_collection/built_collection.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/grades_chart_page.dart';
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

  testWidgets('tapping the chart reveals the selected grade details',
      (tester) async {
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
    await settleFor(tester);

    expect(
      find.text('Tippe auf das Diagramm, um Details zu sehen'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(750, 200));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Fach1 – Schularbeit3: 7+'), findsOneWidget);
    expect(find.text('4. Januar'), findsOneWidget);
  });

  testWidgets('changing the legend clears the selected chart item',
      (tester) async {
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
    await settleFor(tester);

    await tester.tapAt(const Offset(750, 200));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Fach1 – Schularbeit3: 7+'), findsOneWidget);
    expect(find.text('Legende'), findsOneWidget);

    await tester.tap(find.text('Legende'));
    await tester.pump();
    await settleFor(tester);

    await tester.tapAt(const Offset(510, 515));
    await tester.pump();
    await settleFor(tester);

    expect(
      find.text('Tippe auf das Diagramm, um Details zu sehen'),
      findsOneWidget,
    );
    expect(find.text('Fach1 – Schularbeit3: 7+'), findsNothing);
  });
  testWidgets('preview chart shows points when only one grade is available',
      (tester) async {
    final state = buildGradesPageState().rebuild(
      (b) => b.gradesState.subjects = ListBuilder<Subject>(<Subject>[
        buildSubject(
          name: 'Fach1',
          gradesAll: <Semester, BuiltList<GradeAll>>{
            Semester.first: BuiltList<GradeAll>(<GradeAll>[
              buildGradeAll(
                date: UtcDateTime(2021, 1, 2),
                grade: 775,
                type: 'Schularbeit1',
              ),
            ]),
          },
        ),
      ]),
    );
    final store = createStore(initialState: state);

    await pumpApp(
      tester,
      store: store,
      home: const Center(
        child: SizedBox(
          width: 250,
          height: 150,
          child: Material(
            child: GradesChartContainer(isFullscreen: false),
          ),
        ),
      ),
    );
    await settleFor(tester);

    final chart = tester
        .widget<charts.TimeSeriesChart>(find.byType(charts.TimeSeriesChart));
    final renderer =
        chart.defaultRenderer! as charts.LineRendererConfig<DateTime>;

    expect(renderer.includePoints, isTrue);
  });
}
