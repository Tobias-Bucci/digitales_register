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

import 'package:dr/analytics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/ui/glass_surface.dart' show GlassRimBorder;
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:flutter/material.dart';

/// The open consent dialog, so that a second request joins it.
Future<void>? _openDialog;

/// Opens the consent dialog to change the choices made before.
Future<void> showPrivacyOptionsForm(BuildContext context) =>
    showPrivacyConsentDialog(context, force: true);

/// Asks for consent when there is no current choice, or always with [force].
/// It cannot be dismissed without a choice; a second request while it is
/// open waits for the same dialog.
Future<void> showPrivacyConsentDialog(BuildContext context,
    {bool force = false}) async {
  await AnalyticsService.initLich();
  final hasChoice = !force && AnalyticsService.hasCurrentConsent;
  if (hasChoice || !context.mounted) return;
  if (_openDialog != null) return _openDialog;
  final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: '/privacy_consent'),
      builder: (_) => _PrivacyConsentDialog(management: force));
  _openDialog = dialog;
  try {
    await dialog;
  } finally {
    _openDialog = null;
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
  // Without a current decision every optional purpose starts off: consent
  // must be an active choice, never a pre-set switch (#155). An existing
  // decision shows what it allows.
  late bool _diagnostics = AnalyticsService.hasCurrentConsent &&
      AnalyticsService.privacy.decision.diagnosticsAllowed;
  late bool _usage = AnalyticsService.hasCurrentConsent &&
      AnalyticsService.privacy.decision.analyticsAllowed;
  late bool _academic = AnalyticsService.hasCurrentConsent &&
      AnalyticsService.privacy.decision.academicStatsAllowed;

  /// Whether saving would switch on a purpose that is not allowed now.
  bool get _enablesPurpose {
    final current = AnalyticsService.hasCurrentConsent;
    final d = AnalyticsService.privacy.decision;
    return (_diagnostics && !(current && d.diagnosticsAllowed)) ||
        (_usage && !(current && d.analyticsAllowed)) ||
        (_academic && !(current && d.academicStatsAllowed));
  }

  /// Minors: in Italy from 14 a person can consent alone (Art. 2-quinquies
  /// D.Lgs. 196/2003); younger users need their parents' agreement. The app
  /// asks for no age or ID (data minimisation), only for this confirmation,
  /// and only when an optional purpose is switched on.
  Future<bool> _confirmAge() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: '/privacy_age_confirmation'),
      builder: (context) => AlertDialog(
        title: Text(l10n.text('privacyConsent.age.title')),
        content: Text(l10n.text('privacyConsent.age.body')),
        actions: [
          TextButton(
            key: const Key('privacy-age-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.text('privacyConsent.cancel')),
          ),
          FilledButton(
            key: const Key('privacy-age-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.text('privacyConsent.age.confirm')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _save({bool requiredOnly = false}) async {
    if (_saving) return false;
    if (!requiredOnly && _enablesPurpose && !await _confirmAge()) {
      return false;
    }
    if (!mounted) return false;
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
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return false;
    }
  }

  Future<void> _allowAll() async {
    final before = (_diagnostics, _usage, _academic);
    _diagnostics = _usage = _academic = true;
    // Not confirmed: the switches show what they showed before.
    if (!await _save() && mounted && !_saving && !_failed) {
      setState(() {
        _diagnostics = before.$1;
        _usage = before.$2;
        _academic = before.$3;
      });
    }
  }

  /// "Allow all" and "Required data only" always look alike. In the custom
  /// view "Save" is the main action, so both step back to outlined buttons.
  Widget _choiceButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final child = Text(label, textAlign: TextAlign.center);
    if (_custom) {
      return OutlinedButton(key: key, onPressed: onPressed, child: child);
    }
    return FilledButton.tonal(
        key: key,
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            textStyle: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        onPressed: onPressed,
        child: child);
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
        // Opened from the settings of the new design, it gets the rim of its
        // glass panels; on first start, above the shell, it keeps its corners.
        shape: theme.dialogTheme.shape is GlassRimBorder
            ? theme.dialogTheme.shape
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                          ],
                          // Refusing is as easy and as visible as accepting:
                          // the same kind of button, the same style (#155).
                          _choiceButton(
                              key: const Key('privacy-accept-all'),
                              label: l10n.text('privacyConsent.acceptAll'),
                              onPressed: _saving ? null : _allowAll),
                          const SizedBox(height: 8),
                          _choiceButton(
                              key: const Key('privacy-required-only'),
                              label: l10n.text('privacyConsent.necessaryOnly'),
                              onPressed: _saving
                                  ? null
                                  : () => _save(requiredOnly: true)),
                          if (_saving) const LinearProgressIndicator(),
                        ])),
              ]),
        ),
      ),
    );
  }
}
