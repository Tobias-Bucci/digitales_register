// Copyright (C) 2026 Tobias Bucci

import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/ui/dashboard_card_layout.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
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
    expect(initialHolidaySize.height, lessThan(150));

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
      tester
          .getSize(find.byKey(const ValueKey('holiday-countdown-card')))
          .width,
      initialHolidaySize.width,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('long card texts are limited and keep a row the same size',
      (tester) async {
    // Wide enough for two columns at this text scale, so both share a row.
    tester.view.physicalSize = const Size(720, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longText = List.filled(60, 'sehr langer Text').join(' ');

    await pumpApp(
      tester,
      store: createStore(initialState: AppState()),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SingleChildScrollView(
          child: DashboardCardLayout(
            widths: const [
              DashboardItemWidth.automatic,
              DashboardItemWidth.automatic,
            ],
            textScale: 2,
            children: [
              DashboardSummaryCard(
                icon: Icons.event_note_rounded,
                title: longText,
                primaryText: longText,
                secondaryText: longText,
                progress: 0.5,
              ),
              const DashboardSummaryCard(
                icon: Icons.event_note_rounded,
                title: 'Kurz',
                primaryText: '1',
                secondaryText: 'ok',
              ),
            ],
          ),
        ),
      ),
    );
    await settleFor(tester);

    expect(tester.takeException(), isNull);
    final cards = find.byType(DashboardSummaryCard);
    expect(
        tester.getTopLeft(cards.at(1)).dy, tester.getTopLeft(cards.at(0)).dy);
    expect(
        tester.getSize(cards.at(0)).height, tester.getSize(cards.at(1)).height);
    // 2 title + 2 primary + 4 secondary lines at most, regardless of length.
    expect(tester.getSize(cards.at(0)).height, lessThan(600));
  });
}
