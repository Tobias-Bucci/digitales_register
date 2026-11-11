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
import 'package:dr/reminder_link.dart';
import 'package:dr/reminder_notifications.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({
    super.key,
    required this.mensaEnabled,
    required this.mensaMinuteOfDay,
    required this.mensaUrl,
    required this.onSetMensaEnabled,
    required this.onSetMensaMinuteOfDay,
    required this.onSetMensaUrl,
    required this.mensaWeekdays,
    required this.onSetMensaWeekdays,
    required this.assessmentsEnabled,
    required this.assessmentDays,
    required this.onSetAssessmentsEnabled,
    required this.examsEnabled,
    required this.onSetExamsEnabled,
    required this.testsEnabled,
    required this.onSetTestsEnabled,
    required this.homeworkEnabled,
    required this.onSetHomeworkEnabled,
    required this.onSetAssessmentDays,
    required this.assessmentMinuteOfDay,
    required this.onSetAssessmentMinuteOfDay,
    this.service,
  });

  final bool mensaEnabled;
  final int mensaMinuteOfDay;
  final String mensaUrl;
  final ValueChanged<bool> onSetMensaEnabled;
  final ValueChanged<int> onSetMensaMinuteOfDay;
  final ValueChanged<String> onSetMensaUrl;

  /// ISO weekdays, 1 = Monday.
  final List<int> mensaWeekdays;
  final ValueChanged<List<int>> onSetMensaWeekdays;
  final bool assessmentsEnabled;
  final List<int> assessmentDays;
  final ValueChanged<bool> onSetAssessmentsEnabled;
  final bool examsEnabled;
  final ValueChanged<bool> onSetExamsEnabled;
  final bool testsEnabled;
  final ValueChanged<bool> onSetTestsEnabled;
  final bool homeworkEnabled;
  final ValueChanged<bool> onSetHomeworkEnabled;
  final ValueChanged<List<int>> onSetAssessmentDays;
  final int assessmentMinuteOfDay;
  final ValueChanged<int> onSetAssessmentMinuteOfDay;
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
    await _showPermission(
        granted: await _permissionState(_service.hasPermission));
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

  Future<void> _pickTime(int minuteOfDay, ValueChanged<int> onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      // The dial follows the locale, but the keyboard input only accepts hours
      // after 12 with this flag, which desktop systems usually do not set.
      builder: (context, child) {
        final format = MaterialLocalizations.of(context).timeOfDayFormat();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat:
                MediaQuery.alwaysUse24HourFormatOf(context) ||
                    hourFormat(of: format) != HourFormat.h,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onPicked(picked.hour * 60 + picked.minute);
  }

  Widget _timeTile({
    required Key key,
    required int minuteOfDay,
    required ValueChanged<int> onPicked,
  }) =>
      ListTile(
        key: key,
        leading: const Icon(Icons.schedule_outlined),
        title: Text(context.l10n.text('reminders.settings.time')),
        trailing: Text(
          _formatMinuteOfDay(context, minuteOfDay),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        onTap: () => unawaited(_pickTime(minuteOfDay, onPicked)),
      );

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

  /// The weekdays of the Mensa reminder, Monday first, in the app's language.
  /// The last selected day cannot be deselected; to stop, use the switch.
  Widget _mensaWeekdays(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final localeTag = l10n.locale.toLanguageTag();
    final selected = normalizeReminderWeekdays(widget.mensaWeekdays);
    final lastOne = selected.length == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.text('reminders.mensa.weekdays'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var weekday = DateTime.monday;
                  weekday <= DateTime.sunday;
                  weekday++)
                _weekdayChip(
                  weekday: weekday,
                  // 1 January 2024 was a Monday.
                  date: DateTime(2024, 1, weekday),
                  localeTag: localeTag,
                  selected: selected.contains(weekday),
                  locked: lastOne && selected.contains(weekday),
                  onChanged: (on) => widget.onSetMensaWeekdays(
                    normalizeReminderWeekdays(on
                        ? [...selected, weekday]
                        : selected.where((day) => day != weekday)),
                  ),
                ),
            ],
          ),
          if (lastOne) ...[
            const SizedBox(height: 6),
            Text(
              l10n.text('reminders.mensa.weekdaysLastOne'),
              key: const Key('mensa-reminder-weekdays-last'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _weekdayChip({
    required int weekday,
    required DateTime date,
    required String localeTag,
    required bool selected,
    required bool locked,
    required ValueChanged<bool> onChanged,
  }) {
    final l10n = context.l10n;
    final name = l10n.capitalize(DateFormat('EEEE', localeTag).format(date));
    return FilterChip(
      key: Key('mensa-reminder-weekday-$weekday'),
      label: Text(
        l10n.capitalize(DateFormat('E', localeTag).format(date)),
        semanticsLabel: name,
      ),
      tooltip: name,
      showCheckmark: false,
      selected: selected,
      onSelected: locked ? null : onChanged,
    );
  }

  /// What the assessment reminders cover. Nothing chosen is allowed, but said.
  List<Widget> _assessmentKinds(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    const padding = EdgeInsetsDirectional.only(start: 32, end: 16);
    final nothing =
        !widget.examsEnabled && !widget.testsEnabled && !widget.homeworkEnabled;
    return [
      SwitchListTile.adaptive(
        key: const Key('exam-reminder-toggle'),
        contentPadding: padding,
        secondary: const Icon(Icons.school_outlined),
        title: Text(l10n.text('reminders.exam.setting')),
        value: widget.examsEnabled,
        onChanged: widget.onSetExamsEnabled,
      ),
      SwitchListTile.adaptive(
        key: const Key('test-reminder-toggle'),
        contentPadding: padding,
        secondary: const Icon(Icons.quiz_outlined),
        title: Text(l10n.text('reminders.test.setting')),
        value: widget.testsEnabled,
        onChanged: widget.onSetTestsEnabled,
      ),
      SwitchListTile.adaptive(
        key: const Key('homework-reminder-toggle'),
        contentPadding: padding,
        secondary: const Icon(Icons.menu_book_outlined),
        title: Text(l10n.text('reminders.homework.setting')),
        subtitle: Text(l10n.text('reminders.homework.settingHint')),
        value: widget.homeworkEnabled,
        onChanged: widget.onSetHomeworkEnabled,
      ),
      if (nothing)
        Padding(
          key: const Key('assessment-reminder-nothing'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.text('reminders.assessment.nothingChosen'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _assessmentDays(BuildContext context) {
    final l10n = context.l10n;
    final days = normalizeReminderDays(widget.assessmentDays);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: double.infinity,
            child: Text(
              l10n.text('reminders.assessment.daysCaption'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
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
          if (widget.mensaEnabled) ...[
            _timeTile(
              key: const Key('mensa-reminder-time'),
              minuteOfDay: widget.mensaMinuteOfDay,
              onPicked: widget.onSetMensaMinuteOfDay,
            ),
            _mensaWeekdays(context),
            _ReminderLinkField(
              key: const Key('mensa-reminder-url'),
              value: widget.mensaUrl,
              onSaved: widget.onSetMensaUrl,
            ),
          ],
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
          if (widget.assessmentsEnabled) ...[
            ..._assessmentKinds(context),
            if (widget.examsEnabled ||
                widget.testsEnabled ||
                widget.homeworkEnabled)
              _timeTile(
                key: const Key('assessment-reminder-time'),
                minuteOfDay: widget.assessmentMinuteOfDay,
                onPicked: widget.onSetAssessmentMinuteOfDay,
              ),
            if (widget.examsEnabled || widget.testsEnabled)
              _assessmentDays(context),
          ],
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

/// Edits the link of a reminder. A value is saved when the field is left, not
/// while typing, because a half-typed address can look valid. An invalid value
/// is never saved, so the last valid one stays in effect.
class _ReminderLinkField extends StatefulWidget {
  const _ReminderLinkField({
    super.key,
    required this.value,
    required this.onSaved,
  });

  final String value;
  final ValueChanged<String> onSaved;

  @override
  State<_ReminderLinkField> createState() => _ReminderLinkFieldState();
}

class _ReminderLinkFieldState extends State<_ReminderLinkField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_ReminderLinkField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    // Leaving the page does not take the focus away first.
    _save(showError: false);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _save(showError: true);
  }

  void _save({required bool showError}) {
    final link = normalizeReminderLink(_controller.text);
    if (showError && mounted) setState(() => _invalid = link == null);
    if (link == null) return;
    if (showError) _controller.text = link;
    if (link != widget.value) widget.onSaved(link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        key: const Key('mensa-reminder-url-field'),
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: l10n.text('reminders.mensa.url'),
          hintText: l10n.text('reminders.mensa.urlHint'),
          helperText: l10n.text('reminders.mensa.urlHelper'),
          helperMaxLines: 2,
          errorText: _invalid ? l10n.text('reminders.mensa.urlInvalid') : null,
          errorMaxLines: 2,
        ),
        onChanged: (_) {
          if (_invalid) setState(() => _invalid = false);
        },
        onSubmitted: (_) => _save(showError: true),
      ),
    );
  }
}
