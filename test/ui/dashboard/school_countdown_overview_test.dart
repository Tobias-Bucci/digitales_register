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
    GradeDeadline? editedDeadline;

    await pumpApp(
      tester,
      store: createStore(initialState: AppState()),
      home: SchoolCountdownOverview(
        timeline: timeline,
        onOpenCalendarAt: (date) async {
          selectedDate = date;
        },
        onEditGradeDeadline: (deadline) async {
          editedDeadline = deadline;
        },
      ),
    );
    await settleFor(tester);

    expect(find.text('1 Tag'), findsOneWidget);
    expect(find.text('Ferien'), findsOneWidget);
    expect(find.textContaining('% fortgeschritten'), findsWidgets);
    final initialHolidaySize =
        tester.getSize(find.byKey(const ValueKey('holiday-countdown-card')));
    expect(initialHolidaySize.height, 176);
    expect(
      initialHolidaySize,
      tester
          .getSize(find.byKey(const ValueKey('grade-deadline-countdown-card'))),
    );

    await tester.tap(find.byKey(const ValueKey('holiday-countdown-card')));
    expect(selectedDate, DateTime(2025, 12, 24));
    await tester
        .tap(find.byKey(const ValueKey('grade-deadline-countdown-card')));
    expect(editedDeadline?.date, DateTime(2026, 1, 23));

    await appClock.setSimulatedDate(DateTime(2025, 12, 24));
    await tester.pump();

    expect(find.text('13 Tage Ferien'), findsOneWidget);
    expect(find.text('30 Tage'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('holiday-countdown-card'))),
      initialHolidaySize,
    );
  });

  testWidgets('countdown cards do not overflow on a narrow dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await appClock.setSimulatedDate(DateTime(2025, 12, 23));

    await pumpApp(
      tester,
      store: createStore(initialState: AppState()),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
        child: SchoolCountdownOverview(
          timeline: SchoolTimeline(
            schoolYearStart: DateTime(2025, 9, 10),
            holidays: <SchoolHoliday>[
              SchoolHoliday(
                name: 'Lange Weihnachtsferien',
                start: DateTime(2025, 12, 24),
                end: DateTime(2026, 1, 6),
              ),
            ],
            gradeDeadlines: <GradeDeadline>[
              GradeDeadline(
                name: 'Erster Notenschluss',
                date: DateTime(2026, 1, 31),
              ),
            ],
          ),
        ),
      ),
    );
    await settleFor(tester);

    expect(tester.takeException(), isNull);
  });
}
