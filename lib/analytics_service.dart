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
  late bool _diagnostics = !AnalyticsService.hasCurrentConsent ||
      AnalyticsService.privacy.decision.diagnosticsAllowed;
  late bool _usage = !AnalyticsService.hasCurrentConsent ||
      AnalyticsService.privacy.decision.analyticsAllowed;
  late bool _academic = !AnalyticsService.hasCurrentConsent ||
      AnalyticsService.privacy.decision.academicStatsAllowed;

  Future<void> _save({bool requiredOnly = false}) async {
    if (_saving) return;
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
              : ConsentChoice.denied);
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
    _diagnostics = _usage = _academic = true;
    await _save();
  }

  void _details() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/privacy_details'),
        builder: (_) => const PrivacyDataDetailsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: widget.management && !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height - 48,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
                  child: Row(children: [
                    Expanded(
                        child: Text(l10n.text('privacyConsent.title'),
                            maxLines: 1,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    if (widget.management)
                      IconButton(
                          tooltip: l10n.text('privacyConsent.cancel'),
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close)),
                  ]),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(l10n.text('privacyConsent.body'),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(height: 1.45)),
                          const SizedBox(height: 12),
                          Text(l10n.text('privacyConsent.note'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant, height: 1.4)),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero),
                                  onPressed: _saving ? null : _details,
                                  icon:
                                      const Icon(Icons.info_outline, size: 18),
                                  label:
                                      Text(l10n.text('privacyConsent.more')))),
                          const SizedBox(height: 4),
                          Material(
                              color: colors.surfaceContainerLow,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side:
                                      BorderSide(color: colors.outlineVariant)),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                if (!_custom)
                                  ListTile(
                                      leading: Icon(Icons.tune,
                                          color: colors.primary),
                                      title: Text(
                                          l10n.text('privacyConsent.customize'),
                                          style: theme.textTheme.labelLarge),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: _saving
                                          ? null
                                          : () =>
                                              setState(() => _custom = true)),
                                for (final category in [
                                  'diagnostics',
                                  'usage',
                                  'academic'
                                ])
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
                                      child: _custom
                                          ? SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                  l10n.text(
                                                      'privacyCategory.$category.title'),
                                                  style: theme
                                                      .textTheme.titleSmall),
                                              subtitle: Text(l10n.text(
                                                  'privacyCategory.$category.body')),
                                              value: category == 'diagnostics'
                                                  ? _diagnostics
                                                  : category == 'usage'
                                                      ? _usage
                                                      : _academic,
                                              onChanged: _saving ||
                                                      (category == 'academic' &&
                                                          !_usage)
                                                  ? null
                                                  : (value) => setState(() {
                                                        if (category ==
                                                            'diagnostics') {
                                                          _diagnostics = value;
                                                        }
                                                        if (category ==
                                                            'usage') {
                                                          _usage = value;
                                                          if (!value) {
                                                            _academic = false;
                                                          }
                                                        }
                                                        if (category ==
                                                            'academic') {
                                                          _academic = value;
                                                        }
                                                      }))
                                          : Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                        category ==
                                                                'diagnostics'
                                                            ? Icons
                                                                .bug_report_outlined
                                                            : category ==
                                                                    'usage'
                                                                ? Icons
                                                                    .insights_outlined
                                                                : Icons
                                                                    .school_outlined,
                                                        color: colors.primary,
                                                        size: 22),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          Text(
                                                              l10n.text(
                                                                  'privacyCategory.$category.title'),
                                                              style: theme
                                                                  .textTheme
                                                                  .titleSmall),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                              l10n.text(
                                                                  'privacySummary.$category'),
                                                              style: theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                      color: colors
                                                                          .onSurfaceVariant,
                                                                      height:
                                                                          1.4)),
                                                        ])),
                                                  ]))),
                              ])),
                          if (_failed) ...[
                            const SizedBox(height: 12),
                            Text(l10n.text('privacyConsent.saveError'),
                                style: TextStyle(color: colors.error)),
                          ],
                        ]),
                  ),
                ),
                Container(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: colors.outlineVariant))),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_custom) ...[
                            FilledButton.icon(
                                onPressed: _saving ? null : () => _save(),
                                icon: const Icon(Icons.check, size: 20),
                                label: Text(l10n.text('privacyConsent.save'),
                                    textAlign: TextAlign.center)),
                            const SizedBox(height: 8),
                            OutlinedButton(
                                onPressed: _saving ? null : _allowAll,
                                child: Text(
                                    l10n.text('privacyConsent.acceptAll'),
                                    textAlign: TextAlign.center)),
                          ] else
                            FilledButton.icon(
                                style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    textStyle: theme.textTheme.labelLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                onPressed: _saving ? null : _allowAll,
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 20),
                                label: Text(
                                    l10n.text('privacyConsent.acceptAll'),
                                    textAlign: TextAlign.center)),
                          const SizedBox(height: 4),
                          TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _save(requiredOnly: true),
                              child: Text(
                                  l10n.text('privacyConsent.necessaryOnly'),
                                  textAlign: TextAlign.center)),
                          if (_saving) const LinearProgressIndicator(),
                        ])),
              ]),
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
