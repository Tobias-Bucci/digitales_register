import 'dart:async';
import 'package:dr/analytics_schema.dart';
import 'package:dr/analytics_school_ids.dart';
import 'package:dr/config.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/product_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'privacy_consent_test.dart' show MemoryStore, FakeCollection;

class MemoryAnalyticsStore implements AnalyticsLocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class RecordingSink implements AnalyticsSink {
  final calls = <String>[];
  final events = <Map<String, Object>>[];
  final ids = <String?>[];
  bool failEvent = false;
  Completer<void>? blockingEvent;
  @override
  Future<void> event(String name, Map<String, Object> values) async {
    if (failEvent) throw StateError('synthetic');
    calls.add(name);
    events.add(values);
    await blockingEvent?.future;
  }

  @override
  Future<void> screen(String name) async {
    calls.add('screen:$name');
  }

  @override
  Future<void> userId(String? id) async {
    calls.add('id:$id');
    ids.add(id);
  }

  @override
  Future<void> property(String key, String? value) async {
    calls.add('$key:$value');
  }

  @override
  Future<void> reset() async {
    calls.add('reset');
  }
}

PrivacyDecision consent(
        {bool usage = true,
        bool academic = true,
        bool diagnostics = false,
        AnalyticsAgeEligibility age = AnalyticsAgeEligibility.atLeast14,
        int version = 4}) =>
    PrivacyDecision(
        version: version,
        completed: true,
        ageEligibility: age,
        usageAnalyticsConsent:
            usage ? ConsentChoice.granted : ConsentChoice.denied,
        academicStatisticsConsent:
            academic ? ConsentChoice.granted : ConsentChoice.denied,
        diagnosticsConsent:
            diagnostics ? ConsentChoice.granted : ConsentChoice.denied);
final summary = <String, Object>{
  'academic_year': '2026_2027',
  'semester': '1',
  'grade_average_tenths': 81,
  'grade_count_bucket': '11_20',
  'subject_count_bucket': '6_10',
  'snapshot_schema_version': 1
};
void main() {
  late RecordingSink sink;
  late MemoryAnalyticsStore store;
  late PrivacyDecision decision;
  late ProductAnalytics service;
  setUp(() {
    sink = RecordingSink();
    store = MemoryAnalyticsStore();
    decision = consent();
    service =
        ProductAnalytics(sink: sink, store: store, decision: () => decision);
    service.gate(true);
  });
  test('every catalog entry has a unique immutable explicit reservation', () {
    expect(analyticsSchoolIds.keys.toSet(), schools.keys.toSet());
    expect(analyticsSchoolIds.values.toSet().length, schools.length);
    for (final entry in analyticsSchoolIds.entries) {
      expect(entry.value, matches(r'^school_[0-9]{4}$'));
      expect(entry.key, isNot(entry.value));
    }
    expect(analyticsSchoolIdForUrl('https://unknown.invalid'), isNull);
    final duplicate = schools.values
        .firstWhere((url) => schools.values.where((v) => v == url).length > 1);
    expect(analyticsSchoolIdForUrl(duplicate), isNull);
  });
  test('old consent and under14 cannot authorize any purpose', () async {
    for (final age in AnalyticsAgeEligibility.values) {
      decision = consent(age: age, version: 3);
      await service.event('account_switch');
      expect(sink.calls, isEmpty);
    }
    decision = consent(age: AnalyticsAgeEligibility.under14, diagnostics: true);
    expect(decision.diagnosticsAllowed, false);
    expect(decision.analyticsAllowed, false);
    expect(decision.academicStatsAllowed, false);
    await service.event('account_switch');
    expect(sink.calls, isEmpty);
  });
  test(
      'diagnostics and usage choices are independent; academic depends on usage',
      () {
    decision = consent(usage: false, diagnostics: true);
    expect(decision.diagnosticsAllowed, true);
    expect(decision.analyticsAllowed, false);
    expect(decision.academicStatsAllowed, false);
    decision = consent(academic: false);
    expect(decision.analyticsAllowed, true);
    expect(decision.diagnosticsAllowed, false);
    expect(decision.academicStatsAllowed, false);
  });
  test('unknown event, keys, school names and free text fail closed', () async {
    await service.event('grade_received', {'grade': 8});
    await service
        .event('feature_opened', {'feature': 'math', 'source': 'navigation'});
    await service.event('feature_opened',
        {'feature': 'grades', 'source': 'navigation', 'username': 'someone'});
    await service.updateUserProperties(
        {'school_id': schools.keys.first, 'teacher': 'someone', 'age': '14'});
    await service.screenView('grades?student=123');
    expect(sink.calls, isEmpty);
    await service
        .event('feature_opened', {'feature': 'grades', 'source': 'navigation'});
    expect(sink.calls, ['feature_opened']);
  });
  test('installation identity is random UUIDv4 and stable for a local account',
      () async {
    await service.identifyUser('local A', demo: false, schoolId: 'school_0001');
    final id = sink.ids.last;
    expect(
        id,
        matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'));
    await service.clearIdentity();
    await service.identifyUser('local A', demo: false, schoolId: 'school_0001');
    expect(sink.ids.last, id);
    expect(sink.calls.any((call) => call.contains('local A')), false);
  });
  test('switch clears old identity before identifying B', () async {
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    final a = sink.ids.last;
    sink.calls.clear();
    await service.identifyUser('B', demo: false, schoolId: 'school_0002');
    expect(sink.calls.first, 'id:null');
    expect(sink.ids.last, isNot(a));
    expect(sink.calls.indexOf('school_id:null'),
        lessThan(sink.calls.indexOf('id:${sink.ids.last}')));
  });
  test('revocation discards queued work and clears every custom property',
      () async {
    sink.blockingEvent = Completer<void>();
    final first = service.event('account_switch');
    await Future<void>.delayed(Duration.zero);
    final second = service
        .event('feature_opened', {'feature': 'grades', 'source': 'navigation'});
    service.gate(false);
    decision = consent(usage: false);
    final clear = service.clearTelemetry();
    sink.blockingEvent!.complete();
    await Future.wait([first, second, clear]);
    expect(sink.calls.contains('feature_opened'), false);
    expect(sink.calls.contains('id:null'), true);
    expect(sink.calls.last, 'reset');
    for (final key in AnalyticsSchema.propertyNames) {
      expect(sink.calls.contains('$key:null'), true);
    }
    await service.event('account_switch');
    expect(sink.calls.last, 'reset');
  });
  test(
      'academic requires identity, school, usage, academic choice and non-demo',
      () async {
    await service.logAcademicSummary(summary);
    expect(sink.events, isEmpty);
    await service.identifyUser('A', demo: true, schoolId: 'school_0001');
    await service.logAcademicSummary(summary);
    expect(sink.events, isEmpty);
    expect(sink.calls.contains('school_id:school_0001'), false);
    await service.clearIdentity();
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    decision = consent(academic: false);
    await service.logAcademicSummary(summary);
    expect(sink.events, isEmpty);
    decision = consent();
    await service.logAcademicSummary(summary);
    expect(sink.events, [summary]);
  });
  test('academic deduplicates changed normalized summaries across restart',
      () async {
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    await service.logAcademicSummary(summary);
    await service.logAcademicSummary(summary);
    expect(sink.events.length, 1);
    service =
        ProductAnalytics(sink: sink, store: store, decision: () => decision);
    service.gate(true);
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    await service.logAcademicSummary(summary);
    expect(sink.events.length, 1);
    await service.logAcademicSummary({...summary, 'grade_average_tenths': 82});
    expect(sink.events.length, 2);
    expect(sink.events.every((e) => !e.containsKey('fingerprint')), true);
  });
  test(
      'failed submission remains eligible for retry; invalid precision rejected',
      () async {
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    sink.failEvent = true;
    await service.logAcademicSummary(summary);
    sink.failEvent = false;
    await service.logAcademicSummary(summary);
    expect(sink.events.length, 1);
    for (final value in [-1, 101, 81.123]) {
      await service
          .logAcademicSummary({...summary, 'grade_average_tenths': value});
    }
    await service.logAcademicSummary({...summary, 'subject': 'mathematics'});
    expect(sink.events.length, 1);
  });
  test('screen dedup and synthetic helpers respect consent', () async {
    await service.screenView('grades');
    await service.screenView('grades');
    expect(sink.calls, ['screen:grades']);
    await service.identifyUser('A', demo: false, schoolId: 'school_0001');
    await service.developerTestAcademicAnalytics();
    expect(sink.events.last['academic_year'], '2099_2100');
    decision = consent(usage: false);
    final count = sink.calls.length;
    await service.developerTestProductAnalytics();
    expect(sink.calls.length, count);
  });
  test('bucket and academic-year schemas reject invalid values', () {
    expect(AnalyticsSchema.gradeCount(0), '0');
    expect(AnalyticsSchema.gradeCount(5), '1_5');
    expect(AnalyticsSchema.gradeCount(6), '6_10');
    expect(AnalyticsSchema.gradeCount(41), '41_plus');
    expect(AnalyticsSchema.subjectCount(11), '11_plus');
    expect(AnalyticsSchema.year('2026_2028'), false);
    expect(AnalyticsSchema.year('2026_2027'), true);
  });
  test('granular controller enables each SDK independently and denies under14',
      () async {
    for (final diagnostics in [false, true]) {
      for (final usage in [false, true]) {
        final calls = <String>[];
        final store = MemoryStore(calls);
        final sdk = FakeCollection(calls);
        final gates = <bool>[];
        final productGates = <bool>[];
        final controller = PrivacyController(
            store: store,
            collection: sdk,
            gate: gates.add,
            analyticsGate: productGates.add);
        await controller.chooseGranular(
            diagnostics:
                diagnostics ? ConsentChoice.granted : ConsentChoice.denied,
            usage: usage ? ConsentChoice.granted : ConsentChoice.denied,
            academic: ConsentChoice.granted,
            age: AnalyticsAgeEligibility.atLeast14);
        expect(calls.contains('crash:true'), diagnostics);
        expect(calls.contains('analytics:true'), usage);
        expect(controller.decision.academicStatsAllowed, usage);
        expect(gates.last, diagnostics);
        expect(productGates.last, usage);
        await controller.chooseGranular(
            diagnostics: ConsentChoice.granted,
            usage: ConsentChoice.granted,
            academic: ConsentChoice.granted,
            age: AnalyticsAgeEligibility.under14);
        expect(controller.decision.requiredOnly, true);
        expect(gates.last, false);
        expect(productGates.last, false);
      }
    }
  });
  test(
      'v3 required-only and full consent require v4; simulated later notice returns',
      () async {
    for (final raw in ['requiredOnly', 'allAllowed']) {
      final decision = PrivacyDecision.deserialize(
          '{"privacyNoticeVersionAccepted":3,"telemetryConsentState":"$raw","completed":true}');
      expect(decision.isCurrent, false);
      expect(decision.analyticsAllowed, false);
      expect(decision.diagnosticsAllowed, false);
    }
    expect(consent().isCurrent, true);
    expect(consent(version: currentPrivacyNoticeVersion + 1).isCurrent, false);
    expect(
        PrivacyDecision.deserialize(consent().serialize()).academicStatsAllowed,
        true);
    expect(consent().serialize().contains('birth'), false);
  });
  test('academic provenance rejects late foreign-account semester data',
      () async {
    final ownership = service.gradeOwnership;
    ownership.mark('1', 'A');
    ownership.mark('2', 'A');
    expect(ownership.matches('A', ['1', '2']), true);
    ownership.mark('2', 'B');
    expect(ownership.matches('A', ['1', '2']), false);
    expect(ownership.matches('A', ['1']), true);
    ownership.invalidate('1');
    expect(ownership.matches('A', ['1']), false);
    ownership.mark('1', 'A');
    await service.clearIdentity();
    expect(ownership.matches('A', ['1']), false);
  });
  test('No revokes immediately; age confirmation alone never grants purposes',
      () async {
    final calls = <String>[];
    final store = MemoryStore(calls);
    final sdk = FakeCollection(calls);
    final gates = <bool>[];
    final controller = PrivacyController(
        store: store, collection: sdk, gate: (_) {}, analyticsGate: gates.add);
    await controller.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
        age: AnalyticsAgeEligibility.atLeast14);
    expect(gates.last, true);
    final denied =
        controller.resolveAgeEligibility(AnalyticsAgeEligibility.under14);
    expect(gates.last, false);
    await denied;
    expect(controller.decision.ageEligibility, AnalyticsAgeEligibility.under14);
    await controller.resolveAgeEligibility(AnalyticsAgeEligibility.atLeast14);
    expect(controller.decision.requiredOnly, true);
    final fresh = PrivacyController(
        store: MemoryStore([]), collection: FakeCollection([]), gate: (_) {});
    await fresh.resolveAgeEligibility(AnalyticsAgeEligibility.atLeast14);
    expect(fresh.decision.isCurrent, false);
    expect(fresh.decision.requiredOnly, true);
  });
}
