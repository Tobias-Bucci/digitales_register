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

import 'package:dr/i18n/app_localizations.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PrivacyConsentChoice {
  necessaryOnly,
  all,
}

// ignore: avoid_classes_with_only_static_members
class AnalyticsService {
  static const String _consentChoiceKey = 'privacy_consent_choice_v2';
  static const String _legacyConsentGivenKey = 'consent_given';
  static const int _consentVersion = 2;

  static Future<void>? _initializationFuture;
  static bool _initialized = false;
  static bool _firebaseHandlersInstalled = false;
  static PrivacyConsentChoice? _choice;

  static bool get statisticsEnabled => _choice == PrivacyConsentChoice.all;
  static bool get hasCurrentConsent => _choice != null;

  static Future<void> initLich() async {
    if (_initialized) {
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

    _choice = _readChoice(prefs.getString(_consentChoiceKey));
    if (_choice == null && prefs.containsKey(_legacyConsentGivenKey)) {
      await prefs.remove(_legacyConsentGivenKey);
    }

    await _ensureFirebaseInitialized();
    if (_choice == PrivacyConsentChoice.all) {
      await _enableFirebaseCollection();
    } else {
      await _disableFirebaseCollection();
    }
    _initialized = true;
  }

  static PrivacyConsentChoice? _readChoice(String? raw) {
    if (raw == 'v${_consentVersion}_all') {
      return PrivacyConsentChoice.all;
    }
    if (raw == 'v${_consentVersion}_necessary_only') {
      return PrivacyConsentChoice.necessaryOnly;
    }
    return null;
  }

  static String _writeChoice(PrivacyConsentChoice choice) {
    switch (choice) {
      case PrivacyConsentChoice.all:
        return 'v${_consentVersion}_all';
      case PrivacyConsentChoice.necessaryOnly:
        return 'v${_consentVersion}_necessary_only';
    }
  }

  static Future<void> applyConsentChoice(PrivacyConsentChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consentChoiceKey, _writeChoice(choice));
    await prefs.remove(_legacyConsentGivenKey);
    _choice = choice;

    await _ensureFirebaseInitialized();
    if (choice == PrivacyConsentChoice.all) {
      await _enableFirebaseCollection();
      await logCustomEvent('privacy_consent_updated', <String, Object>{
        'statistics_enabled': true,
      });
    } else {
      await _disableFirebaseCollection();
    }
    _initialized = true;
  }

  static Future<void> _enableFirebaseCollection() async {
    await FirebaseAnalytics.instance.setConsent(
      analyticsStorageConsentGranted: true,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    _installCrashReportingOnce();
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

  static Future<void> _disableFirebaseCollection() async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    await FirebaseAnalytics.instance.setConsent(
      analyticsStorageConsentGranted: false,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await FirebaseAnalytics.instance.resetAnalyticsData();
    await FirebaseCrashlytics.instance.deleteUnsentReports();
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }

  static Future<void> logCustomEvent(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    await initLich();
    if (!statisticsEnabled || Firebase.apps.isEmpty) {
      return;
    }

    try {
      await FirebaseAnalytics.instance
          .logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint("Fehler beim Logging von Event '$name': $e");
    }
  }

  static Future<void> logScreenView(String screenName) async {
    await initLich();
    if (!statisticsEnabled || Firebase.apps.isEmpty) {
      return;
    }

    try {
      await FirebaseAnalytics.instance.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint("Fehler beim Logging von Screen '$screenName': $e");
    }
  }

  static Future<void> showPrivacyOptionsForm(BuildContext context) async {
    await showPrivacyConsentDialog(context, force: true);
  }

  static Future<void> showPrivacyConsentDialog(
    BuildContext context, {
    bool force = false,
  }) async {
    await initLich();
    if (!force && hasCurrentConsent) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final choice = await showDialog<PrivacyConsentChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _PrivacyConsentDialog(),
    );
    if (choice == null) {
      return;
    }
    await applyConsentChoice(choice);
  }
}

class _PrivacyConsentDialog extends StatelessWidget {
  const _PrivacyConsentDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(l10n.text('privacyConsent.title')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.62,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.text('privacyConsent.body'),
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
              ),
              const SizedBox(height: 16),
              _ConsentInfoTile(
                icon: Icons.lock_outline,
                title: l10n.text('privacyConsent.necessary.title'),
                body: l10n.text('privacyConsent.necessary.body'),
                details: l10n.text('privacyConsent.necessary.details'),
                alwaysActive: true,
              ),
              const SizedBox(height: 10),
              _ConsentInfoTile(
                icon: Icons.analytics_outlined,
                title: l10n.text('privacyConsent.statistics.title'),
                body: l10n.text('privacyConsent.statistics.body'),
                details: l10n.text('privacyConsent.statistics.details'),
                alwaysActive: false,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.text('privacyConsent.note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(PrivacyConsentChoice.necessaryOnly),
          child: Text(l10n.text('privacyConsent.necessaryOnly')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(PrivacyConsentChoice.all),
          child: Text(l10n.text('privacyConsent.acceptAll')),
        ),
      ],
    );
  }
}

class _ConsentInfoTile extends StatelessWidget {
  const _ConsentInfoTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.details,
    required this.alwaysActive,
  });

  final IconData icon;
  final String title;
  final String body;
  final String details;
  final bool alwaysActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusLabel = alwaysActive
        ? context.l10n.text('privacyConsent.alwaysActive')
        : context.l10n.text('privacyConsent.optional');
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: alwaysActive
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: alwaysActive
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              details,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
