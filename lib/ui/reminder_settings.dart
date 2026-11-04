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
import 'package:dr/reminder_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({
    super.key,
    required this.mensaEnabled,
    required this.mensaMinuteOfDay,
    required this.onSetMensaEnabled,
    required this.onSetMensaMinuteOfDay,
    required this.assessmentsEnabled,
    required this.assessmentDays,
    required this.onSetAssessmentsEnabled,
    required this.onSetAssessmentDays,
    this.service,
  });

  final bool mensaEnabled;
  final int mensaMinuteOfDay;
  final ValueChanged<bool> onSetMensaEnabled;
  final ValueChanged<int> onSetMensaMinuteOfDay;
  final bool assessmentsEnabled;
  final List<int> assessmentDays;
  final ValueChanged<bool> onSetAssessmentsEnabled;
  final ValueChanged<List<int>> onSetAssessmentDays;
  final ReminderNotificationService? service;

  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings>
    with WidgetsBindingObserver {
  bool _permissionMissing = false;

  ReminderNotificationService get _service =>
      widget.service ?? reminderNotifications;

  bool get _anyEnabled => widget.mensaEnabled || widget.assessmentsEnabled;

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
      // The dial follows the locale, but the keyboard input only accepts hours
      // after 12 with this flag, which desktop systems usually do not set.
      builder: (context, child) {
        final format = MaterialLocalizations.of(context).timeOfDayFormat();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context) ||
                hourFormat(of: format) != HourFormat.h,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      widget.onSetMensaMinuteOfDay(picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _addAssessmentDay() async {
    final day = await showDialog<int>(
      context: context,
      builder: (_) => _ReminderDayDialog(existing: widget.assessmentDays),
    );
    if (day != null) {
      widget.onSetAssessmentDays(
        normalizeReminderDays([...widget.assessmentDays, day]),
      );
    }
  }

  void _removeAssessmentDay(int day) => widget.onSetAssessmentDays(
        normalizeReminderDays(widget.assessmentDays.where((d) => d != day)),
      );

  Widget _assessmentDays(BuildContext context) {
    final l10n = context.l10n;
    final days = normalizeReminderDays(widget.assessmentDays);
    final time = _formatMinuteOfDay(context, assessmentReminderHour * 60);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in days)
                InputChip(
                  key: Key('assessment-reminder-day-$day'),
                  label: Text(
                    l10n.text(
                      day == 1
                          ? 'reminders.assessment.dayBeforeOne'
                          : 'reminders.assessment.dayBefore',
                      args: {'days': '$day'},
                    ),
                  ),
                  // At least one day has to stay; to stop, use the switch.
                  onDeleted:
                      days.length > 1 ? () => _removeAssessmentDay(day) : null,
                  deleteButtonTooltipMessage:
                      l10n.text('reminders.assessment.removeDay'),
                ),
              if (days.length < maxAssessmentReminderDayCount)
                ActionChip(
                  key: const Key('assessment-reminder-add'),
                  avatar: const Icon(Icons.add),
                  label: Text(l10n.text('reminders.assessment.addDay')),
                  onPressed: () => unawaited(_addAssessmentDay()),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.text('reminders.assessment.timeHint', args: {'time': time}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
          SwitchListTile.adaptive(
            key: const Key('assessment-reminder-toggle'),
            secondary: const Icon(Icons.event_note_outlined),
            title: Text(l10n.text('reminders.assessment.setting')),
            subtitle: Text(l10n.text('reminders.assessment.settingHint')),
            value: widget.assessmentsEnabled,
            onChanged: (enabled) {
              if (enabled) {
                unawaited(_enable(() => widget.onSetAssessmentsEnabled(true)));
              } else {
                widget.onSetAssessmentsEnabled(false);
              }
            },
          ),
          if (widget.assessmentsEnabled) _assessmentDays(context),
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

class _ReminderDayDialog extends StatefulWidget {
  const _ReminderDayDialog({required this.existing});

  final List<int> existing;

  @override
  State<_ReminderDayDialog> createState() => _ReminderDayDialogState();
}

class _ReminderDayDialogState extends State<_ReminderDayDialog> {
  final _controller = TextEditingController();
  ReminderDayError? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = validateReminderDay(_controller.text, widget.existing);
    if (error == null) {
      Navigator.of(context).pop(int.parse(_controller.text.trim()));
    } else {
      setState(() => _error = error);
    }
  }

  String? _errorText(BuildContext context) => switch (_error) {
        null => null,
        ReminderDayError.invalid =>
          context.l10n.text('reminders.assessment.dayInvalid'),
        ReminderDayError.tooLarge => context.l10n.text(
            'reminders.assessment.dayTooLarge',
            args: {'max': '$maxAssessmentReminderDay'},
          ),
        ReminderDayError.duplicate =>
          context.l10n.text('reminders.assessment.dayDuplicate'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.text('reminders.assessment.addDay')),
      content: TextField(
        key: const Key('assessment-reminder-day-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: l10n.text('reminders.assessment.dayLabel'),
          errorText: _errorText(context),
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.text('common.cancel')),
        ),
        FilledButton(
          key: const Key('assessment-reminder-day-confirm'),
          onPressed: _submit,
          child: Text(l10n.text('reminders.assessment.addDayConfirm')),
        ),
      ],
    );
  }
}
