import 'dart:convert';

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

// Issue #103: a fresh installation must not alert for the announcements that
// were already active before its first sync.

const a = '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731';
const b = '5f0e2c1a-7f4d-4b52-9d43-2a6c0f3e1b10';
const c = '2c9a7e44-1d6b-4c3f-8a55-73e1b9d0c2f4';

/// Twelve old announcements, the backlog a new user would be flooded with.
final backlog = [
  for (var i = 0; i < 12; i++)
    item(
      id: '00000000-0000-4000-8000-${'$i'.padLeft(12, '0')}',
      publishedAt: '2026-0${1 + i % 9}-1${i % 10}T08:00:00Z',
    ),
];

void main() {
  late FakeServer server;
  late FakeStorage storage;
  var now = DateTime.utc(2026, 10, 22, 20);

  ServerNotificationRepository repository() =>
      repositoryFor(server, storage, now: () => now);

  /// A new process on the same storage.
  Future<ServerNotificationRepository> restarted() async {
    final fresh = repository();
    await fresh.load();
    return fresh;
  }

  ServerNotificationDeviceState device() =>
      ServerNotificationDeviceState.decode(
          storage.values[serverNotificationDeviceKey]);

  setUp(() {
    server = FakeServer();
    storage = FakeStorage();
    now = DateTime.utc(2026, 10, 22, 20);
  });

  group('first sync of a fresh installation', () {
    test('lists the backlog without alerts and without a badge', () async {
      final repo = repository();
      server.replyList(backlog);
      await repo.sync(selection);
      expect(repo.notifications, hasLength(12), reason: 'still in the center');
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
      expect(device().baselined, isTrue);
    });

    test('the listener never sees the backlog as pending', () async {
      final repo = repository();
      final seen = <int>[];
      repo.addListener(() => seen.add(repo.pendingAlerts.length));
      server.replyList(backlog);
      await repo.sync(selection);
      expect(seen, isNotEmpty);
      expect(seen, everyElement(0));
    });

    test('a notification published after it alerts as before', () async {
      final repo = repository();
      server
        ..replyList([item(id: a)])
        ..replyList([item(id: b, publishedAt: '2026-10-22T20:05:00Z'), item()]);
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [b, a]);
      expect(repo.unreadCount, 1);
      expect(repo.pendingAlerts.map((n) => n.id), [b]);
    });

    test('a later important edit of a backlog item alerts again', () async {
      final repo = repository();
      server
        ..replyList([item()])
        ..replyList([item(attention: 2)]);
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.pendingAlerts.map((n) => n.id), [a]);
    });

    test('also after a restart, which does not baseline again', () async {
      final first = repository();
      server.replyList(backlog);
      await first.sync(selection);

      final second = await restarted();
      server.replyList([item(id: c, publishedAt: '2026-10-23T08:00:00Z')]);
      await second.sync(selection);
      expect(second.unreadCount, 1);
      expect(second.pendingAlerts.map((n) => n.id), [c]);
    });

    test('an empty first list still sets the baseline', () async {
      final repo = repository();
      server
        ..replyList([])
        ..replyList([item()]);
      await repo.sync(selection);
      expect(device().baselined, isTrue);
      await repo.sync(selection);
      expect(repo.pendingAlerts.map((n) => n.id), [a]);
    });

    test('covers every page of the collection', () async {
      final repo = repository();
      server
        ..reply(jsonResponse(page([item()], nextCursor: 'p2'), etag: 'W/"1"'))
        ..reply(jsonResponse(page([item(id: b)]), etag: 'W/"2"'));
      await repo.sync(selection);
      expect(repo.notifications, hasLength(2));
      expect(repo.unreadCount, 0);
    });
  });

  group('expired and revoked', () {
    test('expired backlog is neither listed nor counted', () async {
      final repo = repository();
      server.replyList([
        item(expiresAt: '2026-10-22T19:30:00Z'),
        item(id: b),
      ]);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [b]);
      expect(repo.unreadCount, 0);
    });

    test('a backlog item that expires later leaves the list', () async {
      final repo = repository();
      server
        ..replyList([item(expiresAt: '2026-10-22T21:00:00Z'), item(id: b)])
        ..replyNotModified();
      await repo.sync(selection);
      now = DateTime.utc(2026, 10, 22, 21, 0, 1);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [b]);
    });

    test('revoked items leave the list and the badge', () async {
      final repo = repository();
      server
        ..replyList([item(), item(id: b)])
        ..replyList([
          item(id: c, publishedAt: '2026-10-22T20:05:00Z'),
          item(id: b),
        ])
        ..replyList([item(id: b)]);
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [c, b]);
      expect(repo.unreadCount, 1);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [b], reason: 'a and c gone');
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
    });
  });

  group('failed first sync', () {
    test('stores no baseline, and the next success is still the first',
        () async {
      final repo = repository();
      server
        ..reply(jsonResponse({'error': {}}, status: 503))
        ..replyList(backlog);
      await expectLater(
          repo.sync(selection), throwsA(isA<ServerNotificationFailure>()));
      expect(storage.values[serverNotificationDeviceKey], isNull);
      await repo.sync(selection);
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
    });

    test('a malformed body is not a successful sync either', () async {
      final repo = repository();
      server
        ..reply(http.Response('not json', 200))
        ..replyList(backlog);
      await expectLater(
          repo.sync(selection), throwsA(isA<ServerNotificationFailure>()));
      expect(device().baselined, isFalse);
      await repo.sync(selection);
      expect(repo.pendingAlerts, isEmpty);
    });

    test('a broken later page stores no baseline', () async {
      final repo = repository();
      server
        ..reply(jsonResponse(page([item()], nextCursor: 'p2'), etag: 'W/"1"'))
        ..reply(jsonResponse({'error': {}}, status: 500));
      await expectLater(
          repo.sync(selection), throwsA(isA<ServerNotificationFailure>()));
      expect(repo.notifications, isEmpty);
      expect(device().baselined, isFalse);
    });

    test('offline first start shows nothing and saves nothing', () async {
      final repo = repository();
      server.reply(jsonResponse({}, status: 500));
      await expectLater(
          repo.sync(selection), throwsA(isA<ServerNotificationFailure>()));
      expect(repo.notifications, isEmpty);
      expect(storage.values, isEmpty);
    });
  });

  group('reinstall, data deletion and accounts', () {
    test('a reinstall, which deletes app data, baselines again', () async {
      server
        ..replyList([item()])
        ..replyList([item(), item(id: b)]);
      await repository().sync(selection);

      storage.values.clear();
      final reinstalled = repository();
      await reinstalled.sync(selection);
      expect(reinstalled.notifications, hasLength(2));
      expect(reinstalled.pendingAlerts, isEmpty);
      expect(reinstalled.unreadCount, 0);
    });

    test('a leftover cache without device state cannot alert', () async {
      server.replyList([item()]);
      await repository().sync(selection);
      // Only the device state lost, e.g. by an interrupted deletion.
      storage.values.remove(serverNotificationDeviceKey);
      final repo = await restarted();
      expect(repo.notifications, isEmpty, reason: 'the cache is not trusted');
      expect(repo.pendingAlerts, isEmpty);
      server.replyList([item(), item(id: b)]);
      await repo.sync(selection);
      expect(server.requests.last.headers['If-None-Match'], isNull,
          reason: 'a 304 would confirm a list the device cannot show');
      expect(repo.pendingAlerts, isEmpty);
    });

    test('state is per installation, so accounts do not matter', () async {
      // Announcements are public and the same for every account. Signing out
      // or switching accounts does not touch this storage, so the next sync is
      // an ordinary one on the same device.
      server
        ..replyList([item()])
        ..replyList([item(), item(id: b, publishedAt: '2026-10-22T20:05:00Z')]);
      await repository().sync(selection);
      final afterAccountSwitch = await restarted();
      await afterAccountSwitch.sync(selection);
      expect(afterAccountSwitch.pendingAlerts.map((n) => n.id), [b]);
    });

    test('another device has its own state', () async {
      final otherStorage = FakeStorage();
      server
        ..replyList([item()])
        ..replyList([item(), item(id: b)]);
      await repository().sync(selection);
      final other = repositoryFor(server, otherStorage, now: () => now);
      await other.sync(selection);
      expect(other.pendingAlerts, isEmpty, reason: 'its own first sync');
      expect(device().baselined, isTrue);
    });
  });

  group('existing installations after the update', () {
    test('unread notifications stay unread and still alert', () async {
      storage = FakeStorage.existingInstall();
      final repo = repository();
      server.replyList([item(), item(id: b)]);
      await repo.sync(selection);
      expect(repo.unreadCount, 2);
      expect(repo.pendingAlerts, hasLength(2));
    });

    test('read and alerted state is kept as it was', () async {
      storage.values[serverNotificationDeviceKey] = jsonEncode({
        'version': 1,
        'records': {
          a: {'read': 1, 'alerted': 1, 'seen': now.millisecondsSinceEpoch},
          b: {'read': 0, 'alerted': 1, 'seen': now.millisecondsSinceEpoch},
        },
        'dismissed': {c: now.millisecondsSinceEpoch},
      });
      final repo = await restarted();
      server.replyList([item(), item(id: b), item(id: c)]);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), unorderedEquals([a, b]));
      expect(repo.unreadCount, 1, reason: 'b was announced, not read');
      expect(repo.pendingAlerts, isEmpty);
      expect(device().baselined, isTrue);
    });

    test('their offline cache still works', () async {
      storage = FakeStorage.existingInstall();
      storage.values[serverNotificationCacheKey] = jsonEncode({
        'version': 1,
        'unread': [item()],
      });
      final repo = await restarted();
      expect(repo.notifications.map((n) => n.id), [a]);
      expect(repo.unreadCount, 1);
    });

    test('unreadable saved state is not taken for a fresh install', () async {
      storage = FakeStorage.existingInstall()..failReads = true;
      final repo = repository();
      await repo.load();
      storage.failReads = false;
      server.replyList([item()]);
      await repo.sync(selection);
      expect(repo.unreadCount, 1, reason: 'nothing is marked read by guess');
    });

    test('damaged saved state is not taken for a fresh install', () async {
      storage.values[serverNotificationDeviceKey] = '{broken';
      final repo = await restarted();
      server.replyList([item()]);
      await repo.sync(selection);
      expect(repo.unreadCount, 1);
    });
  });

  group('device state', () {
    test('round-trips the baseline and reads old data as baselined', () {
      expect(ServerNotificationDeviceState.decode(null).baselined, isFalse);
      expect(
          ServerNotificationDeviceState.decode(FakeStorage.legacyDeviceState)
              .baselined,
          isTrue);
      final fresh = ServerNotificationDeviceState();
      expect(fresh.baselined, isFalse);
      expect(ServerNotificationDeviceState.decode(fresh.encode()).baselined,
          isFalse);
      fresh.baselined = true;
      expect(ServerNotificationDeviceState.decode(fresh.encode()).baselined,
          isTrue);
    });

    test('the baseline holds no content', () async {
      server.replyList([item(title: 'Geheimtitel', body: 'Geheimtext')]);
      await repository().sync(selection);
      expect(storage.values[serverNotificationDeviceKey],
          isNot(contains('Geheim')));
    });
  });
}
