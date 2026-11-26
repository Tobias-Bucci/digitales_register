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

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/demo.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/middleware/middleware.dart' show wrapper;
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

// #179: the register writes dashboard and notification texts in the language
// of the profile. When the app changes that language, the texts loaded before
// the change must be loaded again.
void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    await resetDemoStoreForTest();
    await wrapper.login(
      'demo',
      'demo',
      null,
      '',
      logout: () {},
      configLoaded: () {},
      relogin: () {},
      addProtocolItem: (_) {},
    );
  });

  tearDown(() async {
    await resetDemoStoreForTest();
    await resetTestState();
  });

  Store<AppState, AppStateBuilder, AppActions> signedInStore(String language) {
    return createStore(
      initialState: AppState(
        (b) => b
          ..loginState.loggedIn = true
          ..loginState.username = 'demo'
          ..settingsState.languageCode = language
          ..dashboardState.future = true,
      ),
      withMiddleware: true,
    );
  }

  Iterable<String> dashboardTexts(AppState state) sync* {
    for (final day in state.dashboardState.allDays!) {
      for (final item in day.homework) {
        yield item.title;
        yield item.subtitle;
      }
    }
  }

  Iterable<String> notificationTitles(AppState state) =>
      state.notificationState.notifications!.map((n) => n.title);

  // The first loads after a sign-in, started together as the login does.
  Future<void> firstLoads(Store<AppState, AppStateBuilder, AppActions> store) {
    return Future.wait<void>([
      store.actions.dashboardActions.load(store.state.dashboardState.future),
      store.actions.notificationsActions.load(),
      store.actions.profileActions.load(),
    ]);
  }

  test('the first dashboard after a demo sign-in in English is English',
      () async {
    final store = signedInStore(AppLanguage.en.code);

    await firstLoads(store);

    expect(dashboardTexts(store.state), contains('Pack your sports bag'));
    expect(
        dashboardTexts(store.state), isNot(contains('Turnbeutel einpacken')));
    expect(notificationTitles(store.state), contains('Demo note'));
    expect(notificationTitles(store.state), isNot(contains('Demo-Hinweis')));
  });

  test('a sign-in in the register language keeps the first dashboard',
      () async {
    final store = signedInStore(AppLanguage.de.code);

    await firstLoads(store);
    final loaded = store.state.dashboardState.allDays;

    expect(dashboardTexts(store.state), contains('Turnbeutel einpacken'));
    expect(notificationTitles(store.state), contains('Demo-Hinweis'));
    // Nothing was loaded a second time.
    expect(identical(store.state.dashboardState.allDays, loaded), isTrue);
  });

  test('changing the app language reloads the register texts', () async {
    final store = signedInStore(AppLanguage.de.code);
    await firstLoads(store);
    expect(dashboardTexts(store.state), contains('Turnbeutel einpacken'));

    await store.actions.settingsActions.setLanguage(AppLanguage.en.code);

    expect(dashboardTexts(store.state), contains('Pack your sports bag'));
    expect(notificationTitles(store.state), contains('Demo note'));
  });

  test('switching to Ladin keeps the German register texts loaded', () async {
    final store = signedInStore(AppLanguage.de.code);
    await firstLoads(store);
    final loaded = store.state.dashboardState.allDays;

    await store.actions.settingsActions.setLanguage(AppLanguage.lld.code);

    // Ladin uses the register's German: there is nothing to load again.
    expect(identical(store.state.dashboardState.allDays, loaded), isTrue);
  });
}
