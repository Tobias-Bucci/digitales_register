import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mutex/mutex.dart';

String notificationDigest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

enum SchoolNotificationCategory { grade, message }

/// Personal school events only. General announcements deliberately stay in the bell.
class SchoolNotificationEvent {
  SchoolNotificationEvent({
    required this.category,
    required this.identity,
    required this.sent,
    this.objectId,
    this.viewed = false,
    this.aliases = const [],
    this.fallbackIdentity,
  });

  final SchoolNotificationCategory category;
  final String identity;
  final DateTime sent;
  final int? objectId;
  final bool viewed;
  final List<String> aliases;
  final String? fallbackIdentity;
  Iterable<String> get identities => [identity, ...aliases];

  // The reference's notification_type.dart identifies messageShared as a
  // message and compares the portal's types without case sensitivity.
  static SchoolNotificationCategory? categoryFor(Object? type) =>
      switch (type is String ? type.toLowerCase() : null) {
        'grade' => SchoolNotificationCategory.grade,
        'message' || 'messageshared' => SchoolNotificationCategory.message,
        _ => null,
      };

  static SchoolNotificationEvent? parse(Map item) {
    final category = categoryFor(item['type']);
    if (category == null) return null;
    final timestamp = item['timeSent'];
    final sent =
        timestamp is String ? DateTime.tryParse(timestamp)?.toUtc() : null;
    if (sent == null) return null;
    int? identifier(Object? value) {
      if (value is num && value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      return int.tryParse('$value');
    }

    final objectId = identifier(item['objectId']);
    final id = identifier(item['id']);
    final fallback =
        notificationDigest([category.name, sent.toIso8601String()]);
    // Prefer the underlying object: editing it or reissuing a feed entry must
    // not alert again. Without IDs, conservatively group by immutable timestamp.
    return SchoolNotificationEvent(
      category: category,
      identity: notificationDigest([
        category.name,
        if (objectId != null)
          'object:$objectId'
        else if (id != null)
          'event:$id'
        else
          sent.toIso8601String(),
      ]),
      sent: sent,
      objectId: objectId,
      viewed: item['read'] == true ||
          item['read'] == 1 ||
          (item['timeRead'] != null && item['timeRead'] != ''),
      aliases: [
        if (id != null) notificationDigest([category.name, 'event:$id'])
      ],
      fallbackIdentity: fallback,
    );
  }
}

enum SchoolNotificationConsent { unknown, accepted, declined }

class SchoolNotificationPreferences {
  SchoolNotificationPreferences(
      {this.enabled = false,
      this.grades = true,
      this.messages = true,
      this.consent = SchoolNotificationConsent.unknown,
      this.showEventCount = false});
  SchoolNotificationConsent consent;
  bool enabled;
  bool showEventCount;
  bool grades;
  bool messages;
  bool allows(SchoolNotificationCategory category) =>
      consent == SchoolNotificationConsent.accepted &&
      enabled &&
      (category == SchoolNotificationCategory.grade ? grades : messages);
  Map<String, dynamic> toJson() => {
        'decision': consent.name,
        'enabled': enabled,
        'grades': grades,
        'messages': messages,
        'showEventCount': showEventCount
      };
}

/// The caller holds an inter-isolate transaction lock for every operation.
/// Claims are durably written BEFORE delivery. A crash between claiming and
/// showing may lose an alert, but cannot replay an already delivered alert.
class SchoolNotificationEngine {
  static final _mutex = Mutex();
  SchoolNotificationEngine({required this.read, required this.write});
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;

  String key(String account) => 'school-notifications-v1-$account';

  Future<Map<String, dynamic>> _load(String account) async {
    final raw = await read(key(account));
    if (raw == null) return <String, dynamic>{};
    // Fail closed on corruption; silently resetting would replay history.
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> baselineNext(String account, String category) =>
      _mutex.protect(() async {
        final state = await _load(account);
        state.remove('baseline:$category');
        await write(key(account), jsonEncode(state));
      });

  Future<void> markViewed(String account, Iterable<String> identities) =>
      _mutex.protect(() async {
        final state = await _load(account);
        final seen = Set<String>.from(state['seen'] as List? ?? []);
        final seenBefore = seen.length;
        seen.addAll(identities);
        state['seen'] = seen.toList();
        final observations =
            Map<String, dynamic>.from(state['observations'] as Map? ?? {});
        var changed = seen.length != seenBefore;
        for (final identity in identities) {
          final record =
              observations.putIfAbsent(identity, () => <String, dynamic>{});
          if (record is Map && record['locallyViewedAt'] == null) {
            record['locallyViewedAt'] =
                DateTime.now().toUtc().toIso8601String();
            changed = true;
          }
        }
        state['observations'] = observations;
        if (changed) {
          await write(key(account), jsonEncode(state));
        }
      });

  Future<void> synchronize({
    required String account,
    required List<SchoolNotificationEvent> events,
    required SchoolNotificationPreferences preferences,
    required bool permitted,
    required DateTime now,
    Future<void> Function(SchoolNotificationEvent event)? deliver,
    Future<void> Function(List<SchoolNotificationEvent> events)? deliverBatch,
    bool foreground = false,
  }) =>
      _mutex.protect(() async {
        final state = await _load(account);
        final seen = Set<String>.from(state['seen'] as List? ?? []);
        final seenBefore = seen.length;
        final hadBaselines = SchoolNotificationCategory.values.every(
            (category) => state.containsKey('baseline:${category.name}'));
        final deliverable = <SchoolNotificationEvent>[];
        final observedAt = now.toUtc().toIso8601String();
        final observations =
            Map<String, dynamic>.from(state['observations'] as Map? ?? {});
        for (final category in SchoolNotificationCategory.values) {
          final baselineKey = 'baseline:${category.name}';
          final baseline = state[baselineKey] as String?;
          final cutoff = baseline == null ? null : DateTime.parse(baseline);
          for (final event in events.where((e) => e.category == category)) {
            final fresh = !event.identities.any(seen.contains) &&
                !seen.contains(event.fallbackIdentity);
            seen.addAll(event.identities);
            if (fresh) {
              // No content, server address or credentials are stored here.
              observations[event.identity] = {
                'serverSentAt': event.sent.toIso8601String(),
                if (event.viewed) 'serverReadReported': true,
                'firstDetectedAt': observedAt,
                'storedAt': observedAt,
                'presentation': cutoff == null
                    ? 'baseline'
                    : event.viewed
                        ? 'read'
                        : !preferences.allows(category)
                            ? 'disabled'
                            : foreground
                                ? 'foreground'
                                : !permitted
                                    ? 'permissionDenied'
                                    : !event.sent.isAfter(cutoff)
                                        ? 'olderThanBaseline'
                                        : 'claimed',
              };
              state['lastDetectedAt'] = observedAt;
            }
            if (fresh &&
                cutoff != null &&
                event.sent.isAfter(cutoff) &&
                !event.viewed &&
                !foreground &&
                permitted &&
                preferences.allows(category)) {
              deliverable.add(event);
            }
          }
          state[baselineKey] ??= now.toUtc().toIso8601String();
        }
        state['seen'] = seen.toList();
        state['observations'] = observations;
        if (seen.length != seenBefore || !hadBaselines) {
          await write(key(account), jsonEncode(state));
        }
        // All claims are persisted together; even partial native failures cannot
        // duplicate earlier notifications when the background job is retried.
        if (deliverable.isNotEmpty && deliverBatch != null) {
          await deliverBatch(deliverable);
        } else {
          for (final event in deliverable) {
            await deliver?.call(event);
          }
        }
      });
}

class SchoolNotificationDestination {
  SchoolNotificationDestination(this.account, this.category, this.objectId);
  final String account;
  final SchoolNotificationCategory category;
  final int? objectId;
  String encode() => jsonEncode({
        'v': 1,
        'account': account,
        'category': category.name,
        'id': objectId,
      });
  static SchoolNotificationDestination? decode(String? payload) {
    try {
      final data = jsonDecode(payload!) as Map;
      if (data['v'] != 1 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['account'] as String)) {
        return null;
      }
      return SchoolNotificationDestination(
          data['account'] as String,
          SchoolNotificationCategory.values.byName(data['category'] as String),
          data['id'] as int?);
    } catch (_) {
      return null;
    }
  }
}
