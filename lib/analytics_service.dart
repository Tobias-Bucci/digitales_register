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

import 'dart:async';

import 'package:dr/diagnostics_service.dart';
import 'package:dr/host_platform.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/product_analytics.dart';
import 'package:dr/startup_timeline.dart';
import 'package:dr/telemetry_capabilities.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseTelemetryCollection extends TelemetryCollection {
  FirebaseTelemetryCollection({
    FirebaseAnalytics? analytics,
    Future<void> Function()? initialize,
    TelemetryCapabilities? capabilities,
  })  : _analytics = analytics,
        _initialize = initialize,
        _capabilities = capabilities;
  final FirebaseAnalytics? _analytics;
  final Future<void> Function()? _initialize;
  final TelemetryCapabilities? _capabilities;
  FirebaseAnalytics get analytics => _analytics ?? FirebaseAnalytics.instance;
  @override
  bool get available => supported;
  bool get supported =>
      (_capabilities ?? TelemetryCapabilities.current()).supportsAnalytics;
  Future<void>? _initialization;
  Future<void> _ensure() async {
    if (!supported) return;
    await (_initialization ??= _initialize?.call() ?? _initializeFirebase());
  }

  Future<void> _initializeFirebase() async {
    const bridge = MethodChannel('dr/privacy_bootstrap');
    if (await bridge.invokeMethod<bool>('ready') != true) {
      throw StateError('Native privacy bootstrap unavailable');
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  }

  @override
  Future<void> crashCollection(bool enabled) async {
    if (!supported) return;
    await _ensure();
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> analyticsCollection(bool enabled) async {
    if (!supported) return;
    await _ensure();
    // On withdrawal stop collection first; on opt-in set consent before collection.
    if (!enabled) {
      await analytics.setAnalyticsCollectionEnabled(false);
    }
    await analytics.setConsent(
        analyticsStorageConsentGranted: enabled,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false);
    if (enabled) {
      await analytics.setAnalyticsCollectionEnabled(true);
    } else {
      await AnalyticsService.product.clearTelemetry(reset: false);
    }
  }

  @override
  Future<void> deleteReports() async {
    if (!supported) return;
    await _ensure();
    await FirebaseCrashlytics.instance.deleteUnsentReports();
  }

  @override
  Future<void> resetAnalytics() async {
    if (!supported) return;
    await _ensure();
    await analytics.resetAnalyticsData();
  }
}

// Existing callers use this facade; PrivacyController is the sole consent state.
// ignore: avoid_classes_with_only_static_members
class AnalyticsService {
  static final PrivacyController privacy = PrivacyController(
      store: PreferencesPrivacyStore(),
      collection: FirebaseTelemetryCollection(),
      gate: diagnostics.gate,
      analyticsGate: (enabled) => product.gate(enabled),
      onApplied: (_) async {
        await product.applyPrivacyState();
        await refreshContext?.call();
      },
      onAcademicStatisticsOff: () => product.forgetAcademicSnapshots());
  static Future<void> Function()? refreshContext;
  static final ProductAnalytics product = ProductAnalytics(
      sink: _FirebaseAnalyticsSink(),
      store: SecureAnalyticsStore(),
      decision: () => privacy.decision);
  static Future<void>? _initialization;
  static bool get statisticsEnabled =>
      privacy.decision.analyticsAllowed && privacy.sdkReady;
  static bool get hasCurrentConsent => privacy.decision.isCurrent;
  static Future<void> initLich() => _initialization ??= _initialize();
  static Future<void> _initialize() async {
    diagnostics.installGlobalHandlers();
    await startupTimeline.step('p1_privacy_consent', privacy.initialize);
    await startupTimeline.step('p1_launch_context', _resolveLaunchContext);
  }

  /// Puts the install/upgrade context into the diagnostics. Never throws.
  static Future<void> _resolveLaunchContext() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final info = await PackageInfo.fromPlatform();
      final current = '${info.version}+${info.buildNumber}';
      final launch = LaunchVersionContext.resolve(
          prefs.getString('lastObservedAppVersion'), current,
          existing: privacy.existingInstallation);
      diagnostics.values({
        'is_first_launch': launch.firstLaunch,
        'upgrade_detected': launch.upgrade,
        'previous_app_version': launch.previous,
        'build_flavor': const String.fromEnvironment('BUILD_FLAVOR',
            defaultValue: 'unknown'),
        'release_channel': kDebugMode
            ? 'debug'
            : const String.fromEnvironment('RELEASE_CHANNEL',
                defaultValue: 'unknown'),
        'api_environment': const String.fromEnvironment('API_ENVIRONMENT',
            defaultValue: 'unknown'),
        'flutter_version': const String.fromEnvironment('FLUTTER_VERSION',
            defaultValue: 'unknown'),
        'dart_version': HostPlatform.version.split(' ').first
      });
      if (HostPlatform.isAndroid) {
        try {
          final source = await const MethodChannel('dr/privacy_bootstrap')
              .invokeMethod<String>('installationSource');
          diagnostics.update('installation_source', source ?? 'unknown');
        } catch (_) {
          /* Installer metadata does not block version persistence. */
        }
      }
      if (launch.upgrade) {
        unawaited(product.event('app_update_observed',
            {'previous_version': launch.previous, 'current_version': current}));
      }
      await prefs.setString('lastObservedAppVersion', current);
    } catch (_) {}
  }

  // Compatibility adapter for old call sites; raw timing/count inputs are ignored.
  static Future<void> logCustomEvent(String name,
      [Map<String, Object>? parameters]) {
    if (name == 'calendar_viewed') return product.screenView('timetable');
    if (name == 'grade_calculator_added_grade') {
      return product.event(
          'feature_action', {'feature': 'grade_calculator', 'action': 'add'});
    }
    if (name == 'grade_calculator_imported_grades') {
      return product.event('feature_action',
          {'feature': 'grade_calculator', 'action': 'import'});
    }
    // login_attempt is emitted at the actual login boundary, not the button.
    return Future.value();
  }

  static Future<void> logScreenView(String name) {
    final raw = DiagnosticSanitizer.screen(name);
    const names = {
      'calendar': 'timetable',
      'examCalendar': 'exam_calendar',
      'privacy_consent': 'privacy',
      'privacy_details': 'privacy',
      'profile': 'register',
      'certificate': 'register',
      'classRegister': 'register',
      'courseMaterials': 'register',
      'homeworkSummary': 'homework'
    };
    final screen = names[raw] ?? raw;
    return product.screenView(screen);
  }
}

class _FirebaseAnalyticsSink implements AnalyticsSink {
  bool get available =>
      TelemetryCapabilities.current().supportsAnalytics &&
      Firebase.apps.isNotEmpty;
  @override
  Future<void> event(String name, Map<String, Object> parameters) async {
    if (available) {
      await FirebaseAnalytics.instance
          .logEvent(name: name, parameters: parameters);
    }
  }

  @override
  Future<void> screen(String name) async {
    if (available) {
      await FirebaseAnalytics.instance
          .logScreenView(screenName: name, screenClass: 'register_screen');
    }
  }

  @override
  Future<void> userId(String? id) async {
    if (available) await FirebaseAnalytics.instance.setUserId(id: id);
  }

  @override
  Future<void> property(String name, String? value) async {
    if (available) {
      await FirebaseAnalytics.instance
          .setUserProperty(name: name, value: value);
    }
  }

  @override
  Future<void> reset() async {
    if (available) await FirebaseAnalytics.instance.resetAnalyticsData();
  }
}
