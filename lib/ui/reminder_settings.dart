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
import 'package:dr/reminder_notifications.dart';
import 'package:flutter/material.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({
    super.key,
    required this.mensaEnabled,
    required this.mensaMinuteOfDay,
    required this.onSetMensaEnabled,
    required this.onSetMensaMinuteOfDay,
    this.service,
  });

  final bool mensaEnabled;
  final int mensaMinuteOfDay;
  final ValueChanged<bool> onSetMensaEnabled;
  final ValueChanged<int> onSetMensaMinuteOfDay;
  final ReminderNotificationService? service;

  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings>
    with WidgetsBindingObserver {
  bool _permissionMissing = false;

  ReminderNotificationService get _service =>
      widget.service ?? reminderNotifications;

  bool get _anyEnabled => widget.mensaEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from the system settings.
    if (state == AppLifecycleState.resumed) unawaited(_checkPermission());
  }

  Future<void> _checkPermission() async {
    if (!_anyEnabled) return _showPermission(granted: true);
    await _showPermission(granted: await _permissionState(_service.hasPermission));
  }

  /// Turning a reminder on is the moment to ask, as the user knows why.
  Future<void> _enable(void Function() save) async {
    save();
    await _showPermission(
      granted: await _permissionState(_service.requestPermission),
    );
  }

  /// A system that cannot answer is no reason to warn about a denial.
  Future<bool> _permissionState(Future<bool> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return true;
    }
  }

  Future<void> _showPermission({required bool granted}) async {
    if (mounted) setState(() => _permissionMissing = !granted);
  }

  Future<void> _pickMensaTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: widget.mensaMinuteOfDay ~/ 60,
        minute: widget.mensaMinuteOfDay % 60,
      ),
    );
    if (picked != null) {
      widget.onSetMensaMinuteOfDay(picked.hour * 60 + picked.minute);
    }
  }

  String _formatMinuteOfDay(BuildContext context, int minuteOfDay) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              Icons.alarm_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              l10n.text('reminders.settings.title'),
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(l10n.text('reminders.settings.subtitle')),
          ),
          if (_permissionMissing && _anyEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.text('reminders.settings.permission')),
                  if (_service.canOpenSystemSettings) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => unawaited(_service.openSystemSettings()),
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(
                        l10n.text('schoolNotifications.settings.system'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          SwitchListTile.adaptive(
            key: const Key('mensa-reminder-toggle'),
            secondary: const Icon(Icons.restaurant_outlined),
            title: Text(l10n.text('reminders.mensa.setting')),
            subtitle: Text(l10n.text('reminders.mensa.settingHint')),
            value: widget.mensaEnabled,
            onChanged: (enabled) {
              if (enabled) {
                unawaited(_enable(() => widget.onSetMensaEnabled(true)));
              } else {
                widget.onSetMensaEnabled(false);
              }
            },
          ),
          if (widget.mensaEnabled)
            ListTile(
              key: const Key('mensa-reminder-time'),
              leading: const Icon(Icons.schedule_outlined),
              title: Text(l10n.text('reminders.mensa.time')),
              trailing: Text(
                _formatMinuteOfDay(context, widget.mensaMinuteOfDay),
                style: theme.textTheme.titleMedium,
              ),
              onTap: () => unawaited(_pickMensaTime()),
            ),
          if (_service.onlyWhileRunning)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                l10n.text('reminders.settings.whileRunning'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
