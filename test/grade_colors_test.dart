import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_chart.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuple/tuple.dart';

void main() {
  test('orange is exactly 5.50 through 5.75 without rounding averages', () {
    for (final value in [0, 400, 525, 549, 549.99]) {
      expect(gradeColor(value), AppPalette.markerNegative);
    }
    for (final value in [550, 550.01, 562.5, 574.99, 575]) {
      expect(gradeColor(value), AppPalette.markerWarning);
    }
    for (final value in [575.01, 599.99, 600, 625, 750, 800, 1000, 1200]) {
      expect(gradeColor(value), AppPalette.markerPositive);
    }
    for (final value in [null, -1, double.nan, double.infinity]) {
      expect(gradeColor(value), isNull);
    }
  });

  test('chart points use grade colors while lines retain subject colors', () {
    final date = UtcDateTime(2026, 10, 23);
    final graphs = {
      SubjectGrades([MapEntry(date, const Tuple2(575, 'Test'))], 'Mathematik'):
          SubjectTheme((b) => b
            ..color = 0xFF123456
            ..thick = 2),
    };
    final colored = GradesChart.convert(graphs, colorGrades: true).single;
    expect(colored.fillColorFn!(0)?.r, 0xC2);
    expect(colored.fillColorFn!(0)?.g, 0x7C);
    expect(colored.seriesColor?.r, 0x12);
    expect(colored.measureFn(0), 5.75);
    expect(colored.data.single.value.item1, 575);
    expect(GradesChart.convert(graphs).single.fillColorFn, isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('orange badge preserves text and cancellation (dark=$dark)',
        (tester) async {
      final scheme = dark ? AppPalette.dark : AppPalette.light;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
            body: GradeBadge(
          text: '5¾',
          hundredths: 575,
          colorized: true,
          cancelled: true,
        )),
      ));
      final text = tester.widget<Text>(find.text('5¾'));
      expect(text.style?.color, scheme.onWarningContainer);
      expect(text.style?.decoration, TextDecoration.lineThrough);
      final badge = tester.widget<DecoratedBox>(find
          .ancestor(
            of: find.text('5¾'),
            matching: find.byType(DecoratedBox),
          )
          .first);
      expect(
          (badge.decoration as ShapeDecoration).color, scheme.warningContainer);
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
