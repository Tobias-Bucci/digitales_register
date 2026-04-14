// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:built_collection/built_collection.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/absences_page.dart';
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
      home: const AbsencesPageContainer(),
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
      home: const AbsencesPageContainer(),
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
      home: const AbsencesPageContainer(),
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
      home: const AbsencesPageContainer(),
    );

    expect(find.text('Noch keine Absenzen'), findsOneWidget);
  });

  testWidgets('future absence dialog shows end hour with end time',
      (tester) async {
    final store = createStore(
      initialState: _buildAbsencesStateWithCalendarTimes(),
    );

    await pumpApp(
      tester,
      store: store,
      home: const AbsencesPageContainer(),
    );
    await settleFor(tester);

    await tester.tap(find.byType(FilledButton));
    await settleFor(tester);

    expect(find.text('1 (07:50)'), findsOneWidget);
    expect(find.text('1 (08:40)'), findsOneWidget);
    expect(find.text('1 (von 07:50)'), findsNothing);
    expect(find.text('1 (bis 08:40)'), findsNothing);
  });

  test('collectLessonTimesByWeekday groups lessons by weekday', () {
    final state = _buildAbsencesStateWithDifferentWeekdayHours();

    final lessonTimes = collectLessonTimesByWeekday(state);

    expect(
      lessonTimes.item1[DateTime.monday]!.keys.toList(),
      <int>[1, 2, 3, 4, 5, 6, 7, 8],
    );
    expect(
      lessonTimes.item1[DateTime.tuesday]!.keys.toList(),
      <int>[1, 2, 3, 4, 5, 6],
    );
    expect(lessonTimes.item1[DateTime.monday]![8], '15:00');
    expect(lessonTimes.item2[DateTime.monday]![8], '15:50');
    expect(lessonTimes.item1[DateTime.tuesday]![6], '12:20');
    expect(lessonTimes.item2[DateTime.tuesday]![6], '13:10');
  });

  testWidgets('whole day sends 1 to 20 to the api payload', (tester) async {
    Map<String, dynamic>? submittedPayload;
    final store = createStore(initialState: _buildAbsencesState());

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPage(
        state: _buildAbsencesState().absencesState,
        noInternet: false,
        onAddFutureAbsence: (payload) {
          submittedPayload = payload;
        },
        onRemoveFutureAbsence: (_) {},
      ),
    );
    await settleFor(tester);

    await tester.tap(find.byType(FilledButton));
    await settleFor(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Arzttermin');
    await tester.enterText(find.byType(TextField).at(1), 'Max Mustermann');
    await settleFor(tester);

    await tester.tap(find.text('Ganzer Tag'));
    await settleFor(tester);

    await tester.tap(find.text('Speichern'));
    await settleFor(tester);

    expect(submittedPayload, isNotNull);
    expect(submittedPayload!['futureAbsence']['startTime'], 1);
    expect(submittedPayload!['futureAbsence']['endTime'], 20);
  });

  testWidgets('absence justification dialog requires reason and signature',
      (tester) async {
    String? submittedReason;
    String? submittedSignature;
    final store = createStore();

    await pumpApp(
      tester,
      store: store,
      home: Material(
        child: AbsenceGroupWidget(
          vm: AbsencesViewModel(
            fromTo: 'Mo. 13.4.2026, 8. - 9. Stunde',
            duration: '2 Unterrichtseinheiten',
            justifiedString: 'Noch nicht entschuldigt',
            reason: null,
            justified: AbsenceJustified.notYetJustified,
            note: null,
            onJustify: (reason, signature) {
              submittedReason = reason;
              submittedSignature = signature;
            },
          ),
        ),
      ),
    );
    await settleFor(tester);

    await tester.tap(find.text('Absenz entschuldigen'));
    await settleFor(tester);

    expect(find.text('Absenz entschuldigen'), findsNWidgets(2));
    expect(
      tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Speichern'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).at(0), 'Bauchschmerzen');
    await settleFor(tester);
    expect(
      tester
          .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Speichern'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).at(1), 'Tobias Bucci');
    await settleFor(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await settleFor(tester);

    expect(submittedReason, 'Bauchschmerzen');
    expect(submittedSignature, 'Tobias Bucci');
  });

  testWidgets('does not show justify button when reason already exists',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.absencesState
          ..canEdit = true
          ..statistic = AbsenceStatisticBuilder()
          ..absences = ListBuilder<AbsenceGroup>(<AbsenceGroup>[
            AbsenceGroup(
              (b) => b
                ..date = UtcDateTime(2026, 4, 13)
                ..reason = 'Bauchschmerzen'
                ..reasonSignature = 'Tobias Bucci'
                ..reasonTimestamp = UtcDateTime(2026, 4, 14, 7, 11, 27)
                ..reasonUser = 3649
                ..justified = AbsenceJustified.notYetJustified
                ..hours = 2
                ..minutes = 0
                ..absences = ListBuilder<Absence>(<Absence>[
                  Absence(
                    (b) => b
                      ..id = 44533
                      ..date = UtcDateTime(2026, 4, 13)
                      ..hour = 8
                      ..minutes = 50
                      ..minutesCameTooLate = 0
                      ..minutesLeftTooEarly = 0,
                  ),
                  Absence(
                    (b) => b
                      ..id = 44509
                      ..date = UtcDateTime(2026, 4, 13)
                      ..hour = 9
                      ..minutes = 50
                      ..minutesCameTooLate = 0
                      ..minutesLeftTooEarly = 0,
                  ),
                ]),
            ),
          ])
          ..futureAbsences = ListBuilder<FutureAbsence>(),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: const AbsencesPageContainer(),
    );
    await settleFor(tester);

    expect(find.text('Absenz entschuldigen'), findsNothing);
  });

  testWidgets('matches absences page golden', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 600));

    final store = createStore(initialState: _buildAbsencesState());

    await pumpApp(
      tester,
      store: store,
      home: const AbsencesPageContainer(),
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

AppState _buildAbsencesStateWithCalendarTimes() {
  return _buildAbsencesState().rebuild(
    (b) => b.calendarState
      ..days[UtcDateTime(2026, 4, 7)] = CalendarDay(
        (day) => day
          ..date = UtcDateTime(2026, 4, 7)
          ..lastFetched = UtcDateTime(2026, 4, 7, 12)
          ..hours = ListBuilder<CalendarHour>(<CalendarHour>[
            CalendarHour(
              (hour) => hour
                ..subject = 'Deutsch'
                ..fromHour = 1
                ..toHour = 1
                ..rooms = ListBuilder<String>()
                ..teachers = ListBuilder<Teacher>()
                ..homeworkExams = ListBuilder<HomeworkExam>()
                ..lessonContents = ListBuilder<LessonContent>()
                ..timeSpans = ListBuilder<TimeSpan>(<TimeSpan>[
                  TimeSpan(
                    (span) => span
                      ..from = UtcDateTime(2026, 4, 7, 7, 50)
                      ..to = UtcDateTime(2026, 4, 7, 8, 40),
                  ),
                ]),
            ),
          ]),
      ),
  );
}

AppState _buildAbsencesStateWithDifferentWeekdayHours() {
  return _buildAbsencesState().rebuild(
    (b) => b.calendarState
      ..days[UtcDateTime(2026, 4, 13)] = _buildCalendarDayWithHours(
        date: UtcDateTime(2026, 4, 13),
        hourTimes: const <int, List<int>>{
          1: <int>[7, 50, 8, 40],
          2: <int>[8, 40, 9, 30],
          3: <int>[9, 35, 10, 25],
          4: <int>[10, 25, 11, 15],
          5: <int>[11, 30, 12, 20],
          6: <int>[12, 20, 13, 10],
          7: <int>[14, 10, 15, 00],
          8: <int>[15, 00, 15, 50],
        },
      )
      ..days[UtcDateTime(2026, 4, 14)] = _buildCalendarDayWithHours(
        date: UtcDateTime(2026, 4, 14),
        hourTimes: const <int, List<int>>{
          1: <int>[7, 50, 8, 40],
          2: <int>[8, 40, 9, 30],
          3: <int>[9, 35, 10, 25],
          4: <int>[10, 25, 11, 15],
          5: <int>[11, 30, 12, 20],
          6: <int>[12, 20, 13, 10],
        },
      ),
  );
}

CalendarDay _buildCalendarDayWithHours({
  required UtcDateTime date,
  required Map<int, List<int>> hourTimes,
}) {
  return CalendarDay(
    (day) => day
      ..date = date
      ..lastFetched = date
      ..hours = ListBuilder<CalendarHour>(
        hourTimes.entries.map(
          (entry) => CalendarHour(
            (hour) => hour
              ..subject = 'Deutsch'
              ..fromHour = entry.key
              ..toHour = entry.key
              ..rooms = ListBuilder<String>()
              ..teachers = ListBuilder<Teacher>()
              ..homeworkExams = ListBuilder<HomeworkExam>()
              ..lessonContents = ListBuilder<LessonContent>()
              ..timeSpans = ListBuilder<TimeSpan>(<TimeSpan>[
                TimeSpan(
                  (span) => span
                    ..from = UtcDateTime(
                      date.year,
                      date.month,
                      date.day,
                      entry.value[0],
                      entry.value[1],
                    )
                    ..to = UtcDateTime(
                      date.year,
                      date.month,
                      date.day,
                      entry.value[2],
                      entry.value[3],
                    ),
                ),
              ]),
          ),
        ),
      ),
  );
}
