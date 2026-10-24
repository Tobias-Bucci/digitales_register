import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter/material.dart';

class SchoolNotificationSettings extends StatefulWidget {
  const SchoolNotificationSettings({super.key, this.service});
  final SchoolNotificationService? service;

  @override
  State<SchoolNotificationSettings> createState() =>
      _SchoolNotificationSettingsState();
}

class _SchoolNotificationSettingsState extends State<SchoolNotificationSettings>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _failed = false;
  SchoolNotificationService get service =>
      widget.service ?? schoolNotifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run(() async {
      await service.initialize();
      await service.reload();
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_run(service.reload));
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _diagnostic(BuildContext context, String name, String field) {
    final parsed =
        DateTime.tryParse(service.diagnostics[field] as String? ?? '');
    final local = parsed?.toLocal();
    final material = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Text(
          '${context.l10n.text('schoolNotifications.diagnostics.$name')}: ${local == null ? context.l10n.text('schoolNotifications.diagnostics.never') : '${material.formatCompactDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}'}',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = this.service;
    if (!service.supported) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            leading: Icon(
                service.granted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none_rounded,
                color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.text('schoolNotifications.settings.title'),
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(l10n.text('schoolNotifications.settings.privacy')),
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child:
                Text(l10n.text('schoolNotifications.settings.account', args: {
              'account': service.activeAccountLabel ??
                  l10n.text('schoolNotifications.settings.noAccount'),
            })),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(l10n.text('schoolNotifications.settings.enabled')),
            value: service.preferences.enabled,
            onChanged:
                _busy ? null : (value) => _run(() => service.setEnabled(value)),
          ),
          if (!service.granted && service.preferences.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.text('schoolNotifications.settings.permission')),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => _run(service.permissionRequested
                              ? service.openSystemSettings
                              : service.requestPermission),
                      icon: Icon(service.permissionRequested
                          ? Icons.settings_outlined
                          : Icons.notifications_outlined),
                      label: Text(l10n.text(service.permissionRequested
                          ? 'schoolNotifications.settings.system'
                          : 'schoolNotifications.settings.allow')),
                    ),
                  ]),
            ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.school_outlined),
            title: Text(l10n.text('schoolNotifications.grade.title')),
            value: service.preferences.grades,
            onChanged: _busy || !service.preferences.enabled
                ? null
                : (value) => _run(() => service.setCategory(
                    SchoolNotificationCategory.grade, value)),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.mail_outline_rounded),
            title: Text(l10n.text('schoolNotifications.message.title')),
            value: service.preferences.messages,
            onChanged: _busy || !service.preferences.enabled
                ? null
                : (value) => _run(() => service.setCategory(
                    SchoolNotificationCategory.message, value)),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.text('schoolNotifications.settings.count')),
            subtitle:
                Text(l10n.text('schoolNotifications.settings.countPrivacy')),
            value: service.preferences.showEventCount,
            onChanged: _busy || !service.preferences.enabled
                ? null
                : (value) => _run(() => service.setShowEventCount(value)),
          ),
          if (service.enrolledAccountLabels.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                  l10n.text('schoolNotifications.settings.accounts', args: {
                'accounts': service.enrolledAccountLabels
                    .map((label) =>
                        '$label (${l10n.text(service.enrolledAccountStates[label] == false ? 'schoolNotifications.settings.off' : 'schoolNotifications.settings.on')})')
                    .join(', ')
              })),
            ),
          if (service.mobileBackgroundSupported)
            ExpansionTile(
                leading: const Icon(Icons.sync_outlined),
                title:
                    Text(l10n.text('schoolNotifications.settings.diagnostics')),
                children: [
                  if (service.platformStatus['scheduled'] is bool)
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(l10n.text(service
                                    .platformStatus['scheduled'] ==
                                true
                            ? 'schoolNotifications.settings.scheduled'
                            : 'schoolNotifications.settings.notScheduled'))),
                  if (service.platformStatus['channelsBlocked'] == true)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.text(
                            'schoolNotifications.settings.channelsBlocked'))),
                  if (service.backgroundReason != null)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.text(
                            'schoolNotifications.status.${service.backgroundReason}'))),
                  if (service.platformStatus['backgroundRestricted'] == true ||
                      service.platformStatus['powerSaveMode'] == true ||
                      service.platformStatus['backgroundRefreshAvailable'] ==
                          false)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n
                            .text('schoolNotifications.settings.restricted'))),
                  _diagnostic(context, 'started', 'lastBackgroundStartedAt'),
                  _diagnostic(context, 'success', 'lastBackgroundSuccessAt'),
                  _diagnostic(context, 'event', 'lastDetectedAt'),
                  _diagnostic(
                      context, 'requested', 'lastNotificationRequestedAt'),
                  if (service.diagnostics['backgroundResult'] != null)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                            l10n.text(
                                'schoolNotifications.result.${service.diagnostics['backgroundResult']}'),
                            style: Theme.of(context).textTheme.bodySmall)),
                  TextButton.icon(
                    onPressed:
                        _busy ? null : () => _run(service.openSystemSettings),
                    icon: const Icon(Icons.settings_outlined),
                    label:
                        Text(l10n.text('schoolNotifications.settings.system')),
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                          l10n.text('schoolNotifications.settings.background'),
                          style: Theme.of(context).textTheme.bodySmall)),
                ]),
          if (_failed ||
              !service.backgroundAvailable ||
              !service.mobileBackgroundSupported)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                  l10n.text(_failed || !service.backgroundAvailable
                      ? 'schoolNotifications.settings.unavailable'
                      : service.mobileBackgroundSupported
                          ? 'schoolNotifications.settings.background'
                          : 'schoolNotifications.settings.desktop'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
