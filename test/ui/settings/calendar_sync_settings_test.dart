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
import 'package:dr/platform_adapter.dart';
import 'package:dr/container/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
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

    expect(find.byKey(const Key('calendar-sync-toggle')), findsOneWidget);
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

    expect(find.byKey(const Key('calendar-sync-toggle')), findsNothing);
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

    await tester.ensureVisible(find.byKey(const Key('calendar-sync-toggle')));
    await tester.tap(find.byKey(const Key('calendar-sync-toggle')));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Turn off calendar sync?'), findsOneWidget);
    expect(find.byKey(const Key('calendar-sync-keep-events')), findsOneWidget);
    expect(find.byKey(const Key('calendar-sync-remove-events')), findsOneWidget);
  });
}
