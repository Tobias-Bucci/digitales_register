import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/calendar_detail_container.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/ui/calendar.dart';
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('shows the nick helper bar when enabled and a nick is missing',
      (tester) async {
    final store = createStore(
      initialState: _calendarState(
        nicksBarEnabled: true,
        hasSubjectWithoutNick: true,
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => SettingsPageContainer(),
      ),
    );
    await settleFor(tester);

    expect(
      tester.widget<EditNickBar>(find.byType(EditNickBar)).show,
      isTrue,
    );
  });

  testWidgets('hides the nick helper bar when the setting is disabled',
      (tester) async {
    final store = createStore(
      initialState: _calendarState(
        nicksBarEnabled: false,
        hasSubjectWithoutNick: true,
      ),
    );
    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => SettingsPageContainer(),
      ),
    );
    await settleFor(tester);

    expect(
      tester.widget<EditNickBar>(find.byType(EditNickBar)).show,
      isFalse,
    );
  });

  testWidgets('jumping to the current week updates the selected monday',
      (tester) async {
    mockNow = UtcDateTime(2021, 1, 27);
    final store = createStore(
      initialState: AppState(
        (b) => b.calendarState.currentMonday = UtcDateTime(2021, 1, 20),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
    );

    expect(find.text('Aktuelle Woche'), findsOneWidget);

    await tester.tap(find.text('Aktuelle Woche'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 250));

    expect(store.state.calendarState.currentMonday, UtcDateTime(2021, 1, 25));
    expect(find.text('Aktuelle Woche'), findsNothing);
  });

  testWidgets('tapping the nick helper bar opens the subject nick dialog',
      (tester) async {
    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      _calendarState(
        nicksBarEnabled: true,
        hasSubjectWithoutNick: true,
      ),
      AppActions(),
      middleware: <Middleware<AppState, AppStateBuilder, AppActions>>[
        routingMiddleware.build(),
      ],
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => SettingsPageContainer(),
      ),
    );
    await settleFor(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Kürzel bearbeiten'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 500));

    expect(find.byType(InfoDialog), findsOneWidget);
    expect(find.text('Kürzel hinzufügen'), findsOneWidget);
    expect(find.text('Fach1'), findsOneWidget);
  });

  testWidgets('tapping substitute helper hides it permanently in state',
      (tester) async {
    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      _calendarState(
        nicksBarEnabled: false,
        hasSubjectWithoutNick: false,
      ),
      AppActions(),
      middleware: <Middleware<AppState, AppStateBuilder, AppActions>>[
        routingMiddleware.build(),
      ],
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        builder: (_) => SettingsPageContainer(),
      ),
    );
    await settleFor(tester);

    expect(
      tester
          .widget<CalendarSubstituteBar>(find.byType(CalendarSubstituteBar))
          .show,
      isTrue,
    );

    await tester
        .tap(find.widgetWithText(TextButton, 'Supplenzfehler korrigieren'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 500));

    expect(store.state.settingsState.showCalendarSubstituteBar, isFalse);
  });

  testWidgets('favorite subject filter clears a hidden calendar selection',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) {
          b.calendarState
            ..currentMonday = UtcDateTime(2021, 2, 20)
            ..selection = CalendarSelection(
              (b) => b
                ..date = UtcDateTime(2021, 2, 21)
                ..hour = 1,
            ).toBuilder()
            ..days = MapBuilder<UtcDateTime, CalendarDay>(
              <UtcDateTime, CalendarDay>{
                UtcDateTime(2021, 2, 20): CalendarDay(
                  (b) => b
                    ..date = UtcDateTime(2021, 2, 20)
                    ..lastFetched = UtcDateTime(2021, 2, 20)
                    ..hours = ListBuilder<CalendarHour>(<CalendarHour>[
                      CalendarHour(
                        (b) => b
                          ..subject = 'Fach1'
                          ..fromHour = 1
                          ..toHour = 1
                          ..rooms = ListBuilder<String>()
                          ..teachers = ListBuilder<Teacher>()
                          ..timeSpans = ListBuilder<TimeSpan>()
                          ..homeworkExams = ListBuilder<HomeworkExam>()
                          ..lessonContents = ListBuilder<LessonContent>(),
                      ),
                    ]),
                ),
                UtcDateTime(2021, 2, 21): CalendarDay(
                  (b) => b
                    ..date = UtcDateTime(2021, 2, 21)
                    ..lastFetched = UtcDateTime(2021, 2, 21)
                    ..hours = ListBuilder<CalendarHour>(<CalendarHour>[
                      CalendarHour(
                        (b) => b
                          ..subject = 'Fach2'
                          ..fromHour = 1
                          ..toHour = 1
                          ..rooms = ListBuilder<String>()
                          ..teachers = ListBuilder<Teacher>()
                          ..timeSpans = ListBuilder<TimeSpan>()
                          ..homeworkExams = ListBuilder<HomeworkExam>()
                          ..lessonContents = ListBuilder<LessonContent>(),
                      ),
                    ]),
                ),
              },
            );
          b.settingsState
            ..favoriteSubjects = ListBuilder<String>(const <String>[
              'Fach1',
              'Fach2',
            ])
            ..subjectThemes = MapBuilder<String, SubjectTheme>(
              <String, SubjectTheme>{
                'Fach1': SubjectTheme(
                  (b) => b
                    ..color = Colors.red.toARGB32()
                    ..thick = 2,
                ),
                'Fach2': SubjectTheme(
                  (b) => b
                    ..color = Colors.blue.toARGB32()
                    ..thick = 2,
                ),
              },
            );
        },
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarContainer(),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(store.state.calendarState.selection, isNotNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fach1'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Kein Fokusfach'), findsOneWidget);
    expect(store.state.calendarState.selection, isNull);
  });

  testWidgets(
      'week view merges adjacent hours with same teacher despite different descriptions',
      (tester) async {
    final store = createStore();
    await pumpApp(
      tester,
      store: store,
      home: Material(
        child: CalendarWeek(
          vm: CalendarWeekViewModel(
            (b) => b
              ..days = ListBuilder<CalendarDay>([
                buildCalendarDay(
                  date: UtcDateTime(2026, 4, 17),
                  hours: [
                    buildCalendarHour(
                      subject: 'Fach1',
                      teachers: [
                        buildTeacher(firstName: 'Anna', lastName: 'Rossi'),
                      ],
                      lessonContents: [
                        LessonContent(
                          (b) => b
                            ..name = 'Beschreibung 1'
                            ..typeName = 'Fachunterricht'
                            ..submissions =
                                ListBuilder<LessonContentSubmission>(),
                        ),
                      ],
                    ),
                    buildCalendarHour(
                      subject: 'Fach1',
                      fromHour: 2,
                      teachers: [
                        buildTeacher(firstName: 'Anna', lastName: 'Rossi'),
                      ],
                      lessonContents: [
                        LessonContent(
                          (b) => b
                            ..name = 'Beschreibung 2'
                            ..typeName = 'Fachunterricht'
                            ..submissions =
                                ListBuilder<LessonContentSubmission>(),
                        ),
                      ],
                    ),
                  ],
                ),
              ])
              ..subjectNicks = MapBuilder<String, String>()
              ..noInternet = false
              ..selection = null
              ..colorBackground = false
              ..subjectThemes = MapBuilder<String, SubjectTheme>({
                'Fach1': SubjectTheme(
                  (b) => b
                    ..color = Colors.red.toARGB32()
                    ..thick = 2,
                ),
              }),
          ),
          favoriteSubject: null,
        ),
      ),
    );
    await settleFor(tester);

    expect(find.text('Fach1'), findsOneWidget);
    expect(find.text('Rossi'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('week view merges adjacent hours with different teachers',
      (tester) async {
    final store = createStore();
    await pumpApp(
      tester,
      store: store,
      home: Material(
        child: CalendarWeek(
          vm: CalendarWeekViewModel(
            (b) => b
              ..days = ListBuilder<CalendarDay>([
                buildCalendarDay(
                  date: UtcDateTime(2026, 4, 17),
                  hours: [
                    buildCalendarHour(
                      subject: 'Fach1',
                      teachers: [
                        buildTeacher(firstName: 'Anna', lastName: 'Rossi'),
                      ],
                    ),
                    buildCalendarHour(
                      subject: 'Fach1',
                      fromHour: 2,
                      toHour: 2,
                      teachers: [
                        buildTeacher(firstName: 'Bruno', lastName: 'Bianchi'),
                      ],
                    ),
                  ],
                ),
              ])
              ..subjectNicks = MapBuilder<String, String>()
              ..noInternet = false
              ..selection = null
              ..colorBackground = false
              ..subjectThemes = MapBuilder<String, SubjectTheme>({
                'Fach1': SubjectTheme(
                  (b) => b
                    ..color = Colors.red.toARGB32()
                    ..thick = 2,
                ),
              }),
          ),
          favoriteSubject: null,
        ),
      ),
    );
    await settleFor(tester);

    expect(find.text('Fach1'), findsOneWidget);
    expect(find.text('Rossi'), findsOneWidget);
    expect(find.text('Bianchi'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets(
      'calendar detail renders self-created assessment in an existing period',
      (tester) async {
    final date = UtcDateTime(2026, 4, 17);
    final store = createStore(
      initialState: AppState(
        (b) {
          b.calendarState
            ..currentMonday = toMonday(date)
            ..selection = CalendarSelection(
              (b) => b
                ..date = date
                ..hour = 4,
            ).toBuilder()
            ..days = MapBuilder<UtcDateTime, CalendarDay>({
              date: buildCalendarDay(
                date: date,
                hours: <CalendarHour>[
                  buildCalendarHour(subject: 'Deutsch'),
                  buildCalendarHour(
                    subject: 'Mathematik',
                    fromHour: 2,
                    toHour: 2,
                  ),
                  buildCalendarHour(
                    subject: 'Geschichte',
                    fromHour: 3,
                    toHour: 3,
                  ),
                  buildCalendarHour(
                    subject: 'Italienisch',
                    fromHour: 4,
                    toHour: 4,
                  ),
                ],
              ),
            });
          b.dashboardState.allDays = ListBuilder<Day>(<Day>[
            buildDay(
              date: date,
              homework: <Homework>[
                buildHomework(
                  id: 77,
                  title: 'Reminder',
                  subtitle: '/cw@4 Italienisch',
                  type: HomeworkType.homework,
                ),
              ],
            ),
          ]);
          b.gradesState.subjects = ListBuilder<Subject>(<Subject>[
            buildSubject(name: 'Italienisch'),
          ]);
        },
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: Material(
        child: CalendarDetailItemContainer(
          date: date,
          isSidebar: false,
        ),
      ),
    );
    await settleFor(tester);

    expect(find.text('Italienisch'), findsOneWidget);
    expect(find.text('Selbst erstellt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

AppState _calendarState({
  required bool nicksBarEnabled,
  required bool hasSubjectWithoutNick,
}) {
  return AppState(
    (b) {
      b.calendarState
        ..currentMonday = UtcDateTime(2021, 2, 20)
        ..days = MapBuilder<UtcDateTime, CalendarDay>(
          <UtcDateTime, CalendarDay>{
            UtcDateTime(2021, 2, 20): CalendarDay(
              (b) => b
                ..date = UtcDateTime(2021, 2, 20)
                ..lastFetched = UtcDateTime(2021, 2, 20)
                ..hours = ListBuilder<CalendarHour>(<CalendarHour>[
                  CalendarHour(
                    (b) => b
                      ..subject = 'Fach1'
                      ..fromHour = 1
                      ..toHour = 2
                      ..rooms = ListBuilder<String>()
                      ..teachers = ListBuilder<Teacher>()
                      ..timeSpans = ListBuilder<TimeSpan>(<TimeSpan>[
                        TimeSpan(
                          (b) => b
                            ..from = UtcDateTime(2022, 9, 5, 22)
                            ..to = UtcDateTime(2022, 9, 5, 23),
                        ),
                      ])
                      ..homeworkExams =
                          ListBuilder<HomeworkExam>(<HomeworkExam>[
                        HomeworkExam(
                          (b) => b
                            ..deadline = UtcDateTime(2022, 9, 5)
                            ..hasGradeGroupSubmissions = false
                            ..hasGrades = false
                            ..homework = true
                            ..id = 5
                            ..name = 'Foo'
                            ..online = false
                            ..typeId = 500
                            ..typeName = 'Hausaufgabe'
                            ..warning = false,
                        ),
                      ])
                      ..lessonContents = ListBuilder<LessonContent>(),
                  ),
                ]),
            ),
          },
        );
      b.settingsState.showCalendarNicksBar = nicksBarEnabled;
      if (!hasSubjectWithoutNick) {
        b.settingsState.subjectNicks = MapBuilder<String, String>(
          <String, String>{'Fach1': 'F'},
        );
      }
    },
  );
}
