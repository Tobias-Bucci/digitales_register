import 'package:dr/analytics_service.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/telemetry_capabilities.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unsupported production platforms and web have no capabilities', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia
    ]) {
      expect(TelemetryCapabilities(platform).supportsAnalytics, false);
      expect(TelemetryCapabilities(platform).supportsCrashlytics, false);
    }
    expect(
        const TelemetryCapabilities(TargetPlatform.android, web: true)
            .supportsAnalytics,
        false);
  });
  test('Windows adapters never initialize Firebase or invoke plugins',
      () async {
    // UI platform overrides do not change dart:io's host OS. Inject the
    // production policy into both adapters to test Windows on any runner.
    const windows = TelemetryCapabilities(TargetPlatform.windows);
    final sdk = MockAnalytics();
    var initializationCalls = 0;
    final collection = FirebaseTelemetryCollection(
        analytics: sdk,
        capabilities: windows,
        initialize: () async {
          initializationCalls++;
        });
    await collection.analyticsCollection(true);
    await collection.analyticsCollection(false);
    await collection.crashCollection(true);
    await collection.crashCollection(false);
    await collection.deleteReports();
    await collection.resetAnalytics();
    final sink = FirebaseDiagnosticSink(capabilities: windows);
    await sink.key('logged_in', true);
    await sink.log('app_initialized');
    await sink.error('E01_flutterFatal', StackTrace.empty, true);
    expect(collection.available, false);
    expect(initializationCalls, 0);
    verifyZeroInteractions(sdk);
  });
  test('consent precedes enabling collection and all advertising stays denied',
      () async {
    final sdk = MockAnalytics();
    final calls = <String>[];
    when(() => sdk.setConsent(
        analyticsStorageConsentGranted: true,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false)).thenAnswer((_) async {
      calls.add('consent');
    });
    when(() => sdk.setAnalyticsCollectionEnabled(true)).thenAnswer((_) async {
      calls.add('enabled');
    });
    final collection = FirebaseTelemetryCollection(
        analytics: sdk,
        initialize: () async {
          calls.add('initialize');
        },
        capabilities: const TelemetryCapabilities(TargetPlatform.android));
    await collection.analyticsCollection(true);
    expect(calls, ['initialize', 'consent', 'enabled']);
  });
  test('unsupported initialization is attempted only once and never enables',
      () async {
    final sdk = MockAnalytics();
    var attempts = 0;
    final collection = FirebaseTelemetryCollection(
        analytics: sdk,
        initialize: () async {
          attempts++;
          throw MissingPluginException();
        },
        capabilities: const TelemetryCapabilities(TargetPlatform.iOS));
    for (var i = 0; i < 3; i++) {
      await expectLater(collection.analyticsCollection(true),
          throwsA(isA<MissingPluginException>()));
    }
    expect(attempts, 1);
    verifyZeroInteractions(sdk);
  });
  for (final bootstrapFailure in [
    'not ready',
    'missing channel',
    'native error'
  ]) {
    test('iOS $bootstrapFailure leaves startup and opt-in safe', () async {
      SharedPreferences.setMockInitialValues({});
      const bridge = MethodChannel('dr/privacy_bootstrap');
      var readinessChecks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
        expect(call.method, 'ready');
        readinessChecks++;
        if (bootstrapFailure == 'missing channel') {
          throw MissingPluginException();
        }
        if (bootstrapFailure == 'native error') {
          throw PlatformException(code: 'bootstrap_failed');
        }
        return false;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(bridge, null);
      });
      final sdk = MockAnalytics();
      final collection = FirebaseTelemetryCollection(
          analytics: sdk,
          capabilities: const TelemetryCapabilities(TargetPlatform.iOS));
      var diagnosticsEnabled = false;
      var analyticsEnabled = false;
      final privacy = PrivacyController(
          store: PreferencesPrivacyStore(),
          collection: collection,
          gate: (enabled) => diagnosticsEnabled = enabled,
          analyticsGate: (enabled) => analyticsEnabled = enabled);

      // Exercise the real adapter and controller: native bootstrap failure
      // must never escape into the app's awaited startup or consent dialog.
      await privacy.initialize();
      await privacy.chooseGranular(
        diagnostics: ConsentChoice.granted,
        usage: ConsentChoice.granted,
        academic: ConsentChoice.granted,
      );
      await privacy.initialize();

      expect(privacy.sdkReady, false);
      expect(diagnosticsEnabled, false);
      expect(analyticsEnabled, false);
      expect(privacy.busy, false);
      expect(readinessChecks, 1);
      verifyZeroInteractions(sdk);
    });
  }
  test('withdrawal stops collection before denying storage; ads remain denied',
      () async {
    final sdk = MockAnalytics();
    final calls = <String>[];
    when(() => sdk.setAnalyticsCollectionEnabled(false)).thenAnswer((_) async {
      calls.add('disabled');
    });
    when(() => sdk.setConsent(
        analyticsStorageConsentGranted: false,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false)).thenAnswer((_) async {
      calls.add('denied');
    });
    final collection = FirebaseTelemetryCollection(
        analytics: sdk,
        capabilities: const TelemetryCapabilities(TargetPlatform.android),
        initialize: () async {});
    await collection.analyticsCollection(false);
    expect(calls, ['disabled', 'denied']);
  });
}
