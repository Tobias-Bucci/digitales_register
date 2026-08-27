// Copyright (C) 2026 Tobias Bucci

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    appClock.setDemoMode(true);
  });

  tearDown(resetTestState);

  testWidgets('simulated demo date immediately updates both countdowns',
      (tester) async {
    final timeline = SchoolTimeline(
      schoolYearStart: DateTime(2025, 9, 10),
      holidays: <SchoolHoliday>[
        SchoolHoliday(
          name: 'Vacanze natalizie',
          start: DateTime(2025, 12, 24),
          end: DateTime(2026, 1, 5),
        ),
      ],
      gradeDeadlines: <GradeDeadline>[
        GradeDeadline(name: 'Notenschluss', date: DateTime(2026, 1, 23)),
      ],
    );
    await appClock.setSimulatedDate(DateTime(2025, 12, 23));
    DateTime? selectedDate;

    await pumpApp(
      tester,
      store: createStore(initialState: AppState()),
      home: SchoolCountdownOverview(
        timeline: timeline,
        onOpenCalendarAt: (date) async {
          selectedDate = date;
        },
      ),
    );
    await settleFor(tester);

    expect(find.text('1 Tag'), findsOneWidget);
    expect(find.text('Ferien'), findsOneWidget);
    final initialHolidaySize =
        tester.getSize(find.byKey(const ValueKey('holiday-countdown-card')));
    expect(
      initialHolidaySize,
      tester
          .getSize(find.byKey(const ValueKey('grade-deadline-countdown-card'))),
    );

    await tester.tap(find.byKey(const ValueKey('holiday-countdown-card')));
    expect(selectedDate, DateTime(2025, 12, 24));
    await tester
        .tap(find.byKey(const ValueKey('grade-deadline-countdown-card')));
    expect(selectedDate, DateTime(2026, 1, 23));

    await appClock.setSimulatedDate(DateTime(2025, 12, 24));
    await tester.pump();

    expect(find.text('13 Tage Ferien'), findsOneWidget);
    expect(find.text('30 Tage'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('holiday-countdown-card'))),
      initialHolidaySize,
    );
  });
}
