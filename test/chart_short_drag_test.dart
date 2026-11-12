// ignore_for_file: depend_on_referenced_packages
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short swipe on the full-screen grade chart: the tap recognizer gives up
/// after the touch slop, the drag wins the arena without a move event of its
/// own, and lifting the finger ended a drag that never had an update. That
/// crashed in ChartGestureDetector.onScaleEnd (Crashlytics 2d7f8d3b, #23).
void main() {
  testWidgets('a drag that ends without an update does not throw',
      (tester) async {
    final series = [
      charts.Series<MapEntry<DateTime, double>, DateTime>(
        id: 'grades',
        data: [
          MapEntry(DateTime(2026, 9, 10), 7),
          MapEntry(DateTime(2026, 10, 2), 8),
          MapEntry(DateTime(2026, 11, 12), 6.5),
        ],
        domainFn: (entry, _) => entry.key,
        measureFn: (entry, _) => entry.value,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: charts.TimeSeriesChart(
            series,
            animate: false,
            behaviors: [
              charts.SelectNearest(
                eventTrigger: charts.SelectionTrigger.tapAndDrag,
              ),
            ],
          ),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(charts.TimeSeriesChart));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // Past the tap's touch slop (18), below the scale's pan slop (36).
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
