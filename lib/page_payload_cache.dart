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

import 'package:shared_preferences/shared_preferences.dart';

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
    } catch (_) {
      return null;
    }
  }
}

class PagePayloadCacheService {
  Future<PagePayloadSnapshot<T>?> load<T>(
    String key,
    T? Function(Object? rawPayload) parsePayload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return PagePayloadSnapshot.tryParse(raw, parsePayload);
  }

  Future<void> save<T>(String key, PagePayloadSnapshot<T> snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(snapshot.toJson()));
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
