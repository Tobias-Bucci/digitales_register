import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const currentPrivacyNoticeVersion = 4;
const privacyDecisionKey = 'privacyDecision';

enum TelemetryConsentState { unknown, requiredOnly, allAllowed }

enum ConsentChoice { denied, granted }

enum AnalyticsAgeEligibility { unknown, atLeast14, under14 }

class PrivacyDecision {
  const PrivacyDecision({
    this.version = 0,
    TelemetryConsentState state = TelemetryConsentState.unknown,
    this.diagnosticsConsent = ConsentChoice.denied,
    this.usageAnalyticsConsent = ConsentChoice.denied,
    this.academicStatisticsConsent = ConsentChoice.denied,
    this.ageEligibility = AnalyticsAgeEligibility.unknown,
    this.completed = false,
    this.timestamp,
    this.reportsPurged = false,
  }) : _legacyState = state;

  final int version;
  // Legacy choice is retained only for migration/display, never authorization.
  final TelemetryConsentState _legacyState;
  final ConsentChoice diagnosticsConsent;
  final ConsentChoice usageAnalyticsConsent;
  final ConsentChoice academicStatisticsConsent;
  final AnalyticsAgeEligibility ageEligibility;
  TelemetryConsentState get state => !completed
      ? _legacyState
      : allOptionalAllowed
          ? TelemetryConsentState.allAllowed
          : TelemetryConsentState.requiredOnly;
  final bool completed;
  final DateTime? timestamp;
  final bool reportsPurged;
  bool get isCurrent => completed && version == currentPrivacyNoticeVersion;
  bool get eligible =>
      isCurrent && ageEligibility == AnalyticsAgeEligibility.atLeast14;
  bool get diagnosticsAllowed =>
      eligible && diagnosticsConsent == ConsentChoice.granted;
  bool get analyticsAllowed =>
      eligible && usageAnalyticsConsent == ConsentChoice.granted;
  bool get academicStatsAllowed =>
      analyticsAllowed && academicStatisticsConsent == ConsentChoice.granted;
  bool get allOptionalAllowed => diagnosticsAllowed && academicStatsAllowed;
  bool get requiredOnly => !diagnosticsAllowed && !analyticsAllowed;
  bool get allowsTelemetry => allOptionalAllowed;

  String serialize() => jsonEncode({
        'privacyNoticeVersionAccepted': version,
        'telemetryConsentState': state.name,
        'diagnosticsConsent': diagnosticsConsent.name,
        'usageAnalyticsConsent': usageAnalyticsConsent.name,
        'academicStatisticsConsent': academicStatisticsConsent.name,
        'ageEligibility': ageEligibility.name,
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
            .byName(data['telemetryConsentState'] as String? ?? 'unknown'),
        completed: data['completed'] == true,
        timestamp: DateTime.tryParse(
            data['consentDecisionTimestamp'] as String? ?? ''),
        reportsPurged: data['reportsPurged'] == true,
        diagnosticsConsent: ConsentChoice.values
            .byName(data['diagnosticsConsent'] as String? ?? 'denied'),
        usageAnalyticsConsent: ConsentChoice.values
            .byName(data['usageAnalyticsConsent'] as String? ?? 'denied'),
        academicStatisticsConsent: ConsentChoice.values
            .byName(data['academicStatisticsConsent'] as String? ?? 'denied'),
        ageEligibility: AnalyticsAgeEligibility.values
            .byName(data['ageEligibility'] as String? ?? 'unknown'),
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
  Future<void> resetAnalytics() async {}
}

class PrivacyController {
  PrivacyController(
      {required this.store,
      required this.collection,
      required this.gate,
      this.analyticsGate,
      this.onApplied});
  final PrivacyStore store;
  final TelemetryCollection collection;
  final void Function(bool) gate;
  final void Function(bool)? analyticsGate;
  final Future<void> Function(PrivacyDecision)? onApplied;
  PrivacyDecision decision = const PrivacyDecision();
  bool existingInstallation = false;
  bool busy = false;
  bool sdkReady = false;

  void _close() {
    gate(false);
    analyticsGate?.call(false);
    sdkReady = false;
  }

  Future<bool> _stop({bool resetAnalytics = false}) async {
    var success = true;
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
    if (resetAnalytics) {
      try {
        await collection.resetAnalytics();
      } catch (_) {
        success = false;
      }
    }
    return success;
  }

  Future<void> _apply({bool alreadyPurged = false}) async {
    // Purge cached diagnostics before a newly authorized diagnostic session.
    try {
      if (!alreadyPurged &&
          (!decision.diagnosticsAllowed || !decision.reportsPurged)) {
        await collection.deleteReports();
      }
      if (!decision.diagnosticsAllowed && !decision.analyticsAllowed) return;
      if (decision.diagnosticsAllowed) await collection.crashCollection(true);
      if (decision.analyticsAllowed) await collection.analyticsCollection(true);
      sdkReady = collection.available;
      gate(sdkReady && decision.diagnosticsAllowed);
      analyticsGate?.call(sdkReady && decision.analyticsAllowed);
      await onApplied?.call(decision);
    } catch (_) {
      _close();
      await _stop();
    }
  }

  Future<void> initialize() async {
    _close();
    try {
      existingInstallation = await store.installationExisted();
      decision = await store.read();
    } catch (_) {
      decision = const PrivacyDecision();
    }
    if (await _stop(resetAnalytics: !decision.analyticsAllowed)) await _apply();
  }

  Future<void> choose(
          TelemetryConsentState state) =>
      state == TelemetryConsentState.unknown
          ? Future.value()
          : chooseGranular(
              diagnostics: state == TelemetryConsentState.allAllowed
                  ? ConsentChoice.granted
                  : ConsentChoice.denied,
              usage: state == TelemetryConsentState.allAllowed
                  ? ConsentChoice.granted
                  : ConsentChoice.denied,
              academic: state == TelemetryConsentState.allAllowed
                  ? ConsentChoice.granted
                  : ConsentChoice.denied,
              age: decision.ageEligibility);

  // Confirming eligibility stores only the local age decision and revokes any
  // prior optional choices. A pending notice stays pending until purpose Save.
  Future<void> resolveAgeEligibility(AnalyticsAgeEligibility age) =>
      chooseGranular(
          diagnostics: ConsentChoice.denied,
          usage: ConsentChoice.denied,
          academic: ConsentChoice.denied,
          age: age,
          complete: decision.isCurrent);

  Future<void> chooseGranular(
      {required ConsentChoice diagnostics,
      required ConsentChoice usage,
      required ConsentChoice academic,
      required AnalyticsAgeEligibility age,
      bool complete = true}) async {
    if (busy) return;
    busy = true;
    _close(); // Synchronous closure before SDK or preference awaits.
    try {
      final nextAllowsAnalytics = age == AnalyticsAgeEligibility.atLeast14 &&
          usage == ConsentChoice.granted;
      final stopped = await _stop(
          resetAnalytics: decision.analyticsAllowed && !nextAllowsAnalytics);
      var purged = false;
      try {
        await collection.deleteReports();
        purged = stopped;
      } catch (_) {}
      final eligible = age == AnalyticsAgeEligibility.atLeast14;
      final next = PrivacyDecision(
          version: currentPrivacyNoticeVersion,
          diagnosticsConsent: eligible ? diagnostics : ConsentChoice.denied,
          usageAnalyticsConsent: eligible ? usage : ConsentChoice.denied,
          academicStatisticsConsent: eligible && usage == ConsentChoice.granted
              ? academic
              : ConsentChoice.denied,
          ageEligibility: age,
          completed: complete,
          timestamp: DateTime.now().toUtc(),
          reportsPurged: purged);
      await store.write(next);
      decision = next;
      if (purged) await _apply(alreadyPurged: true);
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
