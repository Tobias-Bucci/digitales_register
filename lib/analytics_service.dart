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
import 'dart:io';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PrivacyConsentChoice { necessaryOnly, all }

class _FirebaseCollection extends TelemetryCollection {
  @override
  bool get available => supported;
  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
  Future<void> _ensure() async {
    if (!supported) return;
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
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    await FirebaseAnalytics.instance.setConsent(
        analyticsStorageConsentGranted: enabled,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false);
  }

  @override
  Future<void> deleteReports() async {
    if (!supported) return;
    await _ensure();
    await FirebaseCrashlytics.instance.deleteUnsentReports();
  }
}

// Existing callers use this facade; PrivacyController is the sole consent state.
// ignore: avoid_classes_with_only_static_members
class AnalyticsService {
  static final privacy = PrivacyController(
      store: PreferencesPrivacyStore(),
      collection: _FirebaseCollection(),
      gate: diagnostics.gate);
  static Future<void>? _initialization;
  static Future<void>? _dialog;
  static bool get statisticsEnabled =>
      privacy.decision.allowsTelemetry && privacy.sdkReady;
  static bool get hasCurrentConsent => privacy.decision.isCurrent;
  static Future<void> initLich() => _initialization ??= _initialize();
  static Future<void> _initialize() async {
    diagnostics.installGlobalHandlers();
    await privacy.initialize();
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
        'dart_version': Platform.version.split(' ').first
      });
      if (Platform.isAndroid) {
        try {
          final source = await const MethodChannel('dr/privacy_bootstrap')
              .invokeMethod<String>('installationSource');
          diagnostics.update('installation_source', source ?? 'unknown');
        } catch (_) {
          /* Installer metadata does not block version persistence. */
        }
      }
      await prefs.setString('lastObservedAppVersion', current);
    } catch (_) {}
  }

  static Future<void> applyConsentChoice(PrivacyConsentChoice choice) =>
      privacy.choose(choice == PrivacyConsentChoice.all
          ? TelemetryConsentState.allAllowed
          : TelemetryConsentState.requiredOnly);
  static const _events = {
    'app_first_frame',
    'theme_loaded',
    'app_opened',
    'calendar_viewed',
    'grade_calculator_added_grade',
    'grade_calculator_imported_grades',
    'login_attempt'
  };
  static Future<void> logCustomEvent(String name,
      [Map<String, Object>? parameters]) async {
    await initLich();
    if (!statisticsEnabled ||
        !_events.contains(name) ||
        Firebase.apps.isEmpty) {
      return;
    }
    final safe = <String, Object>{};
    for (final key in ['elapsedMs', 'count']) {
      final value = parameters?[key];
      if (value is int && value >= 0 && value <= 1000000) safe[key] = value;
    }
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: safe);
    } catch (_) {}
  }

  static Future<void> logScreenView(String screenName) async {
    await initLich();
    if (!statisticsEnabled || Firebase.apps.isEmpty) return;
    try {
      await FirebaseAnalytics.instance
          .logScreenView(screenName: DiagnosticSanitizer.screen(screenName));
    } catch (_) {}
  }

  static Future<void> showPrivacyOptionsForm(BuildContext context) =>
      showPrivacyConsentDialog(context, force: true);
  static Future<void> showPrivacyConsentDialog(BuildContext context,
      {bool force = false}) async {
    await initLich();
    if ((!force && hasCurrentConsent) || !context.mounted) return;
    if (_dialog != null) return _dialog;
    final dialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        routeSettings: const RouteSettings(name: '/privacy_consent'),
        builder: (_) => _PrivacyConsentDialog(management: force));
    _dialog = dialog;
    try {
      await dialog;
    } finally {
      _dialog = null;
    }
  }
}

class _PrivacyConsentDialog extends StatefulWidget {
  const _PrivacyConsentDialog({this.management = false});
  final bool management;
  @override
  State<_PrivacyConsentDialog> createState() => _PrivacyConsentDialogState();
}

class _PrivacyConsentDialogState extends State<_PrivacyConsentDialog> {
  bool _saving = false;
  bool _failed = false;
  Future<void> _choose(PrivacyConsentChoice choice) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await AnalyticsService.applyConsentChoice(choice);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return PopScope(
        canPop: false,
        child: AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(l10n.text(AnalyticsService.privacy.existingInstallation &&
                  !AnalyticsService.hasCurrentConsent
              ? 'privacyConsent.updateTitle'
              : 'privacyConsent.title')),
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
                    l10n.text(AnalyticsService.privacy.existingInstallation &&
                            !AnalyticsService.hasCurrentConsent
                        ? 'privacyConsent.updateBody'
                        : 'privacyConsent.body'),
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
            if (_saving)
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator()),
            if (_failed) Text(l10n.text('privacyConsent.saveError')),
            TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        settings: const RouteSettings(name: '/privacy_details'),
                        builder: (_) => const PrivacyDataDetailsPage())),
                child: Text(l10n.text('privacyConsent.more'))),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _choose(PrivacyConsentChoice.necessaryOnly),
              child: Text(l10n.text('privacyConsent.necessaryOnly')),
            ),
            FilledButton(
              onPressed:
                  _saving ? null : () => _choose(PrivacyConsentChoice.all),
              child: Text(l10n.text(widget.management
                  ? 'privacySettings.allow'
                  : 'privacyConsent.acceptAll')),
            ),
          ],
        ));
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
