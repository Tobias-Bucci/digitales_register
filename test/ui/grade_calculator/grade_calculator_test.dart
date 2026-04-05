import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('shows the welcome screen before any grade is entered', (tester) async {
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
}
