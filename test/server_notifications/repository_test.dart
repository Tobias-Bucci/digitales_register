import 'dart:async';
import 'dart:convert';

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

const a = '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731';
const b = '5f0e2c1a-7f4d-4b52-9d43-2a6c0f3e1b10';

void main() {
  late FakeServer server;
  late FakeStorage storage;
  var now = DateTime.utc(2026, 10, 22, 20);

  ServerNotificationRepository repository({
    bool Function()? mayStoreCaches,
  }) =>
      repositoryFor(server, storage,
          now: () => now, mayStoreCaches: mayStoreCaches);

  /// A new process: nothing in memory, only what was saved.
  Future<ServerNotificationRepository> restarted() async {
    final fresh = repository();
    await fresh.load();
    return fresh;
  }

  Map<String, dynamic> cache() =>
      jsonDecode(storage.values[serverNotificationCacheKey]!)
          as Map<String, dynamic>;

  setUp(() {
    server = FakeServer();
    storage = FakeStorage.existingInstall();
    now = DateTime.utc(2026, 10, 22, 20);
  });

  group('sync', () {
    test('replaces the list and returns the server interval', () async {
      final repo = repository();
      server.reply(jsonResponse(fixture('list-typical'), etag: 'W/"1"'));
      expect(await repo.sync(selection), 300);
      expect(repo.notifications, hasLength(3));
      expect(repo.unreadCount, 3);
    });

    test('304 keeps the data and has no interval', () async {
      final repo = repository();
      server
        ..reply(jsonResponse(fixture('list-typical'), etag: 'W/"1"'))
        ..replyNotModified();
      await repo.sync(selection);
      expect(await repo.sync(selection), isNull);
      expect(repo.notifications, hasLength(3));
      expect(server.requests.last.headers['If-None-Match'], 'W/"1"');
    });

    test('304 still applies known expiry', () async {
      final repo = repository();
      server
        ..replyList([item(expiresAt: '2026-10-22T21:00:00Z')])
        ..replyNotModified();
      await repo.sync(selection);
      now = DateTime.utc(2026, 10, 22, 21, 0, 1);
      await repo.sync(selection);
      expect(repo.notifications, isEmpty);
    });

    test('a validator is not reused for another selection', () async {
      final repo = repository();
      server
        ..replyList([])
        ..replyList([]);
      await repo.sync(selection);
      await repo.sync(const ServerNotificationSelection(
          platform: 'android', appVersion: '1.17.4', language: 'it'));
      expect(
          server.requests.last.headers.containsKey('If-None-Match'), isFalse);
    });

    test('revoked and out-of-audience items go with the next sync', () async {
      final repo = repository();
      server
        ..replyList([item(), item(id: b)], etag: 'W/"1"')
        ..replyList([item()], etag: 'W/"2"');
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.notifications.map((n) => n.id), [a]);
    });

    test('content is updated in place', () async {
      final repo = repository();
      server
        ..replyList([item(title: 'Alt')], etag: 'W/"1"')
        ..replyList([item(title: 'Neu', revision: 2)], etag: 'W/"2"');
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.notifications.single.title, 'Neu');
    });

    test('a failure keeps the list and says so', () async {
      final repo = repository();
      server
        ..replyList([item()])
        ..reply(http.Response('', 500))
        ..replyNotModified();
      await repo.sync(selection);
      await expectLater(
          repo.sync(selection), throwsA(isA<ServerNotificationFailure>()));
      expect(repo.notifications, hasLength(1));
      expect(repo.lastSyncFailed, isTrue);
      await repo.sync(selection);
      expect(repo.lastSyncFailed, isFalse);
    });

    test('empty list empties the center', () async {
      final repo = repository();
      server
        ..replyList([item()], etag: 'W/"1"')
        ..reply(jsonResponse(fixture('list-empty'), etag: 'W/"2"'));
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.notifications, isEmpty);
      expect(repo.unreadCount, 0);
    });

    test('a wrong device clock does not hide what is active', () async {
      // The device believes it is a month later than the server.
      now = DateTime.utc(2026, 11, 22, 20);
      final repo = repository();
      server.replyList([item(expiresAt: '2026-10-23T00:00:00Z')]);
      await repo.sync(selection);
      expect(repo.notifications, hasLength(1));
    });
  });

  group('read state', () {
    test('survives a restart, and read content leaves the offline cache',
        () async {
      final repo = repository();
      server.replyList([item(), item(id: b)]);
      await repo.sync(selection);
      await repo.markRead(a);
      expect(repo.unreadCount, 1);

      final ids = (cache()['unread'] as List).map((e) => (e as Map)['id']);
      expect(ids, [b]);

      final fresh = await restarted();
      expect(fresh.notifications.map((n) => n.id), [b],
          reason: 'offline, read content is not available');
      server.replyList([item(), item(id: b)]);
      await fresh.sync(selection);
      expect(fresh.notifications, hasLength(2),
          reason: 'online, read items return');
      expect(fresh.unreadCount, 1, reason: 'and they stay read');
      expect(fresh.pendingAlerts.map((n) => n.id), [b]);
    });

    test('device state holds no content', () async {
      final repo = repository();
      server.replyList([item(title: 'Geheimtitel', body: 'Geheimtext')]);
      await repo.sync(selection);
      await repo.markRead(a);
      await repo.markAlerted(repo.notifications);
      expect(storage.values[serverNotificationDeviceKey],
          isNot(contains('Geheim')));
      expect(storage.values[serverNotificationCacheKey],
          isNot(contains('Geheim')));
    });

    test('a 304 after a restart cannot lose read items', () async {
      final repo = repository();
      server.replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.markRead(a);

      final fresh = await restarted();
      expect(fresh.notifications, isEmpty);
      server.replyList([item()], etag: 'W/"1"');
      await fresh.sync(selection);
      expect(server.requests.last.headers.containsKey('If-None-Match'), isFalse,
          reason: 'the app lacks content, so it must not ask for a 304');
      expect(fresh.notifications, hasLength(1));

      server.replyNotModified();
      await fresh.sync(selection);
      expect(server.requests.last.headers['If-None-Match'], 'W/"1"');
      expect(fresh.notifications, hasLength(1));
    });

    test('the stored validator is used when everything is cached', () async {
      final repo = repository();
      server.replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);

      final fresh = await restarted();
      server.replyNotModified();
      await fresh.sync(selection);
      expect(server.requests.last.headers['If-None-Match'], 'W/"1"');
      expect(fresh.notifications, hasLength(1));
    });

    test('a dismissed item does not block the stored validator', () async {
      final repo = repository();
      server.replyList([item(), item(id: b)], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.dismiss(a);

      final fresh = await restarted();
      server.replyNotModified();
      await fresh.sync(selection);
      expect(server.requests.last.headers['If-None-Match'], 'W/"1"');
    });

    test('marking something unknown does nothing', () async {
      final repo = repository();
      await repo.load();
      await repo.markRead(a);
      expect(storage.writes, 0);
    });
  });

  group('alerts and attention_revision', () {
    test('new notifications are pending once, across polls and restarts',
        () async {
      final repo = repository();
      server
        ..replyList([item()], etag: 'W/"1"')
        ..replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);
      expect(repo.pendingAlerts, hasLength(1));
      await repo.markAlerted(repo.pendingAlerts);
      expect(repo.pendingAlerts, isEmpty);
      await repo.sync(selection);
      expect(repo.pendingAlerts, isEmpty);
      expect((await restarted()).pendingAlerts, isEmpty);
    });

    test('an alert that was never shown is not lost by a restart', () async {
      final repo = repository();
      server.replyList([item()]);
      await repo.sync(selection);
      expect((await restarted()).pendingAlerts, hasLength(1));
    });

    test('closing the popup is neither reading nor dismissing', () async {
      final repo = repository();
      server.replyList([item()]);
      await repo.sync(selection);
      await repo.markAlerted(repo.notifications);
      expect(repo.unreadCount, 1);
      expect(repo.notifications, hasLength(1));
    });

    test('a routine edit does not alert a read notification', () async {
      final repo = repository();
      server
        ..replyList([item(revision: 1)], etag: 'W/"1"')
        ..replyList([item(revision: 2, title: 'Neu')], etag: 'W/"2"');
      await repo.sync(selection);
      await repo.markRead(a);
      await repo.sync(selection);
      expect(repo.notifications.single.title, 'Neu');
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
    });

    test('a routine edit does not repeat the popup of an unread one', () async {
      final repo = repository();
      server
        ..replyList([item(revision: 1)], etag: 'W/"1"')
        ..replyList([item(revision: 2)], etag: 'W/"2"');
      await repo.sync(selection);
      await repo.markAlerted(repo.notifications);
      await repo.sync(selection);
      expect(repo.pendingAlerts, isEmpty);
    });

    test('an important edit alerts again and makes it unread', () async {
      final repo = repository();
      server
        ..replyList([item(attention: 1)], etag: 'W/"1"')
        ..replyList([item(attention: 2, revision: 2)], etag: 'W/"2"');
      await repo.sync(selection);
      await repo.markRead(a);
      await repo.sync(selection);
      expect(repo.unreadCount, 1);
      expect(repo.pendingAlerts, hasLength(1));
      expect((cache()['unread'] as List), hasLength(1),
          reason: 'unread again, so its content is cached again');
    });

    test('the fixture of an important revision re-alerts', () async {
      final repo = repository();
      final json = fixture('list-important-revision');
      final notification =
          (json['notifications'] as List).first as Map<String, dynamic>;
      final attention = notification['attention_revision'] as int;
      expect(attention, greaterThan(1));
      server.replyList([
        {...notification, 'attention_revision': attention - 1}
      ], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.markRead(notification['id'] as String);
      server.reply(jsonResponse(json, etag: 'W/"2"'));
      await repo.sync(selection);
      expect(repo.pendingAlerts, hasLength(1));
    });

    test('the read revision is kept per notification', () async {
      final repo = repository();
      server.replyList([item(attention: 3)]);
      await repo.sync(selection);
      await repo.markRead(a);
      final device = ServerNotificationDeviceState.decode(
          storage.values[serverNotificationDeviceKey]);
      expect(device.records[a]!.readAttentionRevision, 3);
    });
  });

  group('dismissal', () {
    test('is final, even after an important edit and a restart', () async {
      final repo = repository();
      server.replyList([item()]);
      await repo.sync(selection);
      await repo.dismiss(a);
      expect(repo.notifications, isEmpty);

      final fresh = await restarted();
      server.replyList([item(attention: 9, revision: 9)]);
      await fresh.sync(selection);
      expect(fresh.notifications, isEmpty);
      expect(fresh.unreadCount, 0);
      expect(fresh.pendingAlerts, isEmpty);
      expect(fresh.byId(a), isNull);
    });

    test('tombstones are never cleaned up, read records are', () async {
      final repo = repository();
      server.replyList([item(), item(id: b)], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.markRead(a);
      await repo.dismiss(b);

      now =
          now.add(serverNotificationRecordRetention + const Duration(days: 1));
      server.reply(jsonResponse(page([], serverTime: '2027-04-21T20:00:00Z'),
          etag: 'W/"2"'));
      await repo.sync(selection);
      final device = ServerNotificationDeviceState.decode(
          storage.values[serverNotificationDeviceKey]);
      expect(device.records, isEmpty);
      expect(device.dismissed.keys, [b]);
    });

    test('read records of active notifications are not cleaned up', () async {
      final repo = repository();
      server.replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.markRead(a);
      now = now.add(serverNotificationRecordRetention * 2);
      server.replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);
      expect(repo.unreadCount, 0);
    });

    test('a record that left the audience for a while is remembered', () async {
      final repo = repository();
      server
        ..replyList([item()], etag: 'W/"1"')
        ..replyList([], etag: 'W/"2"')
        ..replyList([item()], etag: 'W/"1"');
      await repo.sync(selection);
      await repo.markRead(a);
      await repo.sync(selection);
      await repo.sync(selection);
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
    });
  });

  group('expiry', () {
    test('known expiry is filtered offline, also from the cache', () async {
      final repo = repository();
      server.replyList([item(expiresAt: '2026-10-23T00:00:00Z')]);
      await repo.sync(selection);
      now = DateTime.utc(2026, 10, 23, 0, 0, 1);
      final fresh = await restarted();
      expect(fresh.notifications, isEmpty);
    });

    test('an open app drops it at the moment it expires, also offline', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 10, 22, 20);
        final repo =
            repositoryFor(server, storage, now: () => start.add(async.elapsed));
        var changes = 0;
        repo.addListener(() => changes++);
        server.replyList([item(expiresAt: '2026-10-22T20:00:10Z')]);
        unawaited(repo.sync(selection));
        async.flushMicrotasks();
        expect(repo.notifications, hasLength(1));

        changes = 0;
        async.elapse(const Duration(seconds: 9));
        expect(changes, 0);
        async.elapse(const Duration(seconds: 2));
        expect(changes, greaterThan(0), reason: 'the UI must hear about it');
        expect(repo.notifications, isEmpty);
        repo.dispose();
      });
    });

    test('an expired item counts as neither unread nor pending', () async {
      final repo = repository();
      server.replyList([item(expiresAt: '2026-10-22T20:00:10Z')]);
      await repo.sync(selection);
      expect(repo.unreadCount, 1);
      now = now.add(const Duration(minutes: 1));
      expect(repo.unreadCount, 0);
      expect(repo.pendingAlerts, isEmpty);
    });
  });

  group('storage', () {
    test('read failure leaves a working, empty repository', () async {
      storage.failReads = true;
      final repo = repository();
      await repo.load();
      expect(repo.storageFailed, isTrue);
      expect(repo.notifications, isEmpty);
      storage.failReads = false;
      server.replyList([item()]);
      await repo.sync(selection);
      expect(repo.notifications, hasLength(1));
    });

    test('write failure keeps everything working in memory', () async {
      final repo = repository();
      storage.failWrites = true;
      server.replyList([item()]);
      await repo.sync(selection);
      await repo.dismiss(a);
      expect(repo.storageFailed, isTrue);
      expect(repo.notifications, isEmpty);
    });

    test('recovers once writing works again', () async {
      final repo = repository();
      storage.failWrites = true;
      server.replyList([item()]);
      await repo.sync(selection);
      storage.failWrites = false;
      await repo.dismiss(a);
      expect(repo.storageFailed, isFalse);
      expect(storage.values[serverNotificationDeviceKey], contains(a));
    });

    test('a failed read cannot erase tombstones with the next write', () async {
      final first = repository();
      server.replyList([item()]);
      await first.sync(selection);
      await first.dismiss(a);

      storage.failReads = true;
      final second = repository();
      await second.load();
      storage.failReads = false;
      server.replyList([item(), item(id: b)]);
      await second.sync(selection);

      final device = ServerNotificationDeviceState.decode(
          storage.values[serverNotificationDeviceKey]);
      expect(device.dismissed.keys, contains(a));
      expect(second.notifications.map((n) => n.id), [b]);
    });

    test('corrupt data is survived', () async {
      storage.values[serverNotificationDeviceKey] = '{broken';
      storage.values[serverNotificationCacheKey] = '[1,2';
      final repo = await restarted();
      expect(repo.notifications, isEmpty);
      expect(repo.storageFailed, isFalse);
    });

    test('damaged entries do not cost the good ones', () async {
      storage.values[serverNotificationDeviceKey] = jsonEncode({
        'version': 1,
        'records': {'x': 'broken'},
        'dismissed': {a: 1000, 'y': 'broken'},
      });
      storage.values[serverNotificationCacheKey] = jsonEncode({
        'version': 1,
        'unread': [
          item(),
          item(id: b),
          {'id': 'broken'}
        ],
      });
      final repo = await restarted();
      expect(repo.notifications.map((n) => n.id), [b]);
    });

    test('a cache of another version is dropped, state of a newer one is read',
        () async {
      storage.values[serverNotificationDeviceKey] = jsonEncode({
        'version': 99,
        'dismissed': {b: 1000},
      });
      storage.values[serverNotificationCacheKey] = jsonEncode({
        'version': 99,
        'unread': [item()],
      });
      final repo = await restarted();
      expect(repo.notifications, isEmpty);
      server.replyList([item(id: b)]);
      await repo.sync(selection);
      expect(repo.notifications, isEmpty,
          reason: 'a downgrade keeps dismissal');
    });

    test('with saving of data turned off, no content is written', () async {
      final repo = repository(mayStoreCaches: () => false);
      server.replyList([item(title: 'Geheim')]);
      await repo.sync(selection);
      await repo.markAlerted(repo.notifications);
      expect(storage.values.containsKey(serverNotificationCacheKey), isFalse);
      expect(repo.notifications, hasLength(1));
      expect(storage.values[serverNotificationDeviceKey], contains(a));
    });

    test('turning saving off removes the existing cache', () async {
      var allowed = true;
      final repo = repository(mayStoreCaches: () => allowed);
      server.replyList([item()]);
      await repo.sync(selection);
      expect(storage.values.containsKey(serverNotificationCacheKey), isTrue);
      allowed = false;
      await repo.markAlerted(repo.notifications);
      expect(storage.values.containsKey(serverNotificationCacheKey), isFalse);
    });

    test('works with real shared preferences, and login is irrelevant',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = ServerNotificationRepository(
          api: server.api, now: () => now, mayStoreCaches: () => true);
      server.replyList([item()]);
      await repo.sync(selection);
      await repo.dismiss(a);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(serverNotificationDeviceKey), contains(a));
    });
  });

  group('locale fallback', () {
    test('German content for another language is shown as it arrives',
        () async {
      final repo = repository();
      const italian = ServerNotificationSelection(
          platform: 'android', appVersion: '1.17.4', language: 'it');
      server.reply(jsonResponse(fixture('list-locale-fallback')));
      await repo.sync(italian);
      expect(server.requests.single.url.queryParameters['lang'], 'it');
      expect(repo.notifications, isNotEmpty);
    });

    test('another language fetches in full and replaces the cached texts',
        () async {
      final german = repository();
      server.replyList([item(title: 'Wartung', body: 'Heute Abend')],
          etag: 'W/"de"');
      await german.sync(selection);
      expect(german.notifications.single.title, 'Wartung');

      // A restart finds the German cache; the language is now Italian.
      final italian = await restarted();
      expect(italian.notifications.single.title, 'Wartung');
      const it = ServerNotificationSelection(
          platform: 'android', appVersion: '1.17.4', language: 'it');
      server.replyList([item(title: 'Manutenzione', body: 'Stasera')],
          etag: 'W/"it"');
      await italian.sync(it);
      final request = server.requests.last;
      expect(request.url.queryParameters['lang'], 'it');
      expect(request.headers['if-none-match'], isNull,
          reason: 'the German validator must not answer for Italian');
      expect(italian.notifications.single.title, 'Manutenzione');
      expect(italian.notifications.single.body, 'Stasera');
    });
  });

  test('ordering is newest first, then by id', () {
    final older = parsed(item(publishedAt: '2026-01-01T00:00:00Z'));
    final newer = parsed(item(id: b));
    final sameTime = parsed(item());
    final list = [older, newer, sameTime]
      ..sort(ServerNotification.compareNewestFirst);
    expect(list.map((n) => n.id).toList(), [a, b, a]);
  });
}
