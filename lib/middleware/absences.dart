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

part of 'middleware.dart';

final _absencesMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(AbsencesActionsNames.load, _loadAbsences)
      ..add(AbsencesActionsNames.addFutureAbsence, _addFutureAbsence)
      ..add(AbsencesActionsNames.justifyAbsence, _justifyAbsence)
      ..add(AbsencesActionsNames.removeFutureAbsence, _removeFutureAbsence);

Future<void> _loadAbsences(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  if (api.state.noInternet) return;
  _absencesDebug('load -> request');
  await next(action);
  dynamic response;
  try {
    response = await wrapper.send("api/student/dashboard/absences");
  } on UnexpectedLogoutException {
    await _handleUnexpectedLogout(api, 'load');
    return;
  }
  if (response != null) {
    final responseMap = getMap(response);
    if (responseMap != null) {
      final absencesCount = (responseMap['absences'] as List?)?.length;
      final futureCount = (responseMap['futureAbsences'] as List?)?.length;
      final dynamic canEdit = responseMap['canEdit'];
      _absencesDebug(
        'load <- canEdit=$canEdit absences=$absencesCount futureAbsences=$futureCount',
      );
    } else {
      _absencesDebug('load <- non-map response: $response');
    }
    await api.actions.absencesActions.loaded(response);
  } else {
    _absencesDebug('load <- null response');
  }
}

Future<void> _addFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<Map<String, dynamic>> action) async {
  if (api.state.noInternet) return;
  _absencesDebug('add -> payload=${action.payload}');
  await next(action);
  dynamic response;
  try {
    response = await wrapper.send(
      'api/student/dashboard/absence_future',
      args: action.payload,
    );
  } on UnexpectedLogoutException {
    await _handleUnexpectedLogout(api, 'add');
    return;
  }
  _absencesDebug('add <- response=$response');
  if (_responseSucceeded(response)) {
    _absencesDebug('add -> success, reloading absences');
    await api.actions.absencesActions.load();
    if (!wrapper.noInternet) {
      showSnackBar('Voraus-Absenz wurde eingetragen');
    }
  } else if (!wrapper.noInternet) {
    _absencesDebug('add -> failed');
    final message = _responseMessage(response);
    showSnackBar(
      message == null
          ? 'Absenz konnte nicht eingetragen werden'
          : 'Absenz konnte nicht eingetragen werden: $message',
    );
  }
}

Future<void> _removeFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<FutureAbsence> action) async {
  if (api.state.noInternet) return;
  await next(action);
  final payload = _buildRemoveFutureAbsencePayload(action.payload);
  _absencesDebug('remove -> payload=$payload');
  if (payload == null) {
    if (!wrapper.noInternet) {
      showSnackBar('Diese Voraus-Absenz kann nicht gelöscht werden');
    }
    return;
  }
  dynamic response;
  try {
    response = await wrapper.send(
      'api/student/dashboard/remove_absence_future',
      args: payload,
    );
  } on UnexpectedLogoutException {
    await _handleUnexpectedLogout(api, 'remove');
    return;
  }
  _absencesDebug('remove <- response=$response');
  if (_responseSucceeded(response)) {
    _absencesDebug('remove -> success, reloading absences');
    await api.actions.absencesActions.load();
  } else if (!wrapper.noInternet) {
    _absencesDebug('remove -> failed');
    final message = _responseMessage(response);
    showSnackBar(
      message == null
          ? 'Absenz konnte nicht gelöscht werden'
          : 'Absenz konnte nicht gelöscht werden: $message',
    );
  }
}

Future<void> _justifyAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<Map<String, dynamic>> action) async {
  if (api.state.noInternet) return;
  await next(action);
  final payload = _buildJustifyAbsencePayload(api.state, action.payload);
  _absencesDebug('justify -> payload=$payload');
  if (payload == null) {
    if (!wrapper.noInternet) {
      final l10n = await _loadMiddlewareLocalizations(api.state);
      showSnackBar(l10n.text('absences.justification.error.invalidPayload'));
    }
    return;
  }
  dynamic response;
  try {
    response = await wrapper.send(
      'api/student/dashboard/absence_reason',
      args: payload,
    );
  } on UnexpectedLogoutException {
    await _handleUnexpectedLogout(api, 'justify');
    return;
  }
  _absencesDebug('justify <- response=$response');
  if (_responseSucceeded(response)) {
    _absencesDebug('justify -> success, reloading absences');
    await api.actions.absencesActions.load();
    if (!wrapper.noInternet) {
      final l10n = await _loadMiddlewareLocalizations(api.state);
      showSnackBar(l10n.text('absences.justification.success'));
    }
  } else if (!wrapper.noInternet) {
    _absencesDebug('justify -> failed');
    final l10n = await _loadMiddlewareLocalizations(api.state);
    final message = _responseMessage(response);
    showSnackBar(
      message == null
          ? l10n.text('absences.justification.error.submit')
          : l10n.text(
              'absences.justification.error.submitWithMessage',
              args: {'message': message},
            ),
    );
  }
}

bool _responseSucceeded(dynamic response) {
  final map = getMap(response);
  final success = map?['success'];
  if (success is bool) {
    return success;
  }
  if (success is int) {
    return success != 0;
  }
  if (success is String) {
    final normalized = success.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'ok';
  }
  return false;
}

void _absencesDebug(String message) {
  debugPrint('[AbsencesDebug] $message');
}

Future<void> _handleUnexpectedLogout(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  String operation,
) async {
  _absencesDebug(
      '$operation -> unexpected logout from server, triggering forced logout');
  if (!wrapper.noInternet) {
    showSnackBar('Sitzung abgelaufen, bitte erneut anmelden');
  }
  await api.actions.loginActions.logout(
    LogoutPayload(
      (b) => b
        ..hard = api.state.settingsState.noPasswordSaving
        ..forced = true,
    ),
  );
}

String? _responseMessage(dynamic response) {
  final map = getMap(response);
  if (map == null) return null;
  final dynamic message = map['message'];
  if (message is String && message.trim().isNotEmpty) {
    return message;
  }
  final dynamic error = map['error'];
  if (error is String && error.trim().isNotEmpty) {
    return error;
  }
  return null;
}

Map<String, dynamic>? _buildRemoveFutureAbsencePayload(FutureAbsence absence) {
  if (absence.id == null) {
    return null;
  }
  final dateFormat = DateFormat('yyyy-MM-dd');
  final timestampFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final Map<String, dynamic> futureAbsence = <String, dynamic>{
    'id': absence.id,
    'note': absence.note,
    'startDate': dateFormat.format(absence.startDate),
    'endDate': dateFormat.format(absence.endDate),
    'startTime': absence.startHour,
    'endTime': absence.endHour,
    'justified': _justifiedToInt(absence.justified),
    'studentId': absence.studentId,
    'reason_user': absence.reasonUser,
    'reason_timestamp': absence.reasonTimestamp != null
        ? timestampFormat.format(absence.reasonTimestamp!)
        : null,
    'reason_signature': absence.reasonSignature,
    'reason': absence.reason,
  };
  return <String, dynamic>{
    'futureAbsence': futureAbsence,
  };
}

int _justifiedToInt(AbsenceJustified justified) {
  switch (justified) {
    case AbsenceJustified.justified:
      return 2;
    case AbsenceJustified.notJustified:
      return 3;
    case AbsenceJustified.forSchool:
      return 4;
    case AbsenceJustified.notYetJustified:
      return 1;
  }
  return 1;
}

Future<AppLocalizations> _loadMiddlewareLocalizations(AppState state) {
  final locale = AppLanguage.fromCode(state.settingsState.languageCode).locale;
  return AppLocalizations.load(locale);
}

Map<String, dynamic>? _buildJustifyAbsencePayload(
  AppState state,
  Map<String, dynamic> input,
) {
  final absenceGroup = input['absenceGroup'];
  final reason = (input['reason'] as String?)?.trim();
  final signature = (input['signature'] as String?)?.trim();
  if (absenceGroup is! AbsenceGroup ||
      reason == null ||
      reason.isEmpty ||
      signature == null ||
      signature.isEmpty ||
      absenceGroup.absences.isEmpty) {
    return null;
  }

  final dateFormat = DateFormat('yyyy-MM-dd');
  final timestamp = UtcDateTime.now();
  final groupDate = absenceGroup.date ?? absenceGroup.absences.first.date;
  final locale = AppLanguage.fromCode(state.settingsState.languageCode)
      .locale
      .toLanguageTag();

  final groupItems = absenceGroup.absences
      .map(
        (absence) => <String, dynamic>{
          'id': absence.id,
          'minutes': absence.minutes,
          'minutes_begin': absence.minutesCameTooLate,
          'minutes_end': absence.minutesLeftTooEarly,
          'justified':
              _justifiedToInt(absence.justified ?? absenceGroup.justified),
          'note': absence.note,
          'date': dateFormat.format(absence.date),
          'hour': absence.hour,
          'reason': absence.reason,
          'reason_signature': absence.reasonSignature,
          'reason_timestamp': absence.reasonTimestamp?.toIso8601String(),
          'reason_user': absence.reasonUser,
          'selfdecl_id': absence.selfdeclId,
          'selfdecl_input': absence.selfdeclInput,
        },
      )
      .toList();

  final orderedAbsences = absenceGroup.absences.toList()
    ..sort((a, b) {
      final dateOrder = a.date.compareTo(b.date);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return a.hour.compareTo(b.hour);
    });
  final startAbsence = orderedAbsences.first;
  final endAbsence = orderedAbsences.last;
  final startTime = _lookupLessonTime(
    state: state,
    date: startAbsence.date,
    hour: startAbsence.hour,
    endTime: false,
  );
  final endTime = _lookupLessonTime(
    state: state,
    date: endAbsence.date,
    hour: endAbsence.hour,
    endTime: true,
  );

  return <String, dynamic>{
    'absenceGroup': <String, dynamic>{
      'group': groupItems,
      'date': dateFormat.format(groupDate),
      'note': absenceGroup.note,
      'reason': reason,
      'reason_signature': signature,
      'reason_timestamp': timestamp.toIso8601String(),
      'reason_user': absenceGroup.reasonUser,
      'justified': _justifiedToInt(absenceGroup.justified),
      'selfdecl_id': absenceGroup.selfdeclId ?? 0,
      'selfdecl_input': absenceGroup.selfdeclInput ?? '',
      'formattedDateObject': <String, dynamic>{
        'startDate':
            DateFormat('EEE dd.MM.yyyy', locale).format(startAbsence.date),
        'startHour': startAbsence.hour,
        'startTimeObj': _buildTimeObject(startTime),
        'endDate': DateFormat('EEE dd.MM.yyyy', locale).format(endAbsence.date),
        'endHour': endAbsence.hour,
        'endTimeObj': _buildTimeObject(endTime),
        'type': 2,
      },
      'showDetails': false,
      'error': false,
      'details': _buildAbsenceDetails(absenceGroup),
      'selfdecl_item': null,
    },
  };
}

String _buildAbsenceDetails(AbsenceGroup group) {
  final units = group.hours + (group.minutes > 0 ? 1 : 0);
  if (units <= 0) {
    return '0 Einheiten';
  }
  return units == 1 ? '1 Einheit' : '$units Einheiten';
}

Map<String, dynamic> _buildTimeObject(String text) {
  final parts = text.split(':');
  final hour = parts.first.padLeft(2, '0');
  final minute = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
  final ts = (int.parse(hour) * 3600) + (int.parse(minute) * 60);
  return <String, dynamic>{
    'h': hour,
    'm': minute,
    'ts': ts,
    'text': '$hour:$minute',
    'html': '$hour<sup>$minute</sup>',
  };
}

String _lookupLessonTime({
  required AppState state,
  required DateTime date,
  required int hour,
  required bool endTime,
}) {
  final exactDate = UtcDateTime(date.year, date.month, date.day);
  final exact = _collectLessonTimesByDate(state, exactDate, hour, endTime);
  if (exact != null) {
    return exact;
  }
  final weekday =
      _collectLessonTimesByWeekday(state, date.weekday, hour, endTime);
  if (weekday != null) {
    return weekday;
  }
  return endTime
      ? _defaultLessonEndTimes[hour] ?? '00:00'
      : _defaultLessonStartTimes[hour] ?? '00:00';
}

String? _collectLessonTimesByDate(
  AppState state,
  UtcDateTime date,
  int lessonHour,
  bool endTime,
) {
  final day = state.calendarState.days[date];
  if (day == null) {
    return null;
  }
  return _collectLessonTimeFromDay(day, lessonHour, endTime);
}

String? _collectLessonTimesByWeekday(
  AppState state,
  int weekday,
  int lessonHour,
  bool endTime,
) {
  final days = state.calendarState.days.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  for (final day in days) {
    if (day.date.weekday != weekday) {
      continue;
    }
    final match = _collectLessonTimeFromDay(day, lessonHour, endTime);
    if (match != null) {
      return match;
    }
  }
  return null;
}

String? _collectLessonTimeFromDay(
  CalendarDay day,
  int lessonHour,
  bool endTime,
) {
  for (final hour in day.hours) {
    if (lessonHour < hour.fromHour || lessonHour > hour.toHour) {
      continue;
    }
    final spans = hour.timeSpans.toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    if (spans.isEmpty) {
      continue;
    }

    final expectedLength = hour.toHour - hour.fromHour + 1;
    if (spans.length == expectedLength) {
      final span = spans[lessonHour - hour.fromHour];
      return _formatClockTime(endTime ? span.to : span.from);
    }

    if (lessonHour == hour.fromHour && !endTime) {
      return _formatClockTime(spans.first.from);
    }
    if (lessonHour == hour.toHour && endTime) {
      return _formatClockTime(spans.last.to);
    }
  }
  return null;
}

String _formatClockTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const Map<int, String> _defaultLessonStartTimes = <int, String>{
  1: '07:50',
  2: '08:40',
  3: '09:35',
  4: '10:25',
  5: '11:30',
  6: '12:20',
  7: '14:10',
  8: '15:00',
  9: '15:50',
  10: '16:40',
};

const Map<int, String> _defaultLessonEndTimes = <int, String>{
  1: '08:40',
  2: '09:30',
  3: '10:25',
  4: '11:15',
  5: '12:20',
  6: '13:10',
  7: '15:00',
  8: '15:50',
  9: '16:40',
  10: '17:30',
};
