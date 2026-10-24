import 'dart:convert';

import 'package:dr/school_notification_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> disk;
  late SchoolNotificationEngine engine;
  late List<SchoolNotificationEvent> delivered;
  late SchoolNotificationPreferences preferences;
  final baseline = DateTime.utc(2026, 10, 1, 10);
  final account = notificationDigest(['https://school.example', 'student']);

  SchoolNotificationEngine restart() => SchoolNotificationEngine(
        read: (key) async => disk[key],
        write: (key, value) async {
          disk[key] = value;
        },
      );
  SchoolNotificationEvent event(int id,
          {String type = 'grade',
          bool viewed = false,
          DateTime? sent,
          int? feedId}) =>
      SchoolNotificationEvent.parse({
        'type': type,
        'objectId': id,
        'id': feedId ?? id,
        'timeSent': (sent ?? baseline.add(const Duration(minutes: 1)))
            .toIso8601String(),
        'read': viewed,
      })!;
  Future<void> sync(List<SchoolNotificationEvent> items,
          {String? user,
          bool permitted = true,
          Future<void> Function(SchoolNotificationEvent)? deliver}) =>
      engine.synchronize(
          account: user ?? account,
          events: items,
          preferences: preferences,
          permitted: permitted,
          now: baseline,
          deliver: deliver ??
              (e) async {
                delivered.add(e);
              });

  setUp(() {
    disk = {};
    delivered = [];
    preferences = SchoolNotificationPreferences(
        enabled: true, consent: SchoolNotificationConsent.accepted);
    engine = restart();
  });

  test('first synchronization quietly establishes both baselines', () async {
    await sync([event(1), event(2, type: 'message')]);
    expect(delivered, isEmpty);
    await sync([event(1), event(2, type: 'message')]);
    expect(delivered, isEmpty);
  });

  test('enabled category defaults alone cannot authorize a notification',
      () async {
    preferences.consent = SchoolNotificationConsent.unknown;
    await sync([]);
    await sync([event(1)]);
    expect(delivered, isEmpty);
    preferences.consent = SchoolNotificationConsent.accepted;
    await sync([event(1), event(2)]);
    expect(delivered, hasLength(1));
    expect(delivered.single.identity, event(2).identity);
  });

  test(
      'foreground detection persists a separate silent state without a read timestamp',
      () async {
    await sync([]);
    await engine.synchronize(
        account: account,
        events: [event(1)],
        preferences: preferences,
        permitted: true,
        foreground: true,
        now: baseline,
        deliver: (e) async => delivered.add(e));
    expect(delivered, isEmpty);
    final state = jsonDecode(disk[engine.key(account)]!) as Map;
    final record = (state['observations'] as Map)[event(1).identity] as Map;
    expect(record['presentation'], 'foreground');
    expect(record['firstDetectedAt'], baseline.toIso8601String());
    expect(record['locallyViewedAt'], isNull);
    await sync([event(1)]);
    expect(delivered, isEmpty);
    await engine.markViewed(account, event(1).identities);
    final read =
        (jsonDecode(disk[engine.key(account)]!) as Map)['observations'] as Map;
    expect((read[event(1).identity] as Map)['locallyViewedAt'], isNotNull);
  });

  test(
      'batch delivery observes durable claims and cannot replay a partially failed batch',
      () async {
    await sync([]);
    var batches = 0;
    await expectLater(
        engine.synchronize(
            account: account,
            events: [event(1), event(2)],
            preferences: preferences,
            permitted: true,
            now: baseline,
            deliverBatch: (batch) async {
              batches++;
              final state = jsonDecode(disk[engine.key(account)]!) as Map;
              expect(state['seen'], contains(event(1).identity));
              expect(state['seen'], contains(event(2).identity));
              throw StateError('native failure');
            }),
        throwsStateError);
    await sync([event(1), event(2)]);
    expect(batches, 1);
    expect(delivered, isEmpty);
  });

  for (final type in ['grade', 'message']) {
    test('new $type triggers exactly once across retries and restart',
        () async {
      await sync([]);
      await sync([event(1, type: type)]);
      engine = restart();
      for (var i = 0; i < 5; i++) {
        await sync([event(1, type: type)]);
      }
      expect(delivered, hasLength(1));
      expect(delivered.single.category.name, type);
    });
  }

  test('viewed items, including a view before the feed arrives, stay silent',
      () async {
    await sync([]);
    await engine.markViewed(account, [event(1).identity]);
    await sync([event(1), event(2, viewed: true)]);
    await sync([event(2), event(1)]);
    expect(delivered, isEmpty);
  });

  test('disabled categories are consumed and never replayed', () async {
    await sync([]);
    preferences.grades = false;
    await sync([event(1), event(2, type: 'message')]);
    preferences.grades = true;
    await sync([event(1), event(2, type: 'message')]);
    expect(
        delivered.map((e) => e.category), [SchoolNotificationCategory.message]);
  });

  test('re-enabling baselines events discovered while checks were disabled',
      () async {
    await sync([]);
    await engine.baselineNext(account, 'grade');
    await sync([event(1)]);
    await sync([event(1), event(2)]);
    expect(delivered.map((e) => e.objectId), [2]);
  });

  test('permission denial consumes events without showing them', () async {
    await sync([]);
    await sync([event(1)], permitted: false);
    await sync([event(1)], permitted: true);
    expect(delivered, isEmpty);
  });

  test('accounts have independent persistent histories', () async {
    final other = notificationDigest(['https://other.example', 'student']);
    await sync([]);
    await sync([event(1)]);
    await sync([event(1)], user: other);
    await sync([event(1), event(2)], user: other);
    engine = restart();
    await sync([event(1)]);
    expect(delivered.map((e) => e.objectId), [1, 2]);
  });

  test('concurrent engines serialize reads, claims and native deliveries',
      () async {
    await sync([]);
    final workers = List.generate(12, (_) => restart());
    await Future.wait(workers.map((worker) => worker.synchronize(
          account: account,
          events: [event(1), event(2, type: 'message')],
          preferences: preferences,
          permitted: true,
          now: baseline,
          deliver: (e) async {
            delivered.add(e);
          },
        )));
    expect(delivered.map((e) => e.objectId), [1, 2]);
  });

  test('partial native failure cannot replay claimed notifications', () async {
    await sync([]);
    await expectLater(
        sync([event(1), event(2)], deliver: (e) async {
          delivered.add(e);
          throw StateError('native failure');
        }),
        throwsStateError);
    engine = restart();
    await sync([event(1), event(2)]);
    expect(delivered, hasLength(1));
  });

  test('storage failure before claim causes no delivery and allows safe retry',
      () async {
    await sync([]);
    engine = SchoolNotificationEngine(
        read: (key) async => disk[key],
        write: (key, value) async {
          throw StateError('disk failure');
        });
    await expectLater(sync([event(1)]), throwsStateError);
    expect(delivered, isEmpty);
    engine = restart();
    await sync([event(1)]);
    expect(delivered, hasLength(1));
  });

  test(
      'edits, deletion, reordering and reissued feed IDs do not replay objects',
      () async {
    await sync([]);
    await sync([event(1), event(2)]);
    await sync([]);
    await sync([event(2, feedId: 999), event(1, feedId: 1000)]);
    expect(delivered.map((e) => e.objectId), [1, 2]);
  });

  test('late old entries do not alert', () async {
    await sync([]);
    await sync([event(1, sent: baseline.subtract(const Duration(days: 1)))]);
    expect(delivered, isEmpty);
  });

  test('missing IDs use immutable timestamp, independent of title edits', () {
    final data = {
      'type': 'grade',
      'timeSent': baseline.toIso8601String(),
      'title': 'Math 8'
    };
    final original = SchoolNotificationEvent.parse(data)!;
    data['title'] = 'Math 9';
    expect(SchoolNotificationEvent.parse(data)!.identity, original.identity);
  });

  test('general announcements and unknown event types are excluded', () {
    expect(SchoolNotificationEvent.parse({'type': 'general'}), isNull);
    expect(SchoolNotificationEvent.parse({'type': 'announcement'}), isNull);
    expect(SchoolNotificationEvent.parse({'type': 'other'}), isNull);
  });

  test('stable IDs gaining object context do not alert twice', () async {
    await sync([]);
    final raw = <String, Object?>{
      'type': 'grade',
      'id': 9,
      'timeSent': baseline.add(const Duration(minutes: 1)).toIso8601String()
    };
    await sync([SchoolNotificationEvent.parse(raw)!]);
    raw['objectId'] = 99;
    await sync([SchoolNotificationEvent.parse(raw)!]);
    expect(delivered, hasLength(1));
  });

  test('numeric IDs, empty read timestamps and malformed entries are handled',
      () {
    final raw = <String, Object?>{
      'type': 'message',
      'id': 9.0,
      'objectId': 99.0,
      'timeSent': baseline.toIso8601String(),
      'timeRead': ''
    };
    final original = SchoolNotificationEvent.parse(raw)!;
    expect(original.objectId, 99);
    expect(original.viewed, isFalse);
    raw['id'] = 9;
    raw['objectId'] = 99;
    expect(SchoolNotificationEvent.parse(raw)!.identity, original.identity);
    raw['read'] = 1;
    expect(SchoolNotificationEvent.parse(raw)!.viewed, isTrue);
    raw['timeSent'] = 'invalid';
    expect(SchoolNotificationEvent.parse(raw), isNull);
    expect(SchoolNotificationEvent.parse({'type': 'message'}), isNull);
  });

  test('corrupt history fails closed instead of silently resetting', () async {
    disk[engine.key(account)] = 'invalid';
    await expectLater(sync([event(1)]), throwsFormatException);
    expect(delivered, isEmpty);
  });

  test('retains large histories without evicting old claims', () async {
    await sync([]);
    final items = List.generate(10000, (id) => event(id));
    await sync(items);
    delivered.clear();
    engine = restart();
    await sync(items.reversed.toList());
    expect(delivered, isEmpty);
    expect((jsonDecode(disk[engine.key(account)]!) as Map)['seen'],
        hasLength(20000));
    expect(disk[engine.key(account)], isNot(contains('Math')));
  });

  test(
      'tap payload round trips exact message destination without personal data',
      () {
    final original = SchoolNotificationDestination(
        account, SchoolNotificationCategory.message, 42);
    final decoded = SchoolNotificationDestination.decode(original.encode())!;
    expect(decoded.account, account);
    expect(decoded.category, SchoolNotificationCategory.message);
    expect(decoded.objectId, 42);
    expect(original.encode(), isNot(contains('student')));
    expect(original.encode(), isNot(contains('school.example')));
  });

  test(
      'grade fallback supports missing destination ID and rejects invalid payloads',
      () {
    final original = SchoolNotificationDestination(
        account, SchoolNotificationCategory.grade, null);
    expect(SchoolNotificationDestination.decode(original.encode())!.objectId,
        isNull);
    for (final invalid in [null, '', '{}', '{"v":2}', 'not JSON']) {
      expect(SchoolNotificationDestination.decode(invalid), isNull);
    }
  });
}
