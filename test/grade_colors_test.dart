import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_chart.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuple/tuple.dart';

void main() {
  test('uses the existing 6 and 8 thresholds without rounding averages', () {
    for (final value in [0, 400, 599, 599.99]) {
      expect(gradeColor(value), Colors.red);
    }
    for (final value in [600, 625, 750, 799, 799.99]) {
      expect(gradeColor(value), Colors.orange);
    }
    for (final value in [800, 1000, 1200]) {
      expect(gradeColor(value), Colors.green);
    }
    for (final value in [null, -1, double.nan, double.infinity]) {
      expect(gradeColor(value), isNull);
    }
  });

  test('chart points use grade colors while lines retain subject colors', () {
    final date = UtcDateTime(2026, 10, 23);
    final graphs = {
      SubjectGrades({date: const Tuple2(725, 'Test')}, 'Mathematik'):
          SubjectTheme((b) => b
            ..color = 0xFF123456
            ..thick = 2),
    };
    final colored = GradesChart.convert(graphs, colorGrades: true).single;
    expect(colored.fillColorFn!(0)?.r, 255);
    expect(colored.fillColorFn!(0)?.g, 152);
    expect(colored.seriesColor?.r, 0x12);
    expect(colored.measureFn(0), 7.25);
    expect(colored.data.single.value.item1, 725);
    expect(GradesChart.convert(graphs).single.fillColorFn, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('orange badge preserves text and cancellation (dark=$dark)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: const Scaffold(
            body: GradeBadge(
          text: '7+',
          hundredths: 725,
          colorized: true,
          cancelled: true,
        )),
      ));
      final text = tester.widget<Text>(find.text('7+'));
      expect(text.style?.color, Colors.orange.shade900);
      expect(text.style?.decoration, TextDecoration.lineThrough);
      final badge = tester.widget<DecoratedBox>(find
          .ancestor(
            of: find.text('7+'),
            matching: find.byType(DecoratedBox),
          )
          .first);
      expect(
          (badge.decoration as ShapeDecoration).color, Colors.orange.shade100);
    });
  }

  testWidgets('disabled and missing grades remain plain text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(
      children: [
        GradeBadge(text: '7', hundredths: 700, colorized: false),
        GradeBadge(text: '—', hundredths: null, colorized: true),
      ],
    ))));
    for (final value in ['7', '—']) {
      expect(tester.widget<Text>(find.text(value)).style?.color, isNull);
      expect(
          find.ancestor(
              of: find.text(value), matching: find.byType(DecoratedBox)),
          findsNothing);
    }
  });
}
