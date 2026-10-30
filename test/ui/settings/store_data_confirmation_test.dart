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
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('turning saving off asks first and says what stays',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore(
      initialState: AppState(
        (b) => b.settingsState.languageCode = AppLanguage.en.code,
      ),
    );
    await pumpApp(tester, store: store, home: SettingsPageContainer());
    await settleFor(tester);
    final tile = find.widgetWithText(SwitchListTile, 'Store data locally');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();

    // The line under "delete on logout" names what is kept.
    expect(find.textContaining('Downloaded files and entries exported'),
        findsOneWidget);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Delete saved data?'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    expect(
        find.descendant(
            of: dialog,
            matching: find.textContaining('device calendar are kept')),
        findsOneWidget);
    expect(
        find.descendant(
            of: dialog, matching: find.textContaining('downloaded files')),
        findsOneWidget);
    // Backing out changes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.state.settingsState.noDataSaving, isFalse);

    // Closing the dialog is backing out, too.
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(store.state.settingsState.noDataSaving, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off and delete'));
    await tester.pumpAndSettle();
    expect(store.state.settingsState.noDataSaving, isTrue);

    // Turning it on again deletes nothing and asks nothing.
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Delete saved data?'), findsNothing);
    expect(store.state.settingsState.noDataSaving, isFalse);
  });
}
