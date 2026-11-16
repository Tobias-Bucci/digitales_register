import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The random installation ID of this app, used only to vote in polls.
const pollInstallationIdKey = 'polls.installationId';

/// Which option this installation voted for, per poll.
const pollVotesKey = 'polls.votes';

/// Where the poll state is kept. Shared preferences work on every target,
/// including the web, where private browsing can make them fail at any time.
abstract interface class PollStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesPollStorage implements PollStorage {
  const SharedPreferencesPollStorage();

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    final saved =
        await (await SharedPreferences.getInstance()).setString(key, value);
    if (!saved) throw StateError('Could not save $key');
  }
}

final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// A random UUID version 4 from a secure source. Nothing about the device
/// goes into it.
@visibleForTesting
String randomInstallationId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The installation ID: created the first time the user votes, then kept.
/// It is read by nothing but the vote request.
class PollInstallationId {
  PollInstallationId(this._storage, {String Function()? generate})
      : _generate = generate ?? randomInstallationId;

  final PollStorage _storage;
  final String Function() _generate;
  String? _cached;

  /// The stored ID, or a new one that has been saved. Throws if it cannot be
  /// saved: an ID that is not kept would allow a second vote after a restart.
  Future<String> obtain() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await _storage.read(pollInstallationIdKey);
    if (stored != null && _uuidV4.hasMatch(stored)) return _cached = stored;
    final fresh = _generate();
    await _storage.write(pollInstallationIdKey, fresh);
    if (await _storage.read(pollInstallationIdKey) != fresh) {
      throw StateError('installation id was not kept');
    }
    return _cached = fresh;
  }
}

/// Which option this installation chose in each poll, so the poll screen is
/// right offline and after a restart. Holds poll and option ids only.
class PollVoteStore {
  PollVoteStore(this._storage);

  final PollStorage _storage;
  Map<String, String>? _votes;

  Future<Map<String, String>> _load() async {
    final loaded = _votes;
    if (loaded != null) return loaded;
    final votes = <String, String>{};
    try {
      final raw = await _storage.read(pollVotesKey);
      final json = raw == null ? null : jsonDecode(raw);
      if (json is Map) {
        json.forEach((poll, option) {
          if (poll is String && option is String) votes[poll] = option;
        });
      }
    } catch (_) {
      // Unreadable storage is an empty record; voting still works, and the
      // server answers a repeated vote with the first choice.
    }
    return _votes = votes;
  }

  /// The option this installation voted for, or null.
  Future<String?> votedFor(String pollId) async => (await _load())[pollId];

  /// Keeps [optionId] for [pollId]. A failure is ignored: the vote is on the
  /// server, and `409` brings the choice back.
  Future<void> remember(String pollId, String optionId) async {
    final votes = await _load();
    votes[pollId] = optionId;
    try {
      await _storage.write(pollVotesKey, jsonEncode(votes));
    } catch (_) {}
  }
}
