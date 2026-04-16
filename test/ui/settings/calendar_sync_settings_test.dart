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

import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/platform_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  final calendarSyncTitle = find.text('Sync school items to calendar');
  final calendarSyncPickerTitle = find.text('Choose sync calendar');

  setUp(() async {
    await bootstrapTestEnvironment();
    CalendarSyncService.requestPermissionOverride = () async => true;
    CalendarSyncService.getWritableCalendarsOverride =
        () async => const <CalendarSyncCalendar>[
              CalendarSyncCalendar(
                id: 12,
                displayName: 'School',
                accountName: 'school@example.com',
                ownerAccount: 'school@example.com',
                isPrimary: true,
              ),
              CalendarSyncCalendar(
                id: 21,
                displayName: 'Private',
                accountName: 'private@example.com',
                ownerAccount: 'private@example.com',
                isPrimary: false,
              ),
            ];
  });

  tearDown(resetTestState);

  testWidgets('shows the Android-only calendar sync toggle', (tester) async {
    isAndroidOverride = () => true;
    final store = createStore(
      initialState: AppState((b) => b.settingsState.languageCode = 'en'),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    expect(calendarSyncTitle, findsOneWidget);
  });

  testWidgets('hides the calendar sync toggle on non-Android platforms',
      (tester) async {
    isAndroidOverride = () => false;
    final store = createStore(
      initialState: AppState((b) => b.settingsState.languageCode = 'en'),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    expect(calendarSyncTitle, findsNothing);
  });

  testWidgets('disabling calendar sync opens the keep/remove dialog',
      (tester) async {
    isAndroidOverride = () => true;
    final store = createStore(
      initialState: AppState((b) {
        b.settingsState
          ..languageCode = 'en'
          ..calendarSyncEnabled = true;
      }),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    await tester.ensureVisible(calendarSyncTitle);
    await tester.tap(calendarSyncTitle);
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Turn off calendar sync?'), findsOneWidget);
    expect(find.byKey(const Key('calendar-sync-keep-events')), findsOneWidget);
    expect(
        find.byKey(const Key('calendar-sync-remove-events')), findsOneWidget);
  });

  testWidgets('enabling calendar sync asks for the target calendar',
      (tester) async {
    isAndroidOverride = () => true;
    final store = createStore(
      initialState: AppState((b) => b.settingsState.languageCode = 'en'),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    await tester.ensureVisible(calendarSyncTitle);
    await tester.tap(calendarSyncTitle);
    await tester.pump();
    await settleFor(tester);

    expect(calendarSyncPickerTitle, findsOneWidget);
    expect(find.text('School'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);

    await tester.tap(find.text('Private'));
    await tester.pump();
    await settleFor(tester);
    await tester.tap(find.text('Select'));
    await tester.pump();
    await settleFor(tester);

    expect(store.state.settingsState.calendarSyncEnabled, isTrue);
    expect(store.state.settingsState.calendarSyncCalendarId, 21);
    expect(calendarSyncPickerTitle, findsWidgets);
  });
}
