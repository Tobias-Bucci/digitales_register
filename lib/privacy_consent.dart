import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const currentPrivacyNoticeVersion = 3;
const privacyDecisionKey = 'privacyDecision';

enum TelemetryConsentState { unknown, requiredOnly, allAllowed }

class PrivacyDecision {
  const PrivacyDecision({
    this.version = 0,
    this.state = TelemetryConsentState.unknown,
    this.completed = false,
    this.timestamp,
    this.reportsPurged = false,
  });

  final int version;
  final TelemetryConsentState state;
  final bool completed;
  final DateTime? timestamp;
  final bool reportsPurged;
  bool get isCurrent =>
      completed &&
      version == currentPrivacyNoticeVersion &&
      state != TelemetryConsentState.unknown;
  bool get allowsTelemetry =>
      isCurrent && state == TelemetryConsentState.allAllowed;

  String serialize() => jsonEncode({
        'privacyNoticeVersionAccepted': version,
        'telemetryConsentState': state.name,
        'consentDecisionTimestamp': timestamp?.toUtc().toIso8601String(),
        'completed': completed,
        'reportsPurged': reportsPurged,
      });

  factory PrivacyDecision.deserialize(String? raw) {
    try {
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      return PrivacyDecision(
        version: data['privacyNoticeVersionAccepted'] as int,
        state: TelemetryConsentState.values
            .byName(data['telemetryConsentState'] as String),
        completed: data['completed'] == true,
        timestamp: DateTime.tryParse(
            data['consentDecisionTimestamp'] as String? ?? ''),
        reportsPurged: data['reportsPurged'] == true,
      );
    } catch (_) {
      return const PrivacyDecision();
    }
  }
}

abstract class PrivacyStore {
  Future<PrivacyDecision> read();
  Future<bool> installationExisted();
  Future<void> write(PrivacyDecision decision);
}

class PreferencesPrivacyStore implements PrivacyStore {
  @override
  Future<PrivacyDecision> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return PrivacyDecision.deserialize(prefs.getString(privacyDecisionKey));
  }

  @override
  Future<bool> installationExisted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final previousDecision =
        PrivacyDecision.deserialize(prefs.getString(privacyDecisionKey));
    if (previousDecision.version > 0 &&
        previousDecision.version != currentPrivacyNoticeVersion) {
      return true;
    }
    const marker = 'privacyInstallationHistory';
    final previous = prefs.getBool(marker);
    if (previous != null) return previous;
    // Called before startup writes settings. Only key existence is inspected.
    // Keep the migration classification across an interrupted first decision.
    final existed = prefs.getKeys().isNotEmpty;
    if (!await prefs.setBool(marker, existed)) {
      throw StateError('Installation history could not be saved');
    }
    return existed;
  }

  @override
  Future<void> write(PrivacyDecision decision) async {
    final prefs = await SharedPreferences.getInstance();
    // One atomic preferences entry avoids partially accepted notices.
    if (!await prefs.setString(privacyDecisionKey, decision.serialize())) {
      throw StateError('Privacy preference could not be saved');
    }
    await prefs.remove('privacy_consent_choice_v2');
    await prefs.remove('consent_given');
  }
}

abstract class TelemetryCollection {
  bool get available => true;
  Future<void> crashCollection(bool enabled);
  Future<void> analyticsCollection(bool enabled);
  Future<void> deleteReports();
}

class PrivacyController {
  PrivacyController(
      {required this.store, required this.collection, required this.gate});
  final PrivacyStore store;
  final TelemetryCollection collection;
  final void Function(bool) gate;
  PrivacyDecision decision = const PrivacyDecision();
  bool existingInstallation = false;
  bool busy = false;
  bool sdkReady = false;

  Future<bool> _stop() async {
    var success = true;
    // Each SDK is disabled even when another SDK fails.
    try {
      await collection.analyticsCollection(false);
    } catch (_) {
      success = false;
    }
    try {
      await collection.crashCollection(false);
    } catch (_) {
      success = false;
    }
    return success;
  }

  Future<void> initialize() async {
    gate(false);
    sdkReady = false;
    try {
      existingInstallation = await store.installationExisted();
      decision = await store.read();
    } catch (_) {
      decision = const PrivacyDecision();
    }
    try {
      final stopped = await _stop();
      if (!stopped) return;
      if (!decision.allowsTelemetry) {
        await collection.deleteReports();
      } else {
        if (!decision.reportsPurged) {
          await collection.deleteReports();
          decision = PrivacyDecision(
              version: decision.version,
              state: decision.state,
              completed: decision.completed,
              timestamp: decision.timestamp,
              reportsPurged: true);
          await store.write(decision);
        }
        await collection.crashCollection(true);
        await collection.analyticsCollection(true);
        sdkReady = collection.available;
        gate(sdkReady);
      }
    } catch (_) {
      gate(false);
      await _stop();
    }
  }

  Future<void> choose(TelemetryConsentState state) async {
    if (state == TelemetryConsentState.unknown || busy) return;
    if (state == TelemetryConsentState.allAllowed &&
        decision.allowsTelemetry &&
        sdkReady) {
      return;
    }
    busy = true;
    gate(false); // Synchronous revocation before any awaited work.
    sdkReady = false;
    var purged = false;
    try {
      try {
        final stopped = await _stop();
        await collection.deleteReports();
        purged = stopped;
      } catch (_) {
        // Preference remains authoritative. Never enable if purge failed.
      }
      final next = PrivacyDecision(
          version: currentPrivacyNoticeVersion,
          state: state,
          completed: true,
          timestamp: DateTime.now().toUtc(),
          reportsPurged: purged);
      await store.write(next);
      decision = next;
      if (next.allowsTelemetry && purged) {
        try {
          await collection.crashCollection(true);
          await collection.analyticsCollection(true);
          sdkReady = collection.available;
          gate(sdkReady);
        } catch (_) {
          gate(false);
          try {
            await collection.analyticsCollection(false);
          } catch (_) {}
          try {
            await collection.crashCollection(false);
          } catch (_) {}
        }
      }
    } finally {
      busy = false;
    }
  }
}

class LaunchVersionContext {
  const LaunchVersionContext(this.firstLaunch, this.upgrade, this.previous);
  final bool firstLaunch;
  final bool upgrade;
  final String previous;
  factory LaunchVersionContext.resolve(String? previous, String current,
          {required bool existing}) =>
      LaunchVersionContext(
          !existing && previous == null,
          previous != null && previous != current,
          previous ?? (existing ? 'unknown' : 'none'));
}
