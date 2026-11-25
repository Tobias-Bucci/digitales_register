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

// The demo's made-up entries never reach the device calendar, and a demo
// sign-in does not delete the events of the real account: the sync records
// belong to the device, not to an account.

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/data.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  late List<CalendarSyncUpsertRequest> upserts;
  late List<int> deletedIds;

  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 11, 18, 10));
    isAndroidOverride = () => true;
    upserts = <CalendarSyncUpsertRequest>[];
    deletedIds = <int>[];
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 41;
    CalendarSyncService.getWritableCalendarsOverride =
        () async => const <CalendarSyncCalendar>[
              CalendarSyncCalendar(
                id: 41,
                displayName: 'School',
                accountName: 'school@example.com',
                ownerAccount: 'school@example.com',
                isPrimary: true,
              ),
            ];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 500 + upserts.length;
    };
    CalendarSyncService.deleteEventOverride = (id) async => deletedIds.add(id);
  });

  tearDown(resetTestState);

  AppState stateFor(String username, {required int homeworkId}) {
    final date = UtcDateTime(2026, 11, 19);
    return AppState((b) {
      b.settingsState.calendarSyncEnabled = true;
      b.loginState
        ..loggedIn = true
        ..username = username;
      b.dashboardState.allDays = ListBuilder<Day>(<Day>[
        buildDay(date: date, homework: <Homework>[
          buildHomework(
            id: homeworkId,
            title: 'Homework $homeworkId',
            type: HomeworkType.homework,
            checkable: true,
          ),
        ]),
      ]);
    });
  }

  test('the demo writes nothing and keeps the real account\'s events',
      () async {
    expect(
      await CalendarSyncService.reconcile(stateFor('student', homeworkId: 1)),
      isTrue,
    );
    expect(upserts, hasLength(1));

    // Signed in to the demo (school empty, user demo) with sync still on.
    expect(
      await CalendarSyncService.reconcile(stateFor('demo', homeworkId: 2)),
      isTrue,
    );
    expect(upserts, hasLength(1), reason: 'no demo entry in the calendar');
    expect(deletedIds, isEmpty, reason: 'the real event stays');
    expect(CalendarSyncService.missingEventCount.value, 0);

    // Back in the real account: its event is still tracked, nothing changes.
    expect(
      await CalendarSyncService.reconcile(stateFor('student', homeworkId: 1)),
      isTrue,
    );
    expect(upserts, hasLength(1));
    expect(deletedIds, isEmpty);
  });

  test('the demo clock alone also keeps the calendar untouched', () async {
    await CalendarSyncService.reconcile(stateFor('student', homeworkId: 1));
    appClock.setDemoMode(true);

    await CalendarSyncService.reconcile(stateFor('student', homeworkId: 3));

    expect(upserts, hasLength(1));
    expect(deletedIds, isEmpty);
  });
}
