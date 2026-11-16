import 'dart:math';

import 'package:dr/polls/poll_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryPollStorage implements PollStorage {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;

  /// Accepts writes but forgets them, like a quota that drops data.
  bool forget = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('quota exceeded');
    if (!forget) values[key] = value;
  }
}

final _v4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  group('installation id', () {
    test('is a random UUID version 4', () {
      final ids = {for (var i = 0; i < 50; i++) randomInstallationId()};
      expect(ids, hasLength(50));
      for (final id in ids) {
        expect(id, matches(_v4));
      }
      expect(randomInstallationId(Random(1)), matches(_v4));
    });

    test('is created once and kept', () async {
      final storage = MemoryPollStorage();
      var created = 0;
      String make() {
        created++;
        return randomInstallationId();
      }

      final first = await PollInstallationId(storage, generate: make).obtain();
      expect(storage.values[pollInstallationIdKey], first);
      // A restart: a new object reads what was saved.
      final again = await PollInstallationId(storage, generate: make).obtain();
      expect(again, first);
      expect(created, 1);
    });

    test('a damaged stored value is replaced', () async {
      final storage = MemoryPollStorage()
        ..values[pollInstallationIdKey] = 'not-an-id';
      final id = await PollInstallationId(storage).obtain();
      expect(id, matches(_v4));
      expect(storage.values[pollInstallationIdKey], id);
    });

    test('an id that cannot be kept is refused, so no second vote follows',
        () async {
      expect(
          PollInstallationId(MemoryPollStorage()..failWrites = true).obtain(),
          throwsStateError);
      expect(PollInstallationId(MemoryPollStorage()..forget = true).obtain(),
          throwsStateError);
      expect(PollInstallationId(MemoryPollStorage()..failReads = true).obtain(),
          throwsStateError);
    });

    test('is saved in shared preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final id = await PollInstallationId(const SharedPreferencesPollStorage())
          .obtain();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(pollInstallationIdKey), id);
    });
  });

  group('local votes', () {
    test('are kept per poll and survive a restart', () async {
      final storage = MemoryPollStorage();
      final store = PollVoteStore(storage);
      expect(await store.votedFor('p1'), isNull);
      await store.remember('p1', 'a');
      await store.remember('p2', 'b');
      final restarted = PollVoteStore(storage);
      expect(await restarted.votedFor('p1'), 'a');
      expect(await restarted.votedFor('p2'), 'b');
      // Only poll and option ids are stored.
      expect(storage.values[pollVotesKey], '{"p1":"a","p2":"b"}');
    });

    test('unreadable or damaged storage is an empty record', () async {
      expect(
          await PollVoteStore(MemoryPollStorage()..failReads = true)
              .votedFor('p1'),
          isNull);
      final damaged = MemoryPollStorage()..values[pollVotesKey] = '{broken';
      expect(await PollVoteStore(damaged).votedFor('p1'), isNull);
      final wrongShape = MemoryPollStorage()..values[pollVotesKey] = '[1,2]';
      expect(await PollVoteStore(wrongShape).votedFor('p1'), isNull);
    });

    test('a failed write does not throw and keeps the vote in memory',
        () async {
      final store = PollVoteStore(MemoryPollStorage()..failWrites = true);
      await store.remember('p1', 'a');
      expect(await store.votedFor('p1'), 'a');
    });
  });
}
