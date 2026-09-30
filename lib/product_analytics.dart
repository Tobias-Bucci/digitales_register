import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dr/analytics_schema.dart';
import 'package:dr/analytics_school_ids.dart';
import 'package:dr/desktop.dart';
import 'package:dr/privacy_consent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class AnalyticsSink {
  Future<void> event(String name, Map<String, Object> parameters);
  Future<void> screen(String name);
  Future<void> userId(String? id);
  Future<void> property(String name, String? value);
  Future<void> reset();
}

abstract class AnalyticsLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Local provenance only. A late response from another account cannot authorize
/// an academic contribution, even if the legacy reducer accepts that response.
class AcademicDataOwnership {
  final Map<String, String> _owners = {};
  void mark(String semester, String localOwner) {
    if ({'1', '2'}.contains(semester)) _owners[semester] = localOwner;
  }

  void clear() => _owners.clear();
  void invalidate(String semester) => _owners.remove(semester);
  bool matches(String localOwner, Iterable<String> semesters) =>
      semesters.isNotEmpty &&
      semesters.every((semester) => _owners[semester] == localOwner);
}

class SecureAnalyticsStore implements AnalyticsLocalStore {
  late final FlutterSecureStorage storage = getFlutterSecureStorage();
  Future<String> _scopedKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    var scope = prefs.getString('analyticsInstallationNamespaceV4');
    if (scope == null) {
      scope = ProductAnalytics.newUuid();
      if (!await prefs.setString('analyticsInstallationNamespaceV4', scope)) {
        throw StateError('Analytics local namespace could not be saved');
      }
    }
    // Keychain entries can survive uninstall. A preferences-backed namespace
    // prevents a fresh installation without restored preferences reusing them.
    return '$scope:$key';
  }

  @override
  Future<String?> read(String key) async =>
      storage.read(key: await _scopedKey(key));
  @override
  Future<void> write(String key, String value) async =>
      storage.write(key: await _scopedKey(key), value: value);
}

/// The only application event boundary. Invalid input is rejected, not truncated.
/// Queued work is fenced by an epoch, so revocation/switch invalidates old work.
class ProductAnalytics {
  ProductAnalytics(
      {required this.sink, required this.store, required this.decision});
  final AnalyticsSink sink;
  final AnalyticsLocalStore store;
  final PrivacyDecision Function() decision;
  final gradeOwnership = AcademicDataOwnership();
  bool _enabled = false;
  bool _accountOpen = false;
  bool _demo = false;
  String? _identity;
  String? _school;
  String? _desiredSchool;
  String? _accountKey;
  String? _lastScreen;
  final Map<String, String?> _properties = {};
  final Map<String, String> _snapshots = {};
  final Map<String, DateTime> _lastEvents = {};
  int _epoch = 0;
  Future<void> _tail = Future.value();
  bool get enabled => _enabled && decision().analyticsAllowed;
  bool get identityReady => enabled && _accountOpen && _identity != null;
  String get identitySource => 'installation_uuid'; // Local only.
  int get sessionEpoch => _epoch;
  bool isSession(int epoch) => enabled && epoch == _epoch;
  void gate(bool allowed) {
    _enabled = allowed;
    _epoch++;
    _lastScreen = null;
    _lastEvents.clear();
    if (!allowed) {
      _identity = null;
      _school = null;
      _properties.clear();
      _snapshots.clear();
    }
  }

  Future<void> _serialize(Future<void> Function() work) {
    final next = _tail.then((_) => work()).catchError((Object _) {});
    _tail = next;
    return next;
  }

  Future<void> _accepted(Future<void> Function() work) {
    if (!enabled) return Future.value();
    final epoch = _epoch;
    return _serialize(() async {
      if (epoch == _epoch && enabled) await work();
    });
  }

  Future<void> flush() => _tail;
  Future<void> clearTelemetry({bool reset = true}) => _serialize(() async {
        try {
          await sink.userId(null);
        } catch (_) {}
        for (final name in AnalyticsSchema.propertyNames) {
          try {
            await sink.property(name, null);
          } catch (_) {}
        }
        if (reset) {
          try {
            await sink.reset();
          } catch (_) {}
        }
      });
  Future<void> applyPrivacyState() async {
    if (!enabled) return;
    if (_accountOpen && _accountKey != null) {
      await identifyUser(_accountKey!, demo: _demo, schoolId: _desiredSchool);
    }
  }

  static String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // localAccountKey is never passed to the sink, log output or event schemas.
  // It is used solely inside encrypted local storage to separate saved accounts.
  Future<void> identifyUser(String localAccountKey,
      {required bool demo, String? schoolId}) {
    final selectedSchool =
        !demo && analyticsSchoolIds.containsValue(schoolId) ? schoolId : null;
    if (_accountKey != null &&
        (_accountKey != localAccountKey ||
            _demo != demo ||
            _desiredSchool != selectedSchool)) {
      // clearIdentity closes the account gate synchronously and queues SDK clear.
      unawaited(clearIdentity());
    }
    _accountOpen = true;
    _accountKey = localAccountKey;
    _demo = demo;
    _school = selectedSchool;
    _desiredSchool = _school;
    if (!enabled) return Future.value();
    final epoch = _epoch;
    return _accepted(() async {
      if (_identity == null) {
        final raw = await store.read('analyticsIdentityMapV4');
        final map = raw == null
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>;
        var id = map[localAccountKey] as String?;
        if (id == null ||
            !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
                .hasMatch(id)) {
          id = newUuid();
          map[localAccountKey] = id;
          await store.write('analyticsIdentityMapV4', jsonEncode(map));
        }
        if (epoch != _epoch || !enabled || !_accountOpen) return;
        await sink.userId(id);
        if (epoch != _epoch || !enabled) return;
        _identity = id;
      }
      if (epoch != _epoch || !enabled) return;
      await _setProperty('school_id', _school);
      if (epoch != _epoch || !enabled) return;
      await _setProperty(
          'school_api_type', demo ? 'demo' : 'digital_register_api');
      if (epoch != _epoch || !enabled) return;
      await _setProperty('demo_mode', demo.toString());
    });
  }

  Future<void> clearIdentity() {
    _epoch++;
    gradeOwnership.clear();
    _lastScreen = null;
    _lastEvents.clear();
    _accountOpen = false;
    _accountKey = null;
    _identity = null;
    _school = null;
    _desiredSchool = null;
    _snapshots.clear();
    for (final key in [
      'school_id',
      'school_api_type',
      'academic_year',
      'demo_mode',
      'notifications_enabled'
    ]) {
      _properties.remove(key);
    }
    if (!enabled) return Future.value();
    return _serialize(() async {
      try {
        await sink.userId(null);
      } catch (_) {}
      for (final key in [
        'school_id',
        'school_api_type',
        'academic_year',
        'demo_mode',
        'notifications_enabled'
      ]) {
        try {
          await sink.property(key, null);
        } catch (_) {}
      }
    });
  }

  Future<void> _setProperty(String key, String? value) async {
    if (!enabled || !AnalyticsSchema.validProperty(key, value)) return;
    if (_properties.containsKey(key) && _properties[key] == value) return;
    final epoch = _epoch;
    await sink.property(key, value);
    if (epoch == _epoch && enabled) _properties[key] = value;
  }

  Future<void> updateUserProperties(Map<String, String?> values) =>
      _accepted(() async {
        final epoch = _epoch;
        for (final entry in values.entries) {
          if (epoch != _epoch || !enabled) return;
          if (entry.key == 'school_id' &&
              entry.value != null &&
              !analyticsSchoolIds.containsValue(entry.value)) {
            continue;
          }
          await _setProperty(entry.key, entry.value);
        }
      });
  Future<void> screenView(String name) {
    if (!enabled ||
        !AnalyticsSchema.features.contains(name) ||
        name == _lastScreen) {
      return Future.value();
    }
    _lastScreen = name;
    return _accepted(() => sink.screen(name));
  }

  Future<void> event(String name, [Map<String, Object> parameters = const {}]) {
    if (!enabled || !AnalyticsSchema.valid(name, parameters)) {
      return Future.value();
    }
    final now = DateTime.now();
    const frequent = {
      'refresh_requested',
      'refresh_result',
      'cache_result',
      'data_source_used',
      'sync_started',
      'sync_completed',
      'calendar_sync_result'
    };
    final interval = frequent.contains(name)
        ? const Duration(seconds: 5)
        : const Duration(milliseconds: 500);
    final key = '$name:${jsonEncode(parameters)}';
    final previous = _lastEvents[key];
    if (previous != null && now.difference(previous) < interval) {
      return Future.value();
    }
    _lastEvents[key] = now;
    if (_lastEvents.length > 128) _lastEvents.remove(_lastEvents.keys.first);
    final safe = Map<String, Object>.unmodifiable(parameters);
    return _accepted(() => sink.event(name, safe));
  }

  Future<void> logAcademicSummary(Map<String, Object> summary) {
    if (!identityReady ||
        _demo ||
        !decision().academicStatsAllowed ||
        _school == null ||
        _properties['school_id'] != _school ||
        !validSummary(summary)) {
      return Future.value();
    }
    final safe = Map<String, Object>.unmodifiable(summary);
    final epoch = _epoch;
    return _accepted(() async {
      if (epoch != _epoch ||
          !identityReady ||
          _demo ||
          !decision().academicStatsAllowed) {
        return;
      }
      final key =
          '$_identity:$_school:${safe['academic_year']}:${safe['semester']}';
      // Canonical normalized values only. Stored locally; never transmitted.
      final fingerprint = jsonEncode([for (final k in summaryKeys) safe[k]]);
      final storageKey = 'analyticsSnapshotV4:$key';
      final previous = _snapshots[key] ?? await store.read(storageKey);
      if (previous == fingerprint ||
          epoch != _epoch ||
          !decision().academicStatsAllowed) {
        return;
      }
      await sink.event('academic_summary_updated', safe);
      if (epoch != _epoch || !enabled) return;
      await store.write(storageKey, fingerprint);
      _snapshots[key] = fingerprint;
    });
  }

  static const summaryKeys = [
    'academic_year',
    'semester',
    'grade_average_tenths',
    'grade_count_bucket',
    'subject_count_bucket',
    'snapshot_schema_version'
  ];
  static bool validSummary(Map<String, Object> s) =>
      s.length == summaryKeys.length &&
      s.keys.every(summaryKeys.contains) &&
      AnalyticsSchema.year(s['academic_year']) &&
      {'1', '2', 'year'}.contains(s['semester']) &&
      s['grade_average_tenths'] is int &&
      (s['grade_average_tenths']! as int) >= 0 &&
      (s['grade_average_tenths']! as int) <= 100 &&
      {'1_5', '6_10', '11_20', '21_40', '41_plus'}
          .contains(s['grade_count_bucket']) &&
      {'1_5', '6_10', '11_plus'}.contains(s['subject_count_bucket']) &&
      s['snapshot_schema_version'] is int &&
      s['snapshot_schema_version'] == 1;
  Future<void> developerTestProductAnalytics() async {
    if (!kDebugMode || !enabled) return;
    await screenView('analytics_test');
    await event(
        'feature_opened', {'feature': 'analytics_test', 'source': 'unknown'});
    await event('refresh_result', {
      'feature': 'analytics_test',
      'result': 'success',
      'data_source': 'local',
      'duration_bucket': 'under_250ms'
    });
  }

  Future<void> developerTestAcademicAnalytics() async {
    if (!kDebugMode ||
        !identityReady ||
        _demo ||
        !decision().academicStatsAllowed) {
      return;
    }
    // The impossible future year distinguishes this synthetic contribution.
    await logAcademicSummary({
      'academic_year': '2099_2100',
      'semester': '1',
      'grade_average_tenths': 81,
      'grade_count_bucket': '11_20',
      'subject_count_bucket': '6_10',
      'snapshot_schema_version': 1
    });
  }
}
