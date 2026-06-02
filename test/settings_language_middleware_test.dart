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
import 'package:dr/i18n/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

void main() {
  late MockWrapper mockWrapper;

  setUp(() async {
    mockWrapper = MockWrapper();
    when(() => mockWrapper.loginAddress).thenReturn(testLoginAddress);
    when(() => mockWrapper.noInternet).thenReturn(false);
    await bootstrapTestEnvironment(wrapperOverride: mockWrapper);
  });

  tearDown(resetTestState);

  testWidgets('changing language syncs supported language to server',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/profile/updateLanguage',
        args: <String, Object?>{'language': 'it'},
      ),
    ).thenAnswer((_) async => <String, Object?>{});

    final store = createStore(
      initialState: AppState(
        (b) => b
          ..loginState.loggedIn = true
          ..loginState.username = 'anna',
      ),
      withMiddleware: true,
    );

    await pumpApp(tester, store: store, home: const Scaffold());
    await tester.pump();

    await expectLater(
      store.actions.settingsActions.setLanguage(AppLanguage.it.code),
      completes,
    );

    verify(
      () => mockWrapper.send(
        'api/profile/updateLanguage',
        args: <String, Object?>{'language': 'it'},
      ),
    ).called(1);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('changing language to Ladin syncs German to server',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/profile/updateLanguage',
        args: <String, Object?>{'language': 'de'},
      ),
    ).thenAnswer((_) async => <String, Object?>{});

    final store = createStore(
      initialState: AppState(
        (b) => b
          ..loginState.loggedIn = true
          ..loginState.username = 'anna',
      ),
      withMiddleware: true,
    );

    await pumpApp(tester, store: store, home: const Scaffold());
    await tester.pump();

    await expectLater(
      store.actions.settingsActions.setLanguage(AppLanguage.lld.code),
      completes,
    );

    verify(
      () => mockWrapper.send(
        'api/profile/updateLanguage',
        args: <String, Object?>{'language': 'de'},
      ),
    ).called(1);
    await tester.pump(const Duration(seconds: 6));
  });
}
