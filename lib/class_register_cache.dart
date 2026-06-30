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

class ClassRegisterPayloadSnapshot {
  const ClassRegisterPayloadSnapshot({
    required this.payload,
    required this.fetchedAt,
    required this.fingerprint,
  });

  final List<Map<String, dynamic>> payload;
  final DateTime fetchedAt;
  final String fingerprint;

  Map<String, Object?> toJson() => <String, Object?>{
        'payload': payload,
        'fetchedAt': fetchedAt.toIso8601String(),
        'fingerprint': fingerprint,
      };

  factory ClassRegisterPayloadSnapshot.fromPayload(
    List<Map<String, dynamic>> payload, {
    DateTime? fetchedAt,
  }) {
    final normalizedPayload = _normalizePayload(payload);
    return ClassRegisterPayloadSnapshot(
      payload: normalizedPayload,
      fetchedAt: fetchedAt ?? DateTime.now(),
      fingerprint: fingerprintForPayload(normalizedPayload),
    );
  }

  static ClassRegisterPayloadSnapshot? tryParse(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }
      final rawPayload = decoded['payload'];
      if (rawPayload is! List) {
        return null;
      }
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt']?.toString() ?? '',
      );
      if (fetchedAt == null) {
        return null;
      }
      final payload = _normalizePayload(
        rawPayload
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
      final storedFingerprint = decoded['fingerprint']?.toString();
      return ClassRegisterPayloadSnapshot(
        payload: payload,
        fetchedAt: fetchedAt,
        fingerprint: storedFingerprint?.isNotEmpty == true
            ? storedFingerprint!
            : fingerprintForPayload(payload),
      );
    } catch (_) {
      return null;
    }
  }
}

class ClassRegisterCacheService {
  Future<ClassRegisterPayloadSnapshot?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return ClassRegisterPayloadSnapshot.tryParse(raw);
  }

  Future<void> save(String key, ClassRegisterPayloadSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(snapshot.toJson()));
  }
}

final ClassRegisterCacheService classRegisterCacheService =
    ClassRegisterCacheService();

String fingerprintForPayload(List<Map<String, dynamic>> payload) {
  return json.encode(_normalizeJson(payload));
}

List<Map<String, dynamic>> _normalizePayload(
    List<Map<String, dynamic>> payload) {
  final normalized = _normalizeJson(payload);
  if (normalized is! List) {
    return const <Map<String, dynamic>>[];
  }
  return normalized
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
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
