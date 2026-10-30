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

import 'dart:async';
import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/serializers.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved settings from older versions ignore removed push preference', () {
    final serialized = List<Object?>.from(
      serializers.serialize(SettingsState())! as List,
    )..addAll(['pushNotificationsEnabled', true]);

    expect(serializers.deserialize(serialized), isA<SettingsState>());
  });

  test('saved app state includes the notification inbox', () {
    final state = AppState();
    final serialized = serializers.serialize(state);

    expect((serializers.deserialize(serialized) as AppState).notificationState,
        state.notificationState);
  });

  test('saved app state without an inbox loads after the upgrade', () {
    final serialized = List<Object?>.from(
      serializers.serialize(AppState())! as List,
    );
    final index = serialized.indexOf('notificationState');
    expect(index, greaterThanOrEqualTo(0));
    serialized.removeRange(index, index + 2);

    expect(serializers.deserialize(serialized), isA<AppState>());
  });

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

  group('ordering of writes', () {
    AppState signedIn(String user) => AppState(
          (b) => b.loginState
            ..loggedIn = true
            ..username = user,
        );

    Future<void> persist(
      AppStatePersistenceService service,
      PersistStateWriter writer, {
      AppState? state,
      bool deletedData = false,
    }) {
      return service.flush(
        state: state ?? signedIn('anna'),
        deletedData: deletedData,
        server: 'server',
        writer: writer,
        keyFactory: (user, server) => '$user-$server',
      );
    }

    test('a deletion never lands before an older write that is still running',
        () async {
      final service = AppStatePersistenceService();
      final stored = <String, String>{};
      final releaseFirst = Completer<void>();
      var secondStarted = false;

      final first = persist(service, (key, value) async {
        await releaseFirst.future;
        stored[key] = value;
      });
      final second = persist(
        service,
        (key, value) async {
          secondStarted = true;
          stored[key] = value;
        },
        state: signedIn('anna')
            .rebuild((b) => b.settingsState.languageCode = 'it'),
        deletedData: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(secondStarted, isFalse);
      releaseFirst.complete();
      await Future.wait([first, second]);

      final finalState = serializers.deserialize(
        json.decode(stored['anna-server']!) as Object,
      );
      // The deletion payload (settings only) is what stays behind.
      expect(finalState, isA<SettingsState>());
    });

    test(
        'clearing while a write runs keeps its bookkeeping out of the next account',
        () async {
      final service = AppStatePersistenceService();
      final release = Completer<void>();
      final writes = <String>[];
      final state = signedIn('anna');

      final running = persist(service, (key, value) async {
        await release.future;
        writes.add(key);
      }, state: state);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.clear();
      release.complete();
      await running;
      // The account was cleared: the same state must be written again.
      await persist(service, (key, value) async => writes.add(key),
          state: state);

      expect(writes, hasLength(2));
    });

    test('a write requested before clear but not yet started is dropped',
        () async {
      final service = AppStatePersistenceService();
      final release = Completer<void>();
      final writes = <String>[];

      final first = persist(service, (key, value) async {
        await release.future;
        writes.add('first');
      });
      final queued = persist(
        service,
        (key, value) async => writes.add('queued'),
        state: signedIn('berta'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.clear();
      release.complete();
      await Future.wait([first, queued]);

      expect(writes, ['first']);
    });

    test('a failing write does not block the writes behind it', () async {
      final service = AppStatePersistenceService();
      final writes = <String>[];

      final failing = persist(service, (key, value) async {
        throw StateError('disk full');
      });
      final following = persist(
        service,
        (key, value) async => writes.add(key),
        state: signedIn('berta'),
      );

      await expectLater(failing, throwsStateError);
      await following;
      expect(writes, ['berta-server']);
    });

    test('runExclusive and drain wait for every write already requested',
        () async {
      final service = AppStatePersistenceService();
      final release = Completer<void>();
      final order = <String>[];

      final write = persist(service, (key, value) async {
        await release.future;
        order.add('write');
      });
      final drained = service.drain().then((_) => order.add('drained'));
      final exclusive = service.runExclusive(() async => order.add('delete'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(order, isEmpty);
      release.complete();
      await Future.wait([write, drained, exclusive]);

      expect(order.first, 'write');
      expect(order, containsAll(['drained', 'delete']));
    });

    test('an exclusive action that fails does not block later writes',
        () async {
      final service = AppStatePersistenceService();
      final writes = <String>[];

      final exclusive = service.runExclusive<void>(() async {
        throw StateError('delete failed');
      });
      await persist(service, (key, value) async => writes.add(key));

      await expectLater(exclusive, throwsStateError);
      expect(writes, ['anna-server']);
    });
  });
}
