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

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_classes_with_only_static_members
class AnalyticsService {
  static const String _consentGivenKey = 'consent_given';
  static Future<void>? _initializationFuture;
  static bool _initialized = false;
  static bool _firebaseHandlersInstalled = false;

  // 1. Consent anfordern und Firebase bei Zustimmung erlauben
  static Future<void> initLich() async {
    if (_initialized) {
      debugPrint("AnalyticsService ist bereits initialisiert.");
      return;
    }

    _initializationFuture ??= _initialize();
    try {
      await _initializationFuture;
    } finally {
      if (!_initialized) {
        _initializationFuture = null;
      }
    }
  }

  static Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final consentGiven = prefs.getBool(_consentGivenKey);

    // Wenn bereits eine Entscheidung gespeichert wurde, direkt anwenden
    if (consentGiven != null) {
      if (consentGiven) {
        await _enableFirebaseAndAds();
      } else {
        await _disableFirebase();
        _initialized = true;
      }
      return;
    }

    // Keine Entscheidung vorhanden -> Consent-Flow starten
    final params = kDebugMode
        ? ConsentRequestParameters(
            consentDebugSettings: ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: ['0A8EF9EBB8F18901025D2A96EE8EAB47'],
            ),
          )
        : ConsentRequestParameters();

    final completer = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          unawaited(
            _handleConsentInfoUpdate().whenComplete(() {
              if (!completer.isCompleted) {
                completer.complete();
              }
            }),
          );
        },
        (FormError error) {
          debugPrint("❌ Consent Info Update Fehler: ${error.message}");
          unawaited(_persistConsentDecision(false));
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );
      await completer.future;
    } catch (e) {
      debugPrint("❌ Fehler bei Consent-Anfrage: $e");
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  static Future<void> _handleConsentInfoUpdate() async {
    try {
      final isAvailable =
          await ConsentInformation.instance.isConsentFormAvailable();
      if (isAvailable) {
        await _loadAndShowConsentForm();
      } else {
        // Kein Formular verfügbar -> Tracking deaktivieren und Initialisierung abschließen
        await _persistConsentDecision(false);
      }
    } catch (e) {
      debugPrint("❌ Fehler beim Handling Consent Info: $e");
      await _persistConsentDecision(false);
    }
  }

  static Future<void> _loadAndShowConsentForm() async {
    try {
      final completer = Completer<void>();
      ConsentForm.loadConsentForm(
        (ConsentForm consentForm) {
          consentForm.show((FormError? formError) async {
            if (formError != null) {
              debugPrint("⚠️ Formular Fehler: ${formError.message}");
            }
            final consentGiven =
                await ConsentInformation.instance.canRequestAds();
            await _persistConsentDecision(consentGiven);
            if (!completer.isCompleted) {
              completer.complete();
            }
          });
        },
        (FormError error) {
          debugPrint(
              "⚠️ Fehler beim Laden des Consent-Formulars: ${error.message}");
          unawaited(_persistConsentDecision(false));
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );
      await completer.future;
    } catch (e) {
      debugPrint("❌ Exception bei Consent-Formular: $e");
    }
  }

  static Future<void> _persistConsentDecision(bool consentGiven) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentGivenKey, consentGiven);

      if (consentGiven) {
        await _enableFirebaseAndAds();
      } else {
        await _disableFirebase();
        _initialized = true;
      }
    } catch (e) {
      debugPrint("❌ Fehler beim Speichern des Consent-Status: $e");
    }
  }

  static Future<void> _enableFirebaseAndAds() async {
    try {
      await _ensureFirebaseInitialized();
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      await MobileAds.instance.initialize();
      _installCrashReportingOnce();

      debugPrint(
          "✅ Firebase Analytics & Crashlytics erfolgreich DSGVO-konform aktiviert!");
      _initialized = true;
    } catch (e) {
      debugPrint("❌ Fehler bei Firebase Aktivierung: $e");
      _initialized = false;
    }
  }

  static Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    await Firebase.initializeApp();
  }

  static void _installCrashReportingOnce() {
    if (_firebaseHandlersInstalled) {
      return;
    }

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    _firebaseHandlersInstalled = true;
  }

  static Future<void> _disableFirebase() async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    await FirebaseAnalytics.instance.resetAnalyticsData();
    await FirebaseCrashlytics.instance.deleteUnsentReports();
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  static Future<void> logCustomEvent(String name,
      [Map<String, Object>? parameters]) async {
    if (!_initialized) {
      return; // Verhindert fehlerhafte Loggings vor dem Consent-Check
    }
    if (Firebase.apps.isEmpty) {
      return; // Verhindert Absturz, falls Consent abgelehnt wurde
    }

    try {
      await FirebaseAnalytics.instance
          .logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint("❌ Fehler beim Logging von Event '$name': $e");
    }
  }

  static Future<void> showPrivacyOptionsForm(BuildContext context) async {
    try {
      await resetConsent();
      await initLich();
    } catch (e) {
      debugPrint("❌ Fehler bei showPrivacyOptionsForm: $e");
    }
  }

  static Future<void> resetConsent() async {
    try {
      await ConsentInformation.instance.reset();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.remove(_consentGivenKey);
      _initialized = false;
      _initializationFuture = null;
      await _disableFirebase();
      debugPrint("✅ Consent wurde zurückgesetzt.");
    } catch (e) {
      debugPrint("❌ Fehler beim Zurücksetzen des Consent: $e");
    }
  }
}
