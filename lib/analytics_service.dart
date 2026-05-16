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
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: avoid_classes_with_only_static_members
class AnalyticsService {
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
          checkCurrentConsent();
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
                checkCurrentConsent();
              });
            } else {
              checkCurrentConsent();
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

  static const MethodChannel _consentChannel = MethodChannel('dr/consent');

  // 3. Prüfen ob zugestimmt wurde und reaktiv anwenden
  static Future<void> checkCurrentConsent() async {
    try {
      final status = await ConsentInformation.instance.getConsentStatus();
      if (status == ConsentStatus.obtained) {
        final canRequestAds = await ConsentInformation.instance.canRequestAds();
        
        String purposeConsents = '';
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            final String? result = await _consentChannel.invokeMethod('getIABTCFPurposeConsents');
            purposeConsents = result ?? '';
          } catch (e) {
            debugPrint("❌ Fehler beim Auslesen des Consent-Strings über MethodChannel: $e");
          }
        } else {
          // Fallback für iOS (oder wenn SharedPreferences dort direkt ohne Prefix lesbar sind)
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          purposeConsents = prefs.getString('IABTCF_PurposeConsents') ?? '';
        }

        // Index 0 in IABTCF_PurposeConsents entspricht Purpose 1 (Analytics & Storage)
        final hasAnalyticsConsent = purposeConsents.isNotEmpty && purposeConsents[0] == '1';

        if (canRequestAds && hasAnalyticsConsent) {
          _initialized = false; // Reset to force _enableFirebase to run fully
          await _enableFirebase();
        } else {
          debugPrint("⚠️ Nutzer hat Consent verweigert (Not Consent). Firebase bleibt stumm/wird deaktiviert.");
          if (Firebase.apps.isNotEmpty) {
            await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
            await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
          }
          _initialized = true;
        }
      } else {
        debugPrint("⚠️ Consent nicht erhalten. Firebase bleibt deaktiviert.");
        if (Firebase.apps.isNotEmpty) {
          await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
          await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
        }
        _initialized = true; // Entscheidung steht (Ablehnung), also initialisiert
      }
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
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
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
    if (Firebase.apps.isEmpty) return; // Verhindert Absturz, falls Consent abgelehnt wurde

    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters);
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
          checkCurrentConsent();
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
      if (Firebase.apps.isNotEmpty) {
        await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
      }
      debugPrint("✅ Consent wurde zurückgesetzt.");
    } catch (e) {
      debugPrint("❌ Fehler beim Zurücksetzen des Consent: $e");
    }
  }
}
