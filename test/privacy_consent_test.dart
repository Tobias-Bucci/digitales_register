import 'package:dr/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStore implements PrivacyStore {
  PrivacyDecision value = const PrivacyDecision();
  bool existing = false;
  bool fail = false;
  final List<String> calls;
  MemoryStore(this.calls);
  @override
  Future<PrivacyDecision> read() async => value;
  @override
  Future<bool> installationExisted() async => existing;
  @override
  Future<void> write(PrivacyDecision decision) async {
    calls.add('persist');
    if (fail) throw StateError('test');
    value = decision;
  }
}

class FakeCollection extends TelemetryCollection {
  FakeCollection(this.calls);
  final List<String> calls;
  bool failDelete = false;
  bool failAnalytics = false;
  @override
  Future<void> crashCollection(bool enabled) async {
    calls.add('crash:$enabled');
  }

  @override
  Future<void> analyticsCollection(bool enabled) async {
    calls.add('analytics:$enabled');
    if (failAnalytics) throw StateError('test');
  }

  @override
  Future<void> deleteReports() async {
    calls.add('delete');
    if (failDelete) throw StateError('test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late MemoryStore store;
  late FakeCollection sdk;
  late PrivacyController controller;
  setUp(() {
    calls = [];
    store = MemoryStore(calls);
    sdk = FakeCollection(calls);
    controller = PrivacyController(
        store: store, collection: sdk, gate: (v) => calls.add('gate:$v'));
  });

  test('decision round trip preserves version, choice, timestamp, completion',
      () {
    for (final state in TelemetryConsentState.values) {
      final decision = PrivacyDecision(
          version: currentPrivacyNoticeVersion,
          state: state,
          completed: true,
          timestamp: DateTime.utc(2026),
          reportsPurged: true);
      final result = PrivacyDecision.deserialize(decision.serialize());
      expect(result.state, decision.state);
      expect(result.version, currentPrivacyNoticeVersion);
      expect(result.timestamp, decision.timestamp);
      expect(result.completed, true);
      expect(result.reportsPurged, true);
    }
    expect(PrivacyDecision.deserialize('malformed').isCurrent, false);
    expect(PrivacyDecision.deserialize(null).allowsTelemetry, false);
  });
  test('fresh install pending disables both SDKs and deletes reports',
      () async {
    await controller.initialize();
    expect(controller.existingInstallation, false);
    expect(controller.decision.isCurrent, false);
    expect(calls, ['gate:false', 'analytics:false', 'crash:false', 'delete']);
  });
  test('required only persists after disabling and purging', () async {
    await controller.choose(TelemetryConsentState.requiredOnly);
    expect(calls,
        ['gate:false', 'analytics:false', 'crash:false', 'delete', 'persist']);
    expect(controller.decision.isCurrent, true);
    expect(controller.decision.allowsTelemetry, false);
  });
  test('allow deletes BEFORE persist and enable; revoke stops gate first',
      () async {
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    expect(calls, [
      'gate:false',
      'analytics:false',
      'crash:false',
      'delete',
      'persist',
      'crash:true',
      'analytics:true',
      'gate:true'
    ]);
    calls.clear();
    await controller.choose(TelemetryConsentState.requiredOnly);
    expect(calls.first, 'gate:false');
    expect(calls,
        ['gate:false', 'analytics:false', 'crash:false', 'delete', 'persist']);
    calls.clear();
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    expect(calls.indexOf('delete'), lessThan(calls.indexOf('crash:true')));
  });
  test('existing installation needs update; old notice never enables',
      () async {
    store.existing = true;
    store.value = const PrivacyDecision(
        version: currentPrivacyNoticeVersion - 1,
        state: TelemetryConsentState.allAllowed,
        completed: true);
    await controller.initialize();
    expect(controller.existingInstallation, true);
    expect(controller.decision.isCurrent, false);
    expect(calls.contains('crash:true'), false);
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    expect(controller.decision.version, currentPrivacyNoticeVersion);
  });
  test('restart retains valid allowed reports and required-only decision',
      () async {
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    calls.clear();
    await controller.initialize();
    expect(calls.contains('delete'), false);
    expect(controller.decision.isCurrent, true);
    await controller.choose(TelemetryConsentState.requiredOnly);
    calls.clear();
    await controller.initialize();
    expect(controller.decision.isCurrent, true);
    expect(calls.contains('crash:true'), false);
  });
  test('failed purge cannot enable, including on restart', () async {
    sdk.failDelete = true;
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    expect(store.value.state, TelemetryConsentState.allAllowed);
    expect(controller.sdkReady, false);
    expect(calls.contains('crash:true'), false);
    calls.clear();
    await controller.initialize();
    expect(calls.contains('crash:true'), false);
    sdk.failDelete = false;
    calls.clear();
    await controller.initialize();
    expect(calls.indexOf('delete'), lessThan(calls.indexOf('crash:true')));
  });
  test('analytics failure still disables Crashlytics', () async {
    sdk.failAnalytics = true;
    await controller.choose(TelemetryConsentState.requiredOnly);
    expect(calls.contains('crash:false'), true);
    expect(controller.decision.state, TelemetryConsentState.requiredOnly);
  });
  test('persistence failure never enables and double tap is serialized',
      () async {
    store.fail = true;
    await expectLater(
        controller.chooseGranular(
            diagnostics: ConsentChoice.granted,
            usage: ConsentChoice.granted,
            academic: ConsentChoice.granted,
            age: AnalyticsAgeEligibility.atLeast14),
        throwsStateError);
    expect(calls.contains('crash:true'), false);
    store.fail = false;
    calls.clear();
    final first = controller.choose(TelemetryConsentState.requiredOnly);
    final second = controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    await Future.wait([first, second]);
    expect(controller.decision.state, TelemetryConsentState.requiredOnly);
    expect(calls.where((e) => e == 'persist'), hasLength(1));
  });
  test('legacy v2 and v1 flags require an explicit new decision', () async {
    for (final entry in [
      {'consent_given': true},
      {'privacy_consent_choice_v2': 'v2_all'},
      {'globalSettingsState': '{}'}
    ]) {
      SharedPreferences.setMockInitialValues(entry);
      final preferences = PreferencesPrivacyStore();
      expect(await preferences.installationExisted(), true);
      expect((await preferences.read()).isCurrent, false);
      await preferences.write(PrivacyDecision(
          version: currentPrivacyNoticeVersion,
          state: TelemetryConsentState.requiredOnly,
          completed: true));
      expect((await preferences.read()).isCurrent, true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('privacy_consent_choice_v2'), false);
      expect(prefs.containsKey('consent_given'), false);
    }
    SharedPreferences.setMockInitialValues({});
    expect(await PreferencesPrivacyStore().installationExisted(), false);
  });
  test('first launch versus same version versus upgrade', () {
    final fresh =
        LaunchVersionContext.resolve(null, '1.0.0+1', existing: false);
    expect(fresh.firstLaunch, true);
    expect(fresh.upgrade, false);
    expect(fresh.previous, 'none');
    expect(
        LaunchVersionContext.resolve('1.0.0+1', '1.0.0+1', existing: true)
            .upgrade,
        false);
    final upgraded =
        LaunchVersionContext.resolve('1.0.0+1', '1.0.0+2', existing: true);
    expect(upgraded.upgrade, true);
    expect(upgraded.firstLaunch, false);
    expect(upgraded.previous, '1.0.0+1');
    expect(
        LaunchVersionContext.resolve(null, '1.0.0+2', existing: true)
            .firstLaunch,
        false);
  });
}
