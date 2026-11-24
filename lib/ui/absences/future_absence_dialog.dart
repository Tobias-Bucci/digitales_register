// Copyright (C) 2021 Michael Debertol
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

part of '../absences_page.dart';

// The dialog or sheet that announces a future absence, and the lesson
// times it offers, taken from the loaded calendar.

/// Opens the form to record a future absence in a glass sheet of the new
/// design. It returns the payload for `addFutureAbsence`, or null when the
/// sheet is closed or cancelled.
Future<Map<String, dynamic>?> showFutureAbsenceSheet(BuildContext context) =>
    showGlassSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _FutureAbsenceDialogContainer(sheet: true),
    );

class _FutureAbsenceDialogContainer extends StatelessWidget {
  const _FutureAbsenceDialogContainer({this.sheet = false});

  final bool sheet;

  @override
  Widget build(BuildContext context) {
    return StoreConnection<
        AppState,
        AppActions,
        (
          Map<UtcDateTime, Map<int, String>>,
          Map<UtcDateTime, Map<int, String>>,
          Map<int, Map<int, String>>,
          Map<int, Map<int, String>>
        )>(
      builder: (context, vm, actions) {
        return _FutureAbsenceDialog(
          sheet: sheet,
          lessonStartTimesByDate: vm.$1,
          lessonEndTimesByDate: vm.$2,
          lessonStartTimesByWeekday: vm.$3,
          lessonEndTimesByWeekday: vm.$4,
          onLoadCalendarWeek: (date) {
            final monday = toMonday(UtcDateTime.makeUtc(date));
            actions.calendarActions.setCurrentMonday(monday);
            actions.calendarActions.load(monday);
          },
        );
      },
      connect: (state) {
        final lessonTimesByDate = _collectLessonTimesByDate(state);
        final lessonTimesByWeekday = _collectLessonTimesByWeekday(state);
        return (
          lessonTimesByDate.$1,
          lessonTimesByDate.$2,
          lessonTimesByWeekday.$1,
          lessonTimesByWeekday.$2,
        );
      },
    );
  }
}

class _FutureAbsenceDialog extends StatefulWidget {
  final Map<UtcDateTime, Map<int, String>> lessonStartTimesByDate;
  final Map<UtcDateTime, Map<int, String>> lessonEndTimesByDate;
  final Map<int, Map<int, String>> lessonStartTimesByWeekday;
  final Map<int, Map<int, String>> lessonEndTimesByWeekday;
  final void Function(DateTime date) onLoadCalendarWeek;

  /// In a glass sheet of the new design rather than a dialog.
  final bool sheet;

  const _FutureAbsenceDialog({
    this.sheet = false,
    required this.lessonStartTimesByDate,
    required this.lessonEndTimesByDate,
    required this.lessonStartTimesByWeekday,
    required this.lessonEndTimesByWeekday,
    required this.onLoadCalendarWeek,
  });

  @override
  State<_FutureAbsenceDialog> createState() => _FutureAbsenceDialogState();
}

class _FutureAbsenceDialogState extends State<_FutureAbsenceDialog> {
  static const Map<int, String> _lessonStartTimes = <int, String>{
    1: '7:50',
    2: '8:40',
    3: '9:35',
    4: '10:25',
    5: '11:30',
    6: '12:20',
    7: '14:10',
    8: '15:00',
    9: '15:50',
    10: '16:40',
  };
  static const Map<int, String> _lessonEndTimes = <int, String>{
    1: '8:40',
    2: '9:30',
    3: '10:25',
    4: '11:15',
    5: '12:20',
    6: '13:10',
    7: '15:00',
    8: '15:50',
    9: '16:40',
    10: '17:30',
  };

  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  DateTime _startDate = now;
  DateTime _endDate = now;
  int _startTime = 1;
  int _endTime = 1;
  bool _wholeDay = false;
  final Set<UtcDateTime> _requestedMondays = <UtcDateTime>{};

  bool get _validInput =>
      _reasonController.text.trim().isNotEmpty &&
      _signatureController.text.trim().isNotEmpty;

  Map<int, String> get _fallbackLessonStartTimes => _lessonStartTimes;

  Map<int, String> get _fallbackLessonEndTimes => _lessonEndTimes;

  /// Lesson times of [date]: its own loaded schedule, else the schedule of the
  /// same weekday, else the default bell times.
  Map<int, String> _lessonTimesFor(
    DateTime date, {
    required Map<UtcDateTime, Map<int, String>> byDate,
    required Map<int, Map<int, String>> byWeekday,
    required Map<int, String> fallback,
  }) {
    final dateTimes = byDate[UtcDateTime(date.year, date.month, date.day)];
    if (dateTimes != null && dateTimes.isNotEmpty) {
      return _sortedLessonTimes(dateTimes);
    }
    final weekdayTimes = byWeekday[date.weekday];
    if (weekdayTimes != null && weekdayTimes.isNotEmpty) {
      return _sortedLessonTimes(weekdayTimes);
    }
    return fallback;
  }

  /// Start times of the lessons on the start date.
  Map<int, String> get _effectiveLessonStartTimes => _lessonTimesFor(
        _startDate,
        byDate: widget.lessonStartTimesByDate,
        byWeekday: widget.lessonStartTimesByWeekday,
        fallback: _fallbackLessonStartTimes,
      );

  /// End times of the lessons on the end date, which can follow a different
  /// schedule than the start date in a multi-day absence.
  Map<int, String> get _effectiveLessonEndTimes => _lessonTimesFor(
        _endDate,
        byDate: widget.lessonEndTimesByDate,
        byWeekday: widget.lessonEndTimesByWeekday,
        fallback: _fallbackLessonEndTimes,
      );

  List<int> get _availableStartLessonHours =>
      _effectiveLessonStartTimes.keys.toList();

  List<int> get _availableEndLessonHours =>
      _effectiveLessonEndTimes.keys.toList();

  int get _submittedStartTime => _wholeDay ? 1 : _startTime;

  int get _submittedEndTime => _wholeDay ? 20 : _endTime;

  bool get _hasWeekendSelection =>
      _startDate.weekday == DateTime.saturday ||
      _startDate.weekday == DateTime.sunday ||
      _endDate.weekday == DateTime.saturday ||
      _endDate.weekday == DateTime.sunday;

  bool get _validRange {
    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _submittedStartTime,
    );
    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _submittedEndTime,
    );
    return !start.isAfter(end);
  }

  @override
  void initState() {
    super.initState();
    _ensureCalendarWeekLoaded();
    _syncSelectedHoursToAvailableRange();
  }

  @override
  void didUpdateWidget(covariant _FutureAbsenceDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelectedHoursToAvailableRange();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final dateFormat = DateFormat('yyyy-MM-dd', localeTag);
    final fromLabel = l10n.text('absences.dialog.from');
    final toLabel = l10n.text('absences.dialog.to');
    final fields = <Widget>[
      TextField(
        key: const Key('future-absence-reason'),
        controller: _reasonController,
        decoration: InputDecoration(
          labelText: l10n.text('absences.dialog.reason'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('future-absence-signature'),
        controller: _signatureController,
        decoration: InputDecoration(
          labelText: l10n.text('absences.dialog.signature'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.text('absences.dialog.startDate')),
        subtitle: Text(DateFormat('dd.MM.yyyy', localeTag).format(_startDate)),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _startDate,
            firstDate: now.subtract(const Duration(days: 1)),
            lastDate: now.add(const Duration(days: 365 * 2)),
          );
          if (!mounted) return;
          if (picked != null) {
            setState(() {
              _startDate = DateTime(
                picked.year,
                picked.month,
                picked.day,
                _startDate.hour,
                _startDate.minute,
                _startDate.second,
                _startDate.millisecond,
                _startDate.microsecond,
              );
              if (_endDate.isBefore(_startDate)) {
                _endDate = _startDate;
              }
              _ensureCalendarWeekLoaded();
              _syncSelectedHoursToAvailableRange();
            });
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.text('absences.dialog.endDate')),
        subtitle: Text(DateFormat('dd.MM.yyyy', localeTag).format(_endDate)),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _endDate,
            firstDate: _startDate,
            lastDate: now.add(const Duration(days: 365 * 2)),
          );
          if (!mounted) return;
          if (picked != null) {
            setState(() {
              _endDate = DateTime(
                picked.year,
                picked.month,
                picked.day,
                _endDate.hour,
                _endDate.minute,
                _endDate.second,
                _endDate.millisecond,
                _endDate.microsecond,
              );
              _ensureCalendarWeekLoaded();
              _syncSelectedHoursToAvailableRange();
            });
          }
        },
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.text('absences.dialog.wholeDay')),
        value: _wholeDay,
        onChanged: (value) {
          setState(() {
            _wholeDay = value;
          });
        },
      ),
      if (_hasWeekendSelection)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.text('absences.dialog.weekendWarning'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>(
                'start-hour-${_dateKey(_startDate)}-$_startTime-$_wholeDay',
              ),
              initialValue: _startTime,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.text('absences.dialog.startHour'),
              ),
              items: _availableStartLessonHours
                  .map(
                    (lessonHour) => DropdownMenuItem(
                      value: lessonHour,
                      child: Text(
                          '$lessonHour ($fromLabel ${_effectiveLessonStartTimes[lessonHour]})'),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (context) => _availableStartLessonHours
                  .map(
                    (lessonHour) => Text(
                      '$lessonHour (${_effectiveLessonStartTimes[lessonHour]})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                  .toList(),
              onChanged: _wholeDay
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _startTime = value);
                      }
                    },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: ValueKey<String>(
                'end-hour-${_dateKey(_endDate)}-$_endTime-$_wholeDay',
              ),
              initialValue: _endTime,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.text('absences.dialog.endHour'),
              ),
              items: _availableEndLessonHours
                  .map(
                    (lessonHour) => DropdownMenuItem(
                      value: lessonHour,
                      child: Text(
                          '$lessonHour ($toLabel ${_effectiveLessonEndTimes[lessonHour]})'),
                    ),
                  )
                  .toList(),
              selectedItemBuilder: (context) => _availableEndLessonHours
                  .map(
                    (lessonHour) => Text(
                      '$lessonHour (${_effectiveLessonEndTimes[lessonHour]})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                  .toList(),
              onChanged: _wholeDay
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _endTime = value);
                      }
                    },
            ),
          ),
        ],
      ),
      if (!_validRange)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            l10n.text('absences.dialog.invalidRange'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ];
    final VoidCallback? submit = _validInput && _validRange
        ? () {
            final payload = {
              'futureAbsence': {
                'startDateObject': _startDate.toUtc().toIso8601String(),
                'startTime': _submittedStartTime,
                'endDateObject': _endDate.toUtc().toIso8601String(),
                'endTime': _submittedEndTime,
                'reason': _reasonController.text.trim(),
                'reason_signature': _signatureController.text.trim(),
                'startDate': dateFormat.format(_startDate),
                'endDate': dateFormat.format(_endDate),
              },
            };
            Navigator.of(context).pop(payload);
          }
        : null;
    final cancel = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l10n.text('common.cancel')),
    );
    if (widget.sheet) {
      return AbsenceFormPanel(
        title: l10n.text('absences.dialog.title'),
        actions: [
          cancel,
          FilledButton(
            key: const Key('future-absence-save'),
            onPressed: submit,
            child: Text(l10n.text('button.save')),
          ),
        ],
        children: fields,
      );
    }
    return AlertDialog(
      title: Text(l10n.text('absences.dialog.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields,
        ),
      ),
      actions: [
        cancel,
        ElevatedButton(
          onPressed: submit,
          child: Text(l10n.text('button.save')),
        ),
      ],
    );
  }

  /// Keeps both selections valid for their own date, e.g. after a date change
  /// or when a loaded week replaces the fallback schedule.
  void _syncSelectedHoursToAvailableRange() {
    final startHours = _availableStartLessonHours;
    if (startHours.isEmpty) {
      _startTime = 1;
    } else if (!startHours.contains(_startTime)) {
      _startTime = startHours.first;
    }

    final endHours = _availableEndLessonHours;
    if (endHours.isEmpty) {
      _endTime = 1;
    } else if (!endHours.contains(_endTime)) {
      _endTime = endHours.last;
    }
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  Map<int, String> _sortedLessonTimes(Map<int, String> lessonTimes) {
    final sortedEntries = lessonTimes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map<int, String>.fromEntries(sortedEntries);
  }

  /// Requests the weeks of both endpoints, which differ for an absence that
  /// spans more than one week.
  void _ensureCalendarWeekLoaded() {
    for (final date in [_startDate, _endDate]) {
      final monday = toMonday(UtcDateTime(date.year, date.month, date.day));
      if (_requestedMondays.add(monday)) {
        widget.onLoadCalendarWeek(date);
      }
    }
  }
}

/// The start and end time of each lesson hour, by the key [keyOf] gives a
/// day (its date or its weekday). The earliest day that has a time wins.
(Map<K, Map<int, String>>, Map<K, Map<int, String>>) _collectLessonTimes<K>(
  AppState state,
  K Function(CalendarDay day) keyOf,
) {
  final lessonStarts = <K, Map<int, String>>{};
  final lessonEnds = <K, Map<int, String>>{};

  final calendarDays = state.calendarState.days.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  for (final day in calendarDays) {
    final key = keyOf(day);
    final starts = lessonStarts.putIfAbsent(key, () => {});
    final ends = lessonEnds.putIfAbsent(key, () => {});
    for (final hour in day.hours) {
      final spans = hour.timeSpans.toList()
        ..sort((a, b) => a.from.compareTo(b.from));
      if (spans.isEmpty) {
        continue;
      }

      final expectedLength = hour.toHour - hour.fromHour + 1;
      if (spans.length == expectedLength) {
        for (var i = 0; i < spans.length; i++) {
          final lessonHour = hour.fromHour + i;
          starts.putIfAbsent(
            lessonHour,
            () => formatClockTime(spans[i].from),
          );
          ends.putIfAbsent(
            lessonHour,
            () => formatClockTime(spans[i].to),
          );
        }
        continue;
      }

      starts.putIfAbsent(
        hour.fromHour,
        () => formatClockTime(spans.first.from),
      );
      ends.putIfAbsent(
        hour.toHour,
        () => formatClockTime(spans.last.to),
      );
    }
  }

  return (lessonStarts, lessonEnds);
}

(
  Map<UtcDateTime, Map<int, String>>,
  Map<UtcDateTime, Map<int, String>>
) _collectLessonTimesByDate(AppState state) =>
    _collectLessonTimes(state, (day) => day.date.stripTime());

(
  Map<int, Map<int, String>>,
  Map<int, Map<int, String>>
) _collectLessonTimesByWeekday(AppState state) =>
    _collectLessonTimes(state, (day) => day.date.weekday);

(Map<int, Map<int, String>>, Map<int, Map<int, String>>)
    collectLessonTimesByWeekday(AppState state) {
  return _collectLessonTimesByWeekday(state);
}
