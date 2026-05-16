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

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // Crashlytics Import
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AnalyticsService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static bool _initialized = false;

  // 1. Consent anfordern und Firebase bei Zustimmung erlauben
  static Future<void> initLich() async {
    if (_initialized) {
      debugPrint("AnalyticsService ist bereits initialisiert.");
      return;
    }

    final params = kDebugMode
        ? ConsentRequestParameters(
            consentDebugSettings: ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: ['0A8EF9EBB8F18901025D2A96EE8EAB47'], // <- Hier geändert
            ),
          )
        : ConsentRequestParameters();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          _handleConsentInfoUpdate();
        },
        (FormError error) {
          debugPrint("❌ Consent Info Update Fehler: ${error.message}");
          // Bei Fehlern NICHT auf initialized=true setzen, damit ein neuer Versuch möglich bleibt
          _initialized = false; 
        },
      );
    } catch (e) {
      debugPrint("❌ Fehler bei Consent-Anfrage: $e");
      _initialized = false;
    }
  }

  static void _handleConsentInfoUpdate() {
    try {
      ConsentInformation.instance.isConsentFormAvailable().then((isAvailable) {
        if (isAvailable) {
          _loadAndShowConsentForm();
        } else {
          _checkConsentAndEnable();
        }
      });
    } catch (e) {
      debugPrint("❌ Fehler beim Handling Consent Info: $e");
    }
  }

  // 2. Formular laden und anzeigen
  static void _loadAndShowConsentForm() {
    try {
      ConsentForm.loadConsentForm(
        (ConsentForm consentForm) {
          ConsentInformation.instance.getConsentStatus().then((status) {
            if (status == ConsentStatus.required) {
              consentForm.show((FormError? formError) {
                if (formError != null) {
                  debugPrint("⚠️ Formular Fehler: ${formError.message}");
                }
                _checkConsentAndEnable();
              });
            } else {
              _checkConsentAndEnable();
            }
          });
        },
        (FormError error) {
          debugPrint("⚠️ Fehler beim Laden des Consent-Formulars: ${error.message}");
        },
      );
    } catch (e) {
      debugPrint("❌ Exception bei Consent-Formular: $e");
    }
  }

  // 3. Prüfen ob zugestimmt wurde
  static void _checkConsentAndEnable() {
    try {
      ConsentInformation.instance.getConsentStatus().then((status) async {
        if (status == ConsentStatus.obtained) {
          await _enableFirebase();
        } else {
          debugPrint("⚠️ Consent nicht erhalten. Firebase bleibt deaktiviert.");
          _initialized = true; // Entscheidung steht (Ablehnung), also initialisiert
        }
      });
    } catch (e) {
      debugPrint("❌ Fehler beim Prüfen des Consent-Status: $e");
    }
  }

  // 4. Firebase Analytics & Crashlytics scharf schalten
  static Future<void> _enableFirebase() async {
    try {
      // Falls Firebase noch gar nicht initialisiert wurde (Sicherheitsnetz)
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      // Erfassung explizit aktivieren
      await _analytics.setAnalyticsCollectionEnabled(true);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

      // Leitet alle nicht abgefangenen Flutter-Fehler automatisch an Crashlytics weiter
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
      
      debugPrint("✅ Firebase Analytics & Crashlytics erfolgreich DSGVO-konform aktiviert!");
      _initialized = true;
    } catch (e) {
      debugPrint("❌ Fehler bei Firebase Aktivierung: $e");
      _initialized = false;
    }
  }

  // 5. Eigene Events tracken
  static Future<void> logCustomEvent(String name, [Map<String, Object>? parameters]) async {
    if (!_initialized) return; // Verhindert fehlerhafte Loggings vor dem Consent-Check
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint("❌ Fehler beim Logging von Event '$name': $e");
    }
  }

  // 6. Consent-Status abrufen
  static Future<ConsentStatus> getConsentStatus() async {
    try {
      return await ConsentInformation.instance.getConsentStatus();
    } catch (e) {
      debugPrint("❌ Fehler beim Abrufen des Consent-Status: $e");
      return ConsentStatus.unknown;
    }
  }

  // Öffnet die Einstellungen (wichtig für den "Datenschutz-Einstellungen"-Button in deiner App)
  static Future<void> showPrivacyOptionsForm(BuildContext context) async {
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      if (status == PrivacyOptionsRequirementStatus.required) {
        await ConsentForm.showPrivacyOptionsForm((FormError? formError) {
          if (formError != null) {
            debugPrint("⚠️ Fehler beim Öffnen der Privacy Options: ${formError.message}");
          }
          _checkConsentAndEnable();
        });
      } else {
        await resetConsent();
        await initLich();
      }
    } catch (e) {
      debugPrint("❌ Fehler bei showPrivacyOptionsForm: $e");
    }
  }

  // 7. Consent zurücksetzen
  static Future<void> resetConsent() async {
    try {
      await ConsentInformation.instance.reset();
      _initialized = false;
      // Analytics wieder schlafen legen, bis neu entschieden wurde
      await _analytics.setAnalyticsCollectionEnabled(false);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      debugPrint("✅ Consent wurde zurückgesetzt.");
    } catch (e) {
      debugPrint("❌ Fehler beim Zurücksetzen des Consent: $e");
    }
  }
}