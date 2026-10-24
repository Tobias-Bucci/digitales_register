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
          if (!service.granted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.text('schoolNotifications.settings.permission')),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed:
                          _busy ? null : () => _run(service.requestPermission),
                      icon: const Icon(Icons.notifications_outlined),
                      label:
                          Text(l10n.text('schoolNotifications.settings.allow')),
                    ),
                  ]),
            ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.school_outlined),
            title: Text(l10n.text('schoolNotifications.grade.title')),
            value: service.preferences.grades,
            onChanged: _busy
                ? null
                : (value) => _run(() => service.setCategory(
                    SchoolNotificationCategory.grade, value)),
          ),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.mail_outline_rounded),
            title: Text(l10n.text('schoolNotifications.message.title')),
            value: service.preferences.messages,
            onChanged: _busy
                ? null
                : (value) => _run(() => service.setCategory(
                    SchoolNotificationCategory.message, value)),
          ),
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
