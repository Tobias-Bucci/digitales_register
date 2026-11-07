import 'dart:async';
import 'dart:math' as math;

import 'package:dr/local_data_inventory.dart';
import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_store.dart';
import 'package:flutter/foundation.dart';

/// Records of notifications no sync has listed for this long are removed. A
/// notification can leave the audience and return after an app update, so
/// they are kept for a while to avoid alerting about it a second time.
const serverNotificationRecordRetention = Duration(days: 180);

/// The notifications of this device: what the server says is active, combined
/// with what the user did here.
///
/// Order of precedence for every notification: dismissed first, then expired,
/// then read state. Revoked and out-of-audience notifications disappear with
/// the next complete sync; while offline, the client cannot know about them.
class ServerNotificationRepository extends ChangeNotifier {
  ServerNotificationRepository({
    ServerNotificationApi? api,
    ServerNotificationStorage storage =
        const SharedPreferencesServerNotificationStorage(),
    DateTime Function()? now,
    bool Function()? mayStoreCaches,
  })  : _api = api,
        _storage = storage,
        _deviceNow = now ?? DateTime.now,
        _mayStoreCaches =
            mayStoreCaches ?? (() => localDataPolicy.mayStoreCaches);

  ServerNotificationApi? _api;
  final ServerNotificationStorage _storage;

  // Deliberately the real clock, not appClock: the demo mode's simulated date
  // has no meaning for server timestamps.
  final DateTime Function() _deviceNow;
  final bool Function() _mayStoreCaches;

  final Map<String, ServerNotification> _items = {};
  ServerNotificationDeviceState _device = ServerNotificationDeviceState();
  String? _etag;
  String? _etagSelection;
  Set<String> _collectionIds = const {};
  Duration _clockOffset = Duration.zero;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  Timer? _expiryTimer;
  bool _disposed = false;

  bool _lastSyncFailed = false;

  /// The last sync failed, so the list may be out of date.
  bool get lastSyncFailed => _lastSyncFailed;

  bool _storageFailed = false;

  /// The saved state could not be read, so writing now could erase tombstones.
  bool _deviceUnread = false;

  /// State could not be saved. It still works until the app is closed.
  bool get storageFailed => _storageFailed;

  /// Replaces the API client once the configuration is known.
  // ignore: avoid_setters_without_getters
  set api(ServerNotificationApi value) => _api = value;

  DateTime get _now => _deviceNow().toUtc().add(_clockOffset);

  bool _isVisible(ServerNotification item, DateTime now) =>
      !_device.dismissed.containsKey(item.id) && !item.isExpiredAt(now);

  /// What the center shows, newest first.
  List<ServerNotification> get notifications {
    final now = _now;
    return _items.values.where((item) => _isVisible(item, now)).toList()
      ..sort(ServerNotification.compareNewestFirst);
  }

  ServerNotification? byId(String id) {
    final item = _items[id];
    return item != null && _isVisible(item, _now) ? item : null;
  }

  bool isUnread(ServerNotification item) =>
      item.attentionRevision >
      (_device.records[item.id]?.readAttentionRevision ?? 0);

  int get unreadCount => notifications.where(isUnread).length;

  bool _needsAlert(ServerNotification item) {
    final record = _device.records[item.id];
    return item.attentionRevision >
        math.max(record?.readAttentionRevision ?? 0,
            record?.alertedAttentionRevision ?? 0);
  }

  /// Notifications no popup has announced yet at their `attention_revision`.
  /// A routine edit does not change this; an important one does.
  List<ServerNotification> get pendingAlerts =>
      notifications.where(_needsAlert).toList();

  /// Reads the saved state once. A failure leaves an empty, working repository.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _device = ServerNotificationDeviceState.decode(
          await _storage.read(serverNotificationDeviceKey));
    } catch (_) {
      _storageFailed = true;
      _deviceUnread = true;
    }
    try {
      final cache = ServerNotificationCache.decode(
          await _storage.read(serverNotificationCacheKey));
      if (_mayStoreCaches()) {
        final now = _now;
        for (final item in cache.unread) {
          // Checked again: the cache may be older than the last dismissal.
          if (_isVisible(item, now) && isUnread(item)) _items[item.id] = item;
        }
        _etag = cache.etag;
        _etagSelection = cache.selectionKey;
        _collectionIds = cache.collectionIds;
      }
    } catch (_) {
      _storageFailed = true;
    }
    _scheduleExpiry();
    _notify();
  }

  /// The validator to send, or null if a `304` would leave a gap.
  ///
  /// Read content is not cached, so after a restart the app may know a
  /// collection only partly. A `304` would then confirm a list the app cannot
  /// show, and read notifications would be missing until the next change. So
  /// the validator is only used if everything it covers is available here.
  String? _validatorFor(ServerNotificationSelection selection) {
    if (_etag == null || _etagSelection != selection.cacheKey) return null;
    final complete = _collectionIds.every(
        (id) => _items.containsKey(id) || _device.dismissed.containsKey(id));
    return complete ? _etag : null;
  }

  /// Fetches the complete set and merges it. Returns the server's suggested
  /// delay in seconds, or null on `304`, which carries none.
  ///
  /// Throws [ServerNotificationFailure]; the current list then stays as it is.
  Future<int?> sync(ServerNotificationSelection selection) async {
    await load();
    final api = _api;
    if (api == null) {
      throw const ServerNotificationFailure(
          ServerNotificationFailureKind.permanent);
    }
    final ServerNotificationFetchResult result;
    try {
      result = await api.fetch(selection, etag: _validatorFor(selection));
    } on ServerNotificationFailure {
      _lastSyncFailed = true;
      _removeExpired();
      _notify();
      rethrow;
    }
    _lastSyncFailed = false;
    switch (result) {
      case ServerNotificationsNotModified():
        _removeExpired();
        await _persist();
        _notify();
        return null;
      case ServerNotificationsFetched():
        _apply(result, selection);
        await _persist();
        _notify();
        return result.pollAfterSeconds;
    }
  }

  void _apply(
    ServerNotificationsFetched result,
    ServerNotificationSelection selection,
  ) {
    // A wrong device clock must not hide what the server just called active.
    _clockOffset = result.serverTime.difference(_deviceNow().toUtc());
    final now = _now;
    _items
      ..clear()
      ..addEntries(result.notifications
          .where((item) => !_device.dismissed.containsKey(item.id))
          .map((item) => MapEntry(item.id, item)));
    _etag = result.etag;
    _etagSelection = selection.cacheKey;
    _collectionIds = result.notifications.map((item) => item.id).toSet();
    for (final id in _collectionIds) {
      final record = _device.records[id];
      if (record != null) _device.records[id] = record.copyWith(lastSeen: now);
    }
    _device.records.removeWhere((id, record) =>
        !_collectionIds.contains(id) &&
        now.difference(record.lastSeen) > serverNotificationRecordRetention);
    _removeExpired();
  }

  /// Opening a notification is what reads it. Its content leaves the offline
  /// cache; this session keeps showing it, and so does any later online start.
  Future<void> markRead(String id) async {
    final item = _items[id];
    if (item == null || !isUnread(item)) return;
    _device.records[id] =
        (_device.records[id] ?? ServerNotificationRecord(lastSeen: _now))
            .copyWith(readAttentionRevision: item.attentionRevision);
    _notify();
    await _persist();
  }

  /// A popup announced [items]. This is neither reading nor dismissing.
  Future<void> markAlerted(Iterable<ServerNotification> items) async {
    for (final item in items) {
      _device.records[item.id] =
          (_device.records[item.id] ?? ServerNotificationRecord(lastSeen: _now))
              .copyWith(alertedAttentionRevision: item.attentionRevision);
    }
    _notify();
    await _persist();
  }

  /// Hides a notification on this device for good, even after important edits.
  Future<void> dismiss(String id) async {
    _device.dismissed[id] = _now;
    _device.records.remove(id);
    _items.remove(id);
    _notify();
    await _persist();
  }

  void _removeExpired() {
    final now = _now;
    _items.removeWhere((_, item) => item.isExpiredAt(now));
    _scheduleExpiry();
  }

  /// Takes a notification off the screen at the moment it expires, also when
  /// the app stays open and offline.
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final expiries = _items.values
        .map((item) => item.expiresAt)
        .whereType<DateTime>()
        .toList();
    if (expiries.isEmpty || _disposed) return;
    final next = expiries.reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(_now);
    // Timers do not need to be exact, and days ahead are never reached anyway.
    _expiryTimer = Timer(
      delay.isNegative
          ? Duration.zero
          : delay > const Duration(days: 1)
              ? const Duration(days: 1)
              : delay,
      () {
        _removeExpired();
        _notify();
        unawaited(_persist());
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Writes one after the other, so an older state cannot overwrite a newer
  /// one. Never throws: the state in memory keeps working without storage.
  Future<void> _persist() => _writes = _writes.then((_) => _write());

  Future<void> _write() async {
    final mayCache = _mayStoreCaches();
    final cache = ServerNotificationCache(
      unread: _items.values.where(isUnread).toList(),
      etag: _etag,
      selectionKey: _etagSelection,
      collectionIds: _collectionIds,
    ).encode();
    var failed = false;
    try {
      if (_deviceUnread) await _mergeStoredDeviceState();
      await _storage.write(serverNotificationDeviceKey, _device.encode());
    } catch (_) {
      failed = true;
    }
    try {
      if (mayCache) {
        await _storage.write(serverNotificationCacheKey, cache);
      } else {
        await _storage.remove(serverNotificationCacheKey);
      }
    } catch (_) {
      failed = true;
    }
    _storageFailed = failed;
  }

  Future<void> _mergeStoredDeviceState() async {
    final stored = ServerNotificationDeviceState.decode(
        await _storage.read(serverNotificationDeviceKey));
    _deviceUnread = false;
    stored.dismissed.forEach((id, at) {
      _device.dismissed.putIfAbsent(id, () => at);
    });
    stored.records.forEach((id, record) {
      _device.records.putIfAbsent(id, () => record);
    });
    _device.dismissed.keys.forEach(_device.records.remove);
    _items.removeWhere((id, _) => _device.dismissed.containsKey(id));
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
