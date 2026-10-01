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
import 'package:dr/product_analytics.dart';
import 'package:dr/telemetry_capabilities.dart';
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
      });
  static Future<void> Function()? refreshContext;
  static final ProductAnalytics product = ProductAnalytics(
      sink: _FirebaseAnalyticsSink(),
      store: SecureAnalyticsStore(),
      decision: () => privacy.decision);
  static Future<void>? _initialization;
  static Future<void>? _dialog;
  static bool get statisticsEnabled =>
      privacy.decision.analyticsAllowed && privacy.sdkReady;
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
      if (launch.upgrade) {
        unawaited(product.event('app_update_observed',
            {'previous_version': launch.previous, 'current_version': current}));
      }
      await prefs.setString('lastObservedAppVersion', current);
    } catch (_) {}
  }

  static Future<void> applyConsentChoice(PrivacyConsentChoice choice) =>
      privacy.choose(choice == PrivacyConsentChoice.all
          ? TelemetryConsentState.allAllowed
          : TelemetryConsentState.requiredOnly);
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
  late bool _custom = widget.management;
  bool _askingAge = false;
  bool _allowAfterAge = false;
  late AnalyticsAgeEligibility _age =
      AnalyticsService.privacy.decision.ageEligibility;
  late bool _diagnostics = AnalyticsService.privacy.decision.diagnosticsAllowed;
  late bool _usage = AnalyticsService.privacy.decision.analyticsAllowed;
  late bool _academic = AnalyticsService.privacy.decision.academicStatsAllowed;

  Future<void> _save({bool requiredOnly = false}) async {
    if (_saving) return;
    if (!requiredOnly &&
        (_diagnostics || _usage || _academic) &&
        _age == AnalyticsAgeEligibility.unknown) {
      setState(() {
        _askingAge = true;
      });
      return;
    }
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await AnalyticsService.privacy.chooseGranular(
          diagnostics: !requiredOnly && _diagnostics
              ? ConsentChoice.granted
              : ConsentChoice.denied,
          usage: !requiredOnly && _usage
              ? ConsentChoice.granted
              : ConsentChoice.denied,
          academic: !requiredOnly && _academic
              ? ConsentChoice.granted
              : ConsentChoice.denied,
          age: _age);
      unawaited(AnalyticsService.product
          .event('privacy_settings_changed', {'action': 'saved'}));
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

  Future<void> _allowAll() async {
    if (_age != AnalyticsAgeEligibility.atLeast14) {
      setState(() {
        _askingAge = true;
        _allowAfterAge = true;
      });
      return;
    }
    _diagnostics = _usage = _academic = true;
    await _save();
  }

  Future<void> _answerAge(bool eligible) async {
    if (_saving) return;
    setState(() {
      _age = eligible
          ? AnalyticsAgeEligibility.atLeast14
          : AnalyticsAgeEligibility.under14;
      _askingAge = false;
      _custom = true;
      // Reopening eligibility never silently grants optional choices.
      _diagnostics = _usage = _academic = false;
      _saving = true;
    });
    try {
      await AnalyticsService.privacy.resolveAgeEligibility(_age);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    if (eligible && _allowAfterAge) await _allowAll();
    _allowAfterAge = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final eligible = _age == AnalyticsAgeEligibility.atLeast14;
    final update = AnalyticsService.privacy.existingInstallation &&
        !AnalyticsService.hasCurrentConsent;
    return PopScope(
        canPop: widget.management && !_saving,
        child: AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Text(l10n.text(_askingAge
              ? 'privacyAge.question'
              : update
                  ? 'privacyConsent.updateTitle'
                  : 'privacyConsent.title')),
          content: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.sizeOf(context).height * .6),
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    if (!_askingAge) ...[
                      Text(l10n.text('privacyConsent.body')),
                      if (update) ...[
                        const SizedBox(height: 8),
                        Text(l10n.text('privacyConsent.updateBody')),
                      ],
                      const SizedBox(height: 8),
                      Text(l10n.text('privacyConsent.note')),
                      const SizedBox(height: 12),
                      for (final category in [
                        'diagnostics',
                        'usage',
                        'academic'
                      ]) ...[
                        if (_custom)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                l10n.text('privacyCategory.$category.title')),
                            subtitle: Text(
                                l10n.text('privacyCategory.$category.body')),
                            value: category == 'diagnostics'
                                ? _diagnostics
                                : category == 'usage'
                                    ? _usage
                                    : _academic,
                            onChanged: _saving ||
                                    !eligible ||
                                    (category == 'academic' && !_usage)
                                ? null
                                : (value) => setState(() {
                                      if (category == 'diagnostics') {
                                        _diagnostics = value;
                                      }
                                      if (category == 'usage') {
                                        _usage = value;
                                        if (!value) _academic = false;
                                      }
                                      if (category == 'academic') {
                                        _academic = value;
                                      }
                                    }),
                          )
                        else
                          _ConsentInfoTile(
                              icon: category == 'diagnostics'
                                  ? Icons.bug_report_outlined
                                  : Icons.analytics_outlined,
                              title:
                                  l10n.text('privacyCategory.$category.title'),
                              body: l10n.text('privacyCategory.$category.body'),
                              details: '',
                              alwaysActive: false),
                        const SizedBox(height: 8),
                      ],
                      if (_custom)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.text('privacyAge.title')),
                            subtitle:
                                Text(l10n.text('privacyAge.${_age.name}')),
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      _askingAge = true;
                                      _allowAfterAge = false;
                                    })),
                      if (_age == AnalyticsAgeEligibility.under14)
                        Text(l10n.text('privacyAge.under14Explanation')),
                      if (_age == AnalyticsAgeEligibility.unknown && _custom)
                        Text(l10n.text('privacyAge.resolve')),
                    ],
                    if (_failed) Text(l10n.text('privacyConsent.saveError')),
                    if (_saving)
                      const Center(child: CircularProgressIndicator()),
                  ]))),
          actions: [
            if (_askingAge) ...[
              TextButton(
                  onPressed: _saving ? null : () => _answerAge(false),
                  child: Text(l10n.text('privacyAge.no'))),
              FilledButton(
                  onPressed: _saving ? null : () => _answerAge(true),
                  child: Text(l10n.text('privacyAge.yes'))),
            ] else ...[
              TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              settings:
                                  const RouteSettings(name: '/privacy_details'),
                              builder: (_) => const PrivacyDataDetailsPage())),
                  child: Text(l10n.text('privacyConsent.more'))),
              if (_custom)
                TextButton(
                    onPressed: _saving ? null : _allowAll,
                    child: Text(l10n.text('privacyConsent.acceptAll'))),
              if (!_custom)
                TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _custom = true;
                            }),
                    child: Text(l10n.text('privacyConsent.customize'))),
              TextButton(
                  onPressed: _saving ? null : () => _save(requiredOnly: true),
                  child: Text(l10n.text('privacyConsent.necessaryOnly'))),
              FilledButton(
                  onPressed: _saving
                      ? null
                      : _custom
                          ? () => _save()
                          : _allowAll,
                  child: Text(l10n.text(_custom
                      ? 'privacyConsent.save'
                      : 'privacyConsent.acceptAll'))),
              if (widget.management)
                TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.text('privacyConsent.cancel'))),
            ]
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
