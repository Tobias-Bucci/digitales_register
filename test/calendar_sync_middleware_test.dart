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
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/data.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 9));
    isAndroidOverride = () => true;
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 55;
  });

  tearDown(resetTestState);

  testWidgets('enabling calendar sync imports current items', (tester) async {
    final upsertedTitles = <String>[];
    CalendarSyncService.requestPermissionOverride = () async => true;
    CalendarSyncService.upsertEventOverride = (request) async {
      upsertedTitles.add(request.title);
      return 100;
    };

    final store = createStore(
      initialState: AppState((b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 4,
                title: 'Reminder',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      }),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(),
    );
    await store.actions.settingsActions.calendarSyncEnabled(true);

    expect(store.state.settingsState.calendarSyncEnabled, isTrue);
    expect(upsertedTitles, <String>['Reminder']);
  });

  testWidgets('permission denial reverts the calendar sync toggle',
      (tester) async {
    CalendarSyncService.requestPermissionOverride = () async => false;

    final store = createStore(withMiddleware: true);

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(),
    );
    await store.actions.settingsActions.calendarSyncEnabled(true);

    expect(store.state.settingsState.calendarSyncEnabled, isFalse);
  });

  testWidgets('toggling a dashboard item done state reconciles calendar sync',
      (tester) async {
    final upserts = <CalendarSyncUpsertRequest>[];
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 100;
    };
    CalendarSyncService.deleteEventOverride = (eventId) async {
      deletedIds.add(eventId);
    };

    final store = createStore(
      initialState: AppState((b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 4,
                title: 'Reminder',
                type: HomeworkType.homework,
                checkable: true,
              ),
            ],
          ),
        ]);
      }),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(),
    );

    await CalendarSyncService.reconcile(store.state);
    await store.actions.dashboardActions.toggleDone(
      ToggleDonePayload(
        (b) => b
          ..homeworkId = 4
          ..type = HomeworkType.homework.name
          ..done = true,
      ),
    );
    await tester.pump();
    await store.actions.dashboardActions.toggleDone(
      ToggleDonePayload(
        (b) => b
          ..homeworkId = 4
          ..type = HomeworkType.homework.name
          ..done = false,
      ),
    );
    await tester.pump();

    expect(deletedIds, <int>[100]);
    expect(upserts, hasLength(2));
    expect(upserts.first.eventId, isNull);
    expect(upserts.last.eventId, isNull);
  });
}
