import 'dart:convert';

import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read state and dismissals: what the user did on this device.
const serverNotificationDeviceKey = 'serverNotifications.device';

/// Unread content and its validator. Can be fetched again at any time.
const serverNotificationCacheKey = 'serverNotifications.cache';

const serverNotificationStoreVersion = 1;

/// Where the state is kept. Shared preferences work on every target, including
/// the web, where private browsing can make them fail at any moment.
abstract interface class ServerNotificationStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesServerNotificationStorage
    implements ServerNotificationStorage {
  const SharedPreferencesServerNotificationStorage();

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    final saved =
        await (await SharedPreferences.getInstance()).setString(key, value);
    if (!saved) throw StateError('Could not save $key');
  }

  @override
  Future<void> remove(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}

/// Minimal metadata of one notification. Never its content.
@immutable
class ServerNotificationRecord {
  const ServerNotificationRecord({
    this.readAttentionRevision = 0,
    this.alertedAttentionRevision = 0,
    required this.lastSeen,
  });

  /// The `attention_revision` the user has opened. Zero if never opened.
  final int readAttentionRevision;

  /// The `attention_revision` a popup has already announced.
  final int alertedAttentionRevision;

  /// When a sync last listed it, for removing records of old notifications.
  final DateTime lastSeen;

  ServerNotificationRecord copyWith({
    int? readAttentionRevision,
    int? alertedAttentionRevision,
    DateTime? lastSeen,
  }) =>
      ServerNotificationRecord(
        readAttentionRevision:
            readAttentionRevision ?? this.readAttentionRevision,
        alertedAttentionRevision:
            alertedAttentionRevision ?? this.alertedAttentionRevision,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, Object> toJson() => {
        'read': readAttentionRevision,
        'alerted': alertedAttentionRevision,
        'seen': lastSeen.millisecondsSinceEpoch,
      };

  static ServerNotificationRecord? tryParse(Object? json) {
    if (json is! Map) return null;
    final read = json['read'];
    final alerted = json['alerted'];
    final seen = json['seen'];
    if (read is! int || alerted is! int || seen is! int) return null;
    return ServerNotificationRecord(
      readAttentionRevision: read,
      alertedAttentionRevision: alerted,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(seen, isUtc: true),
    );
  }
}

/// What the user did on this device. Scoped to the installation, not to an
/// account: signing in or out does not touch it.
class ServerNotificationDeviceState {
  ServerNotificationDeviceState({
    Map<String, ServerNotificationRecord>? records,
    Map<String, DateTime>? dismissed,
  })  : records = records ?? {},
        dismissed = dismissed ?? {};

  final Map<String, ServerNotificationRecord> records;

  /// Tombstones: id and time of dismissal. Checked before anything else and
  /// never cleaned up, because dismissal is final on this device.
  final Map<String, DateTime> dismissed;

  String encode() => jsonEncode({
        'version': serverNotificationStoreVersion,
        'records': records.map((id, record) => MapEntry(id, record.toJson())),
        'dismissed':
            dismissed.map((id, at) => MapEntry(id, at.millisecondsSinceEpoch)),
      });

  /// Tolerates damage entry by entry, so that one bad record does not cost the
  /// tombstones. Data from a newer version is read as far as it is understood:
  /// a downgrade must not bring a dismissed notification back.
  static ServerNotificationDeviceState decode(String? raw) {
    final state = ServerNotificationDeviceState();
    if (raw == null) return state;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return state;
    }
    if (json is! Map) return state;
    final records = json['records'];
    if (records is Map) {
      records.forEach((id, value) {
        final record = ServerNotificationRecord.tryParse(value);
        if (id is String && record != null) state.records[id] = record;
      });
    }
    final dismissed = json['dismissed'];
    if (dismissed is Map) {
      dismissed.forEach((id, value) {
        if (id is String && value is int) {
          state.dismissed[id] =
              DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        }
      });
    }
    return state;
  }
}

/// The offline copy of unread notifications. Read content is never in here.
@immutable
class ServerNotificationCache {
  const ServerNotificationCache({
    this.unread = const [],
    this.etag,
    this.selectionKey,
    this.collectionIds = const {},
  });

  final List<ServerNotification> unread;
  final String? etag;

  /// The selection [etag] was received for.
  final String? selectionKey;

  /// Every id of the collection [etag] describes.
  final Set<String> collectionIds;

  String encode() => jsonEncode({
        'version': serverNotificationStoreVersion,
        'unread': [for (final item in unread) item.toJson()],
        'etag': etag,
        'selection': selectionKey,
        'ids': collectionIds.toList(),
      });

  /// A cache that cannot be read is an empty cache: it can be fetched again.
  factory ServerNotificationCache.decode(String? raw) {
    if (raw == null) return const ServerNotificationCache();
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return const ServerNotificationCache();
    }
    if (json is! Map || json['version'] != serverNotificationStoreVersion) {
      return const ServerNotificationCache();
    }
    final unread = json['unread'];
    final etag = json['etag'];
    final selection = json['selection'];
    final ids = json['ids'];
    return ServerNotificationCache(
      unread: unread is List
          ? unread
              .map(ServerNotification.tryParse)
              .whereType<ServerNotification>()
              .toList()
          : const [],
      etag: etag is String ? etag : null,
      selectionKey: selection is String ? selection : null,
      collectionIds: ids is List ? ids.whereType<String>().toSet() : const {},
    );
  }
}
