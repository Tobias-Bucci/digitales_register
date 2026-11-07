import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:flutter/foundation.dart';

/// The only `schema_version` this client understands. The server raises it
/// only for breaking changes, so anything else is refused, never guessed at.
const supportedServerNotificationSchema = 1;

const _titleMaxChars = 120;
const _bodyMaxChars = 2000;
const _labelMaxChars = 40;
const _cursorMaxChars = 128;

final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
final _timestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');
final _color = RegExp(r'^#[0-9A-Fa-f]{6}$');
final _typeKey = RegExp(r'^[a-z][a-z0-9_-]{1,31}$');

// Control characters, and the marks that can reorder or hide text. The server
// refuses them; a client must not depend on that.
bool _isUnsafeCharacter(int rune) =>
    (rune < 0x20 && rune != 0x09 && rune != 0x0A) ||
    (rune >= 0x7F && rune <= 0x9F) ||
    rune == 0x200E ||
    rune == 0x200F ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069);

/// Plain text that is safe to show: unsafe characters removed, line breaks
/// unified, and at most [maxChars] characters. Markup stays literal text.
@visibleForTesting
String cleanServerNotificationText(
  String value, {
  required int maxChars,
  required bool multiline,
}) {
  var text = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (!multiline) text = text.replaceAll(RegExp(r'[\n\t]+'), ' ');
  text = String.fromCharCodes(
    text.runes.where((rune) => !_isUnsafeCharacter(rune)),
  ).trim();
  final runes = text.runes;
  return runes.length <= maxChars
      ? text
      : String.fromCharCodes(runes.take(maxChars)).trimRight();
}

DateTime? _parseTimestamp(Object? value) {
  if (value is! String || !_timestamp.hasMatch(value)) return null;
  return DateTime.tryParse(value)?.toUtc();
}

String _formatTimestamp(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

/// Custom type of a notification, as configured on the server.
@immutable
class ServerNotificationType {
  const ServerNotificationType({
    required this.key,
    required this.label,
    required this.colorValue,
    required this.icon,
    required this.critical,
  });

  final String key;
  final String label;

  /// ARGB value, or null if the server sent no usable color.
  final int? colorValue;

  /// Icon name. Unknown names are valid here and map to a fallback in the UI.
  final String icon;

  /// A critical notification's popup must be closed by hand.
  final bool critical;

  static ServerNotificationType? tryParse(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final label = json['label'];
    final icon = json['icon'];
    final critical = json['critical'];
    final color = json['color'];
    if (key is! String || !_typeKey.hasMatch(key)) return null;
    if (label is! String || icon is! String || critical is! bool) return null;
    final cleanLabel = cleanServerNotificationText(label,
        maxChars: _labelMaxChars, multiline: false);
    if (cleanLabel.isEmpty) return null;
    return ServerNotificationType(
      key: key,
      label: cleanLabel,
      colorValue: color is String && _color.hasMatch(color)
          ? 0xFF000000 | int.parse(color.substring(1), radix: 16)
          : null,
      icon: icon,
      critical: critical,
    );
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'color': colorValue == null
            ? null
            : '#${(colorValue! & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'icon': icon,
        'critical': critical,
      };
}

/// One public announcement. Title and body are plain text.
@immutable
class ServerNotification {
  const ServerNotification({
    required this.id,
    required this.revision,
    required this.attentionRevision,
    required this.title,
    required this.body,
    required this.type,
    required this.publishedAt,
    required this.expiresAt,
    required this.link,
  });

  /// Lower-case UUID, stable across edits.
  final String id;

  /// Raised by every edit. Updates the content in place, never alerts.
  final int revision;

  /// Raised by important edits only. May alert again.
  final int attentionRevision;
  final String title;
  final String body;
  final ServerNotificationType type;
  final DateTime publishedAt;
  final DateTime? expiresAt;

  /// Null if there is no link, or if it did not pass validation.
  final ServerNotificationLink? link;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Newest first, as the server orders them: `published_at`, then `id`.
  static int compareNewestFirst(ServerNotification a, ServerNotification b) {
    final byDate = b.publishedAt.compareTo(a.publishedAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  /// Null if a required field is missing or unusable. Unknown fields are
  /// ignored; a bad link only loses the link.
  static ServerNotification? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final revision = json['revision'];
    final attention = json['attention_revision'];
    final title = json['title'];
    final body = json['body'];
    if (id is! String || !_uuid.hasMatch(id)) return null;
    if (revision is! int || revision < 1) return null;
    if (attention is! int || attention < 1) return null;
    if (title is! String || body is! String) return null;
    final cleanTitle = cleanServerNotificationText(title,
        maxChars: _titleMaxChars, multiline: false);
    final cleanBody = cleanServerNotificationText(body,
        maxChars: _bodyMaxChars, multiline: true);
    if (cleanTitle.isEmpty || cleanBody.isEmpty) return null;
    final type = ServerNotificationType.tryParse(json['type']);
    final publishedAt = _parseTimestamp(json['published_at']);
    if (type == null || publishedAt == null) return null;
    final rawExpiry = json['expires_at'];
    final expiresAt = _parseTimestamp(rawExpiry);
    if (rawExpiry != null && expiresAt == null) return null;
    return ServerNotification(
      id: id.toLowerCase(),
      revision: revision,
      attentionRevision: attention,
      title: cleanTitle,
      body: cleanBody,
      type: type,
      publishedAt: publishedAt,
      expiresAt: expiresAt,
      link: ServerNotificationLink.tryParse(json['link']),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'revision': revision,
        'attention_revision': attentionRevision,
        'title': title,
        'body': body,
        'type': type.toJson(),
        'published_at': _formatTimestamp(publishedAt),
        'expires_at': expiresAt == null ? null : _formatTimestamp(expiresAt!),
        'link': link?.toJson(),
      };
}

/// The response body did not match the contract.
class ServerNotificationSchemaException implements Exception {
  const ServerNotificationSchemaException(this.message,
      {this.unsupportedVersion = false});

  final String message;

  /// The body is fine, but from a newer contract: retrying soon will not help.
  final bool unsupportedVersion;

  @override
  String toString() => 'ServerNotificationSchemaException: $message';
}

/// One page of `GET /api/v1/notifications`.
@immutable
class ServerNotificationPage {
  const ServerNotificationPage({
    required this.serverTime,
    required this.pollAfterSeconds,
    required this.nextCursor,
    required this.notifications,
    required this.rejectedCount,
  });

  final DateTime serverTime;
  final int pollAfterSeconds;
  final String? nextCursor;
  final List<ServerNotification> notifications;

  /// Entries left out because they were malformed.
  final int rejectedCount;

  /// Throws [ServerNotificationSchemaException] if the envelope is unusable.
  /// A single malformed entry does not cost the user the others.
  factory ServerNotificationPage.parse(Object? json) {
    if (json is! Map) {
      throw const ServerNotificationSchemaException('body is not an object');
    }
    final version = json['schema_version'];
    if (version is! int) {
      throw const ServerNotificationSchemaException('no schema_version');
    }
    if (version != supportedServerNotificationSchema) {
      throw const ServerNotificationSchemaException('unknown schema_version',
          unsupportedVersion: true);
    }
    final serverTime = _parseTimestamp(json['server_time']);
    final pollAfter = json['poll_after_seconds'];
    final cursor = json['next_cursor'];
    final entries = json['notifications'];
    if (serverTime == null) {
      throw const ServerNotificationSchemaException('bad server_time');
    }
    if (pollAfter is! int || pollAfter < 1) {
      throw const ServerNotificationSchemaException('bad poll_after_seconds');
    }
    if (cursor != null &&
        (cursor is! String ||
            cursor.isEmpty ||
            cursor.length > _cursorMaxChars)) {
      throw const ServerNotificationSchemaException('bad next_cursor');
    }
    if (entries is! List) {
      throw const ServerNotificationSchemaException('bad notifications');
    }
    final parsed = entries
        .map(ServerNotification.tryParse)
        .whereType<ServerNotification>()
        .toList();
    return ServerNotificationPage(
      serverTime: serverTime,
      pollAfterSeconds: pollAfter,
      nextCursor: cursor as String?,
      notifications: parsed,
      rejectedCount: entries.length - parsed.length,
    );
  }
}
