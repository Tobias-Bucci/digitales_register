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

import 'package:dr/android_widget_snapshot.dart';
import 'package:dr/app_state.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  setUp(() {
    mockNow = fixtureNow;
  });

  tearDown(() {
    mockNow = null;
  });

  test('builds ready snapshot without sensitive widget data', () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..url = 'https://school.example',
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.ready);
    expect(snapshot.meta.username, isNull);
    expect(snapshot.meta.server, isNull);
    expect(snapshot.dashboard.items, isEmpty);
    expect(snapshot.grades.overallAverage, isEmpty);
    expect(snapshot.grades.subjects, isEmpty);
    expect(snapshot.today.items, isEmpty);
  });

  test('marks snapshot as data saving disabled when noDataSaving is active',
      () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..settingsState.noDataSaving = true,
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(
      snapshot.meta.status,
      AndroidWidgetSnapshotStatus.dataSavingDisabled,
    );
  });

  test('marks snapshot as app locked when biometric lock is enabled', () {
    final state = AppState(
      (b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'max'
        ..settingsState.biometricAppLockEnabled = true,
    );

    final snapshot = buildAndroidWidgetSnapshot(state);

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.appLocked);
  });

  test('marks snapshot as logged out when no authenticated user exists', () {
    final snapshot = buildAndroidWidgetSnapshot(AppState());

    expect(snapshot.meta.status, AndroidWidgetSnapshotStatus.loggedOut);
    expect(snapshot.dashboard.items, isEmpty);
    expect(snapshot.grades.subjects, isEmpty);
    expect(snapshot.today.items, isEmpty);
  });
}
