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
  if (response != null && response['success'] == true) {
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
  if (response != null && response['success'] == true) {
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
