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
            ];
  });

  tearDown(resetTestState);

  Future<void> useLargeSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> scrollToCalendarSync(WidgetTester tester) async {
    for (var i = 0; i < 10 && calendarSyncTitle.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(600, 1200), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('shows the Android-only calendar sync toggle', (tester) async {
    isAndroidOverride = () => true;
    await useLargeSurface(tester);
    final store = createStore(
      initialState: AppState((b) => b.settingsState.languageCode = 'en'),
    );

    await pumpApp(
      tester,
      store: store,
      home: SettingsPageContainer(),
    );
    await settleFor(tester);

    await scrollToCalendarSync(tester);
    expect(calendarSyncTitle, findsOneWidget);
  });

  testWidgets('hides the calendar sync toggle on non-Android platforms',
      (tester) async {
    isAndroidOverride = () => false;
    await useLargeSurface(tester);
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
}
