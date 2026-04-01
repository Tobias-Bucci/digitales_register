import 'package:built_collection/built_collection.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('statistics start collapsed and expand on tap', (tester) async {
    final store = createStore(initialState: _buildAbsencesState());

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );
    await settleFor(tester);

    expect(find.text('Statistik'), findsOneWidget);
    expect(find.byType(charts.BarChart), findsNothing);

    await tester.tap(find.text('Statistik'));
    await settleFor(tester);

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.byType(charts.BarChart), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Laura ist noch immer nicht ganz fit'),
      250,
    );
    await settleFor(tester);
    expect(find.text('Laura ist noch immer nicht ganz fit'), findsOneWidget);
    expect(find.byType(AbsenceGroupWidget), findsNWidgets(2));
    expect(find.textContaining('entschuldigt'), findsWidgets);
  });

  testWidgets('shows historical placeholder when only future absences exist',
      (tester) async {
    final store = createStore(
      initialState: _buildAbsencesState(
        includeHistory: false,
        includeFuture: true,
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );
    await settleFor(tester);

    await tester.tap(find.text('Statistik'));
    await settleFor(tester);

    expect(find.text('Noch keine vergangenen Absenzen'), findsOneWidget);
    expect(find.byType(charts.BarChart), findsNothing);
    await tester.scrollUntilVisible(find.byType(FutureAbsenceWidget), 250);
    await settleFor(tester);
    expect(find.byType(FutureAbsenceWidget), findsOneWidget);
  });

  testWidgets('percentage button toggles the pie chart', (tester) async {
    final store = createStore(initialState: _buildAbsencesState());

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );
    await settleFor(tester);

    await tester.tap(find.text('Statistik'));
    await settleFor(tester);

    expect(find.text('Abwesenheit im Verhaeltnis'), findsNothing);

    await tester.tap(find.text('Kreisdiagramm'));
    await settleFor(tester);

    expect(find.text('Abwesenheit im Verhaeltnis'), findsOneWidget);
    expect(find.byType(charts.PieChart<String>), findsOneWidget);

    await tester.tap(find.text('Ausblenden'));
    await settleFor(tester);

    expect(find.text('Abwesenheit im Verhaeltnis'), findsNothing);
  });

  testWidgets('shows empty state when there are no absences', (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.absencesState
          ..absences = ListBuilder<AbsenceGroup>()
          ..futureAbsences = ListBuilder<FutureAbsence>()
          ..statistic = AbsenceStatisticBuilder(),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );

    expect(find.text('Noch keine Absenzen'), findsOneWidget);
  });

  testWidgets('matches absences page golden', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 600));

    final store = createStore(initialState: _buildAbsencesState());

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );
    await settleFor(tester);

    await expectLater(
      find.byType(AbsencesPageContainer),
      matchesGoldenFile('absences.png'),
    );
  });
}

AppState _buildAbsencesState({
  bool includeHistory = true,
  bool includeFuture = false,
}) {
  return AppState(
    (b) => b.absencesState
      ..canEdit = true
      ..statistic = (AbsenceStatisticBuilder()
        ..counter = 4
        ..counterForSchool = 1
        ..delayed = 2
        ..justified = 3
        ..notJustified = 1
        ..percentage = '2.5')
      ..absences = ListBuilder<AbsenceGroup>(
        includeHistory
            ? <AbsenceGroup>[
                AbsenceGroup(
                  (b) => b
                    ..reason = 'Laura ist noch immer nicht ganz fit'
                    ..justified = AbsenceJustified.justified
                    ..hours = 2
                    ..minutes = 0
                    ..absences = ListBuilder<Absence>(<Absence>[
                      Absence(
                        (b) => b
                          ..date = UtcDateTime(2021, 2, 2)
                          ..hour = 3
                          ..minutes = 50
                          ..minutesCameTooLate = 0
                          ..minutesLeftTooEarly = 0,
                      ),
                      Absence(
                        (b) => b
                          ..date = UtcDateTime(2021, 2, 2)
                          ..hour = 4
                          ..minutes = 50
                          ..minutesCameTooLate = 0
                          ..minutesLeftTooEarly = 0,
                      ),
                    ]),
                ),
                AbsenceGroup(
                  (b) => b
                    ..reason = 'Kontrolltermin am Morgen'
                    ..justified = AbsenceJustified.notJustified
                    ..hours = 0
                    ..minutes = 10
                    ..absences = ListBuilder<Absence>(<Absence>[
                      Absence(
                        (b) => b
                          ..date = UtcDateTime(2021, 3, 9)
                          ..hour = 1
                          ..minutes = 10
                          ..minutesCameTooLate = 10
                          ..minutesLeftTooEarly = 0,
                      ),
                    ]),
                ),
              ]
            : const <AbsenceGroup>[],
      )
      ..futureAbsences = ListBuilder<FutureAbsence>(
        includeFuture
            ? <FutureAbsence>[
                FutureAbsence(
                  (b) => b
                    ..id = 10
                    ..justified = AbsenceJustified.notYetJustified
                    ..reason = 'Arzttermin'
                    ..startDate = UtcDateTime(2021, 4, 12)
                    ..endDate = UtcDateTime(2021, 4, 12)
                    ..startHour = 2
                    ..endHour = 4,
                ),
              ]
            : const <FutureAbsence>[],
      ),
  );
}
