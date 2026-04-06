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

import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/serializers.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flush skips logged out states', () async {
    final service = AppStatePersistenceService();
    final writes = <MapEntry<String, String>>[];

    await service.flush(
      state: AppState(),
      deletedData: false,
      server: 'https://example.com/v2/api/login',
      writer: (key, value) async {
        writes.add(MapEntry<String, String>(key, value));
      },
      keyFactory: (user, server) => '$user@$server',
    );

    expect(writes, isEmpty);
  });

  test('flush persists the full app state for logged in users', () async {
    final service = AppStatePersistenceService();
    late String payload;

    await service.flush(
      state: AppState(
        (b) => b.loginState
          ..loggedIn = true
          ..username = 'anna',
      ),
      deletedData: false,
      server: 'https://example.com/v2/api/login',
      writer: (key, value) async {
        expect(key, 'anna@https://example.com/v2/api/login');
        payload = value;
      },
      keyFactory: (user, server) => '$user@$server',
    );

    final deserialized = serializers.deserialize(
      json.decode(payload) as Object,
    );
    expect(deserialized, isA<AppState>());
  });

  test('flush persists settings only when data deletion is active', () async {
    final service = AppStatePersistenceService();
    late String payload;

    await service.flush(
      state: AppState(
        (b) => b.loginState
          ..loggedIn = true
          ..username = 'anna',
      ),
      deletedData: true,
      server: 'https://example.com/v2/api/login',
      writer: (key, value) async {
        payload = value;
      },
      keyFactory: (user, server) => '$user@$server',
    );

    final deserialized = serializers.deserialize(
      json.decode(payload) as Object,
    );
    expect(deserialized, isA<SettingsState>());
  });

  test('flush persists selected language in settings state', () async {
    final service = AppStatePersistenceService();
    late String payload;

    await service.flush(
      state: AppState(
        (b) => b
          ..loginState.loggedIn = true
          ..loginState.username = 'anna'
          ..settingsState.languageCode = 'en',
      ),
      deletedData: true,
      server: 'https://example.com/v2/api/login',
      writer: (key, value) async {
        payload = value;
      },
      keyFactory: (user, server) => '$user@$server',
    );

    final deserialized = serializers.deserialize(
      json.decode(payload) as Object,
    )! as SettingsState;
    expect(deserialized.languageCode, 'en');
  });

  test('schedule debounces to the latest pending save', () async {
    final service = AppStatePersistenceService(
      debounce: const Duration(milliseconds: 10),
    );
    final writes = <String>[];

    service.schedule(
      state: AppState(
        (b) => b.loginState
          ..loggedIn = true
          ..username = 'first',
      ),
      deletedData: false,
      server: 'server',
      writer: (key, value) async {
        writes.add(key);
      },
      keyFactory: (user, server) => '$user-$server',
    );
    service.schedule(
      state: AppState(
        (b) => b.loginState
          ..loggedIn = true
          ..username = 'second',
      ),
      deletedData: false,
      server: 'server',
      writer: (key, value) async {
        writes.add(key);
      },
      keyFactory: (user, server) => '$user-$server',
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(writes, <String>['second-server']);
  });

  test('flush skips identical state instances for the same storage key',
      () async {
    final service = AppStatePersistenceService();
    final writes = <String>[];
    final state = AppState(
      (b) => b.loginState
        ..loggedIn = true
        ..username = 'anna',
    );

    Future<void> persist() {
      return service.flush(
        state: state,
        deletedData: false,
        server: 'server',
        writer: (key, value) async {
          writes.add(value);
        },
        keyFactory: (user, server) => '$user-$server',
      );
    }

    await persist();
    await persist();

    expect(writes, hasLength(1));
  });
}
