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

import 'dart:convert';

import 'package:dr/account_scope.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/local_data_inventory.dart';
import 'package:dr/middleware/middleware.dart' show secureStorage;
import 'package:shared_preferences/shared_preferences.dart';

/// The key of the page cache [namespace] of [scope] (#169).
///
/// The page caches hold register content, so they are kept in the encrypted
/// secure storage like the account state. The key names the account only by
/// [AccountScope.fileId], never by user name or school address.
String accountCacheKey(String namespace, AccountScope scope) =>
    '$namespace-v2-${scope.fileId}';

/// The dashboard's grade-deadline overrides (dates the user set) in
/// SharedPreferences.
const gradeDeadlineOverridesNamespace = 'gradeDeadlineOverrides';

/// The key of the grade-deadline overrides of [scope]: the hashed account
/// scope, never the user name or school address (#175).
String gradeDeadlineOverridesKey(AccountScope scope) =>
    accountCacheKey(gradeDeadlineOverridesNamespace, scope);

/// The key versions before #175 used:
/// `gradeDeadlineOverrides:{"username":…,"server_url":…}`.
String legacyGradeDeadlineOverridesKey(String accountStorageKey) =>
    '$gradeDeadlineOverridesNamespace:$accountStorageKey';

/// Moves the grade-deadline overrides of one account from [legacyKey] to
/// [key], then deletes [legacyKey]. A value already under [key] was written
/// by this version and wins; a value under [legacyKey] that is not a JSON
/// object could never be read and is only deleted. Running it again changes
/// nothing.
Future<void> migrateGradeDeadlineOverrides(
    {required String legacyKey, required String key}) async {
  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(legacyKey);
  if (legacy == null) return;
  if (!prefs.containsKey(key) && _isJsonObject(legacy)) {
    if (!await prefs.setString(key, legacy)) return;
  }
  await prefs.remove(legacyKey);
}

bool _isJsonObject(String value) {
  try {
    return jsonDecode(value) is Map;
  } on FormatException {
    return false;
  }
}

/// The page caches that versions before #169 kept as plain text in
/// SharedPreferences, under `<namespace>:<user and school>`.
const legacyPlainCacheNamespaces = [
  'homeworkSummary',
  'classRegisterLessons',
  'courseMaterials',
];

/// Removes the plain-text page caches of older versions (#169).
///
/// They are caches only: each page loads its data again and keeps it in the
/// encrypted store from then on.
Future<void> removeLegacyPlainCaches() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys().toList()) {
    if (legacyPlainCacheNamespaces.any((n) => key.startsWith('$n:'))) {
      await prefs.remove(key);
    }
  }
}

/// Reads the cache [key] from the secure storage; null when there is none or
/// it cannot be read. A cache that cannot be read is loaded again.
Future<String?> readAccountCache(String key) async {
  try {
    return await secureStorage.read(key: key);
  } catch (e, stack) {
    diagnostics.report(e, stack, DiagnosticError.storage);
    return null;
  }
}

/// Writes the cache [key] to the secure storage, unless caches may not be
/// kept right now (saving of data off, data being deleted).
Future<void> writeAccountCache(String key, String value) async {
  if (!localDataPolicy.mayStoreCaches) return;
  try {
    await secureStorage.write(key: key, value: value);
  } catch (e, stack) {
    diagnostics.report(e, stack, DiagnosticError.storage);
    rethrow;
  }
}

class PagePayloadSnapshot<T> {
  const PagePayloadSnapshot({
    required this.payload,
    required this.fetchedAt,
    required this.fingerprint,
  });

  final T payload;
  final DateTime fetchedAt;
  final String fingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
        'payload': payload,
        'fetchedAt': fetchedAt.toIso8601String(),
        'fingerprint': fingerprint,
      };

  factory PagePayloadSnapshot.fromPayload(T payload, {DateTime? fetchedAt}) {
    return PagePayloadSnapshot<T>(
      payload: payload,
      fetchedAt: fetchedAt ?? DateTime.now(),
      fingerprint: fingerprintForPagePayload(payload),
    );
  }

  static PagePayloadSnapshot<T>? tryParse<T>(
    String raw,
    T? Function(Object? rawPayload) parsePayload,
  ) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt']?.toString() ?? '',
      );
      if (fetchedAt == null) {
        return null;
      }
      final payload = parsePayload(decoded['payload']);
      if (payload == null) {
        return null;
      }
      final storedFingerprint = decoded['fingerprint']?.toString();
      return PagePayloadSnapshot<T>(
        payload: payload,
        fetchedAt: fetchedAt,
        fingerprint: storedFingerprint?.isNotEmpty == true
            ? storedFingerprint!
            : fingerprintForPagePayload(payload),
      );
    } catch (e, stack) {
      diagnostics.report(e, stack, DiagnosticError.storage);
      return null;
    }
  }
}

class PagePayloadCacheService {
  Future<PagePayloadSnapshot<T>?> load<T>(
    String key,
    T? Function(Object? rawPayload) parsePayload,
  ) async {
    final raw = await readAccountCache(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final snapshot = PagePayloadSnapshot.tryParse(raw, parsePayload);
    diagnostics.values({
      'cache_hit': snapshot != null,
      'data_source': snapshot != null ? 'cache' : 'unknown'
    });
    diagnostics.safeLog(snapshot != null ? 'cache_hit' : 'cache_miss');
    return snapshot;
  }

  Future<void> save<T>(String key, PagePayloadSnapshot<T> snapshot) async {
    diagnostics.update('operation', 'save');
    await writeAccountCache(key, json.encode(snapshot.toJson()));
    diagnostics.safeLog('cache_write');
  }
}

final PagePayloadCacheService pagePayloadCacheService =
    PagePayloadCacheService();

String fingerprintForPagePayload(Object? payload) {
  return json.encode(_normalizeJson(payload));
}

List<Map<String, dynamic>> parseMapListPayload(Object? rawPayload) {
  final list = rawPayload is List ? rawPayload : const <Object?>[];
  return list
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String? parseStringPayload(Object? rawPayload) {
  return rawPayload is String ? rawPayload : null;
}

dynamic _normalizeJson(dynamic value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return <String, dynamic>{
      for (final entry in entries)
        entry.key.toString(): _normalizeJson(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalizeJson).toList();
  }
  return value;
}
