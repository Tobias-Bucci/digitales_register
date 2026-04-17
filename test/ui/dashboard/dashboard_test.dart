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

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() {
    resetTestState();
  });

  testWidgets('home page shows the no internet state', (tester) async {
    final store = createStore(
      initialState: AppState((b) => b.noInternet = true),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );

    expect(find.text('Keine Verbindung'), findsOneWidget);
    expect(find.byType(NoInternet), findsOneWidget);
    expect(find.text('Vergangenheit'), findsOneWidget);
    expect(find.text('Zukunft'), findsNothing);
    expect(find.byType(Sidebar), findsOneWidget);
  });

  testWidgets('loading without entries shows the fullscreen progress indicator',
      (tester) async {
    final store = createStore(
      initialState: AppState((b) => b.dashboardState.loading = true),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 250));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DayWidget), findsNothing);
  });

  testWidgets(
      'loading with existing entries keeps the dashboard content visible',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState
          ..future = false
          ..loading = true
          ..allDays = ListBuilder<Day>(<Day>[
            buildDay(date: UtcDateTime(2020)),
          ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.byType(DayWidget), findsOneWidget);
    expect(find.text('Keine Einträge vorhanden'), findsNothing);
    expect(find.byType(NoInternet), findsNothing);
  });

  testWidgets('favorite subject filter hides unrelated dashboard entries',
      (tester) async {
    final now = UtcDateTime(2050);
    final store = createStore(
      initialState: AppState(
        (b) {
          b.settingsState.favoriteSubjects =
              ListBuilder<String>(const <String>['Fach1', 'Fach3']);
          b.dashboardState.allDays = ListBuilder<Day>(<Day>[
            buildDay(
              date: now,
              homework: <Homework>[
                buildHomework(title: 'Titel Fach1', label: 'Fach1'),
                buildHomework(id: 2, title: 'Titel Fach2', label: 'Fach2'),
                buildHomework(id: 3, title: 'Ohne Fach'),
              ],
            ),
          ]);
        },
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.byType(FavoriteSubjectFilter), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Fach1'), findsOneWidget);
    expect(find.text('Titel Fach2'), findsOneWidget);
    expect(find.text('Ohne Fach'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fach1'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Titel Fach1'), findsOneWidget);
    expect(find.text('Titel Fach2'), findsNothing);
    expect(find.text('Ohne Fach'), findsNothing);
  });

  testWidgets('empty days filter hides empty days and updates the counter',
      (tester) async {
    final now = UtcDateTime(2050);
    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(date: now),
          buildDay(
            date: now.add(const Duration(days: 1)),
            homework: <Homework>[
              buildHomework(title: 'Mit Eintrag'),
            ],
          ),
          buildDay(
            date: now.add(const Duration(days: 2)),
            deletedHomework: <Homework>[
              buildHomework(
                id: 2,
                title: 'Gelöschter Eintrag',
                deleted: true,
              ),
            ],
          ),
          buildDay(date: now.add(const Duration(days: 3))),
        ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.widgetWithText(FilledButton, 'Filter'), findsOneWidget);
    expect(find.byType(DayWidget), findsNWidgets(4));

    await tester.tap(find.widgetWithText(FilledButton, 'Filter'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Leere Tage anzeigen'), findsOneWidget);

    await tester
        .tap(find.widgetWithText(CheckboxListTile, 'Leere Tage anzeigen'));
    await tester.pump();
    await settleFor(tester);

    expect(find.widgetWithText(FilledButton, 'Filter (1)'), findsOneWidget);
    expect(find.byType(DayWidget), findsNWidgets(2));
    expect(find.text('Mit Eintrag'), findsOneWidget);
  });

  testWidgets(
      'checking an item becomes disabled after offline mode is confirmed',
      (tester) async {
    final mockWrapper = MockWrapper();
    when(() => mockWrapper.noInternet).thenReturn(true);
    when(() => mockWrapper.refreshNoInternet()).thenAnswer((_) async => true);
    when(
      () => mockWrapper.send(
        'api/student/dashboard/toggle_reminder',
        args: <String, Object?>{
          'id': 0,
          'type': 'homework',
          'value': true,
        },
      ),
    ).thenAnswer((_) async => null);
    wrapper = mockWrapper;

    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2050),
            homework: <Homework>[
              buildHomework(
                id: 0,
                type: HomeworkType.homework,
                checkable: true,
                deleteable: true,
              ),
            ],
          ),
        ]),
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await settleFor(tester);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await store.actions.refreshNoInternet();
    await tester.pump();
    await settleFor(tester);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    resetNoInternetRetryForTest();
  });

  testWidgets('offline mode triggers automatic retry checks', (tester) async {
    final mockWrapper = MockWrapper();
    var refreshChecks = 0;
    when(() => mockWrapper.noInternet).thenReturn(true);
    when(() => mockWrapper.refreshNoInternet()).thenAnswer((_) async {
      refreshChecks++;
      return true;
    });
    wrapper = mockWrapper;
    noInternetRetryInterval = const Duration(milliseconds: 20);

    final store = createStore(
      initialState: AppState(),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );

    await store.actions.noInternet(true);
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 80));

    expect(refreshChecks, greaterThanOrEqualTo(1));
    resetNoInternetRetryForTest();
  });

  testWidgets(
      'deleting a reminder starts exit animation before the server responds',
      (tester) async {
    final mockWrapper = MockWrapper();
    final completer = Completer<Map<String, Object?>>();
    when(() => mockWrapper.noInternet).thenReturn(false);
    when(
      () => mockWrapper.send(
        'api/student/dashboard/delete_reminder',
        args: <String, Object?>{'id': 7},
      ),
    ).thenAnswer((_) => completer.future);
    wrapper = mockWrapper;

    final store = createStore(
      initialState: AppState(
        (b) {
          b.settingsState.askWhenDelete = false;
          b.dashboardState.allDays = ListBuilder<Day>(<Day>[
            buildDay(
              date: UtcDateTime(2050),
              homework: <Homework>[
                buildHomework(
                  id: 7,
                  title: 'Erinnerung',
                  subtitle: 'Sofort weg',
                  type: HomeworkType.homework,
                  deleteable: true,
                ),
              ],
            ),
          ]);
        },
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.text('Sofort weg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Sofort weg'), findsOneWidget);

    completer.complete(<String, Object?>{'success': true});
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.text('Sofort weg'), findsNothing);
  });

  testWidgets(
      'editing a reminder deletes the old entry and adds the updated one',
      (tester) async {
    final mockWrapper = MockWrapper();
    when(() => mockWrapper.noInternet).thenReturn(false);
    when(
      () => mockWrapper.send(
        'api/student/dashboard/delete_reminder',
        args: <String, Object?>{'id': 7},
      ),
    ).thenAnswer((_) async => <String, Object?>{'success': true});
    when(
      () => mockWrapper.send(
        'api/student/dashboard/save_reminder',
        args: <String, Object?>{
          'date': '2050-01-01',
          'text': 'Neu formulierte Erinnerung',
        },
      ),
    ).thenAnswer(
      (_) async => <String, Object?>{
        'id': 8,
        'title': 'Erinnerung',
        'subtitle': 'Neu formulierte Erinnerung',
        'type': 'homework',
        'deleteable': true,
        'checkable': true,
        'checked': false,
      },
    );
    wrapper = mockWrapper;

    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2050),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Erinnerung',
                subtitle: 'Alte Erinnerung',
                type: HomeworkType.homework,
                deleteable: true,
                checkable: true,
              ),
            ],
          ),
        ]),
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Alte Erinnerung'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump();
    await settleFor(tester);

    await tester.enterText(
      find.byType(TextField),
      'Neu formulierte Erinnerung',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Speichern'));
    await tester.pump();
    await settleFor(tester);

    verifyInOrder(<void Function()>[
      () => mockWrapper.send(
            'api/student/dashboard/delete_reminder',
            args: <String, Object?>{'id': 7},
          ),
      () => mockWrapper.send(
            'api/student/dashboard/save_reminder',
            args: <String, Object?>{
              'date': '2050-01-01',
              'text': 'Neu formulierte Erinnerung',
            },
          ),
    ]);

    expect(find.text('Neu formulierte Erinnerung'), findsOneWidget);
    expect(find.text('Alte Erinnerung'), findsNothing);
  });

  testWidgets(
      'self-created assessments use reminder action layout without info button',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2050),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Erinnerung',
                subtitle: '/test@2 Italienisch Grammatik',
                type: HomeworkType.homework,
                deleteable: true,
                checkable: true,
              ),
            ],
          ),
        ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysContainer(),
    );
    await settleFor(tester);

    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    final listTile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(listTile.leading, isNotNull);
  });
}
