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

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';

import 'package:dr/actions/absences_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

final absencesReducerBuilder = NestedReducerBuilder<AppState, AppStateBuilder,
    AbsencesState, AbsencesStateBuilder>(
  (s) => s.absencesState,
  (b) => b.absencesState,
)..add<dynamic>(AbsencesActionsNames.loaded, _loaded);

void _loaded(
    AbsencesState state, Action<dynamic> action, AbsencesStateBuilder builder) {
  final parsed = tryParse(getMap(action.payload)!, _parseAbsences);
  if (parsed.absences.length >= state.absences.length) {
    return builder.replace(parsed);
  }

  final mergedByKey = <String, AbsenceGroup>{
    for (final oldGroup in state.absences) _absenceGroupKey(oldGroup): oldGroup,
  };
  for (final newGroup in parsed.absences) {
    mergedByKey[_absenceGroupKey(newGroup)] = newGroup;
  }

  final merged = mergedByKey.values.toList()
    ..sort((a, b) {
      final latestA =
          a.absences.reduce((x, y) => x.date.isAfter(y.date) ? x : y).date;
      final latestB =
          b.absences.reduce((x, y) => x.date.isAfter(y.date) ? x : y).date;
      return latestB.compareTo(latestA);
    });

  return builder.replace(
    parsed.rebuild(
      (b) => b..absences = ListBuilder(merged),
    ),
  );
}

String _absenceGroupKey(AbsenceGroup group) {
  final absenceItems = group.absences
      .map(
        (a) =>
            '${a.date.toIso8601String()}|${a.hour}|${a.minutes}|${a.minutesCameTooLate}|${a.minutesLeftTooEarly}',
      )
      .join('||');
  return '${group.justified.name}::${group.reason ?? ''}::${group.note ?? ''}::${group.reasonSignature ?? ''}::${group.reasonTimestamp?.toIso8601String() ?? ''}::$absenceItems';
}

AbsencesState _parseAbsences(Map json) {
  final rawStats = getMap(json["statistics"])!;
  final stats = AbsenceStatisticBuilder()
    ..counter = getInt(rawStats["counter"])
    ..counterForSchool = getInt(rawStats["counterForSchool"])
    ..delayed = getInt(rawStats["delayed"])
    ..justified = getInt(rawStats["justified"])
    ..notJustified = getInt(rawStats["notJustified"])
    ..percentage = rawStats["percentage"]?.toString().isNotEmpty == true
        ? rawStats["percentage"].toString()
        : null;
  final absences = (json["absences"] as List).map(_parseAbsence).toList()
    ..sort((a, b) {
      final latestA =
          a.absences.reduce((x, y) => x.date.isAfter(y.date) ? x : y).date;
      final latestB =
          b.absences.reduce((x, y) => x.date.isAfter(y.date) ? x : y).date;
      return latestB.compareTo(latestA);
    });
  final futureAbsences =
      (json["futureAbsences"] as List).map(_parseFutureAbsence);
  return AbsencesState(
    (b) => b
      ..statistic = stats
      ..canEdit = getBool(json["canEdit"]) ?? false
      ..absences = ListBuilder(absences)
      ..futureAbsences = ListBuilder(futureAbsences)
      ..lastFetched = UtcDateTime.now(),
  );
}

AbsenceGroup _parseAbsence(dynamic g) {
  return AbsenceGroup(
    (b) => b
      ..date = getString(g["date"]) != null
          ? UtcDateTime.parse(getString(g["date"])!.replaceFirst(" ", "T"))
          : null
      ..justified = AbsenceJustified.fromInt(getInt(g["justified"])!)
      ..reasonSignature = getString(g["reason_signature"])
      ..reasonTimestamp = g["reason_timestamp"] is String
          ? UtcDateTime.tryParse(
              (g["reason_timestamp"] as String).replaceFirst(" ", "T"),
            )
          : null
      ..reasonUser = getInt(g["reason_user"])
      ..reason = getString(g["reason"])
      ..note = getString(g["note"])
      ..selfdeclId = getInt(g["selfdecl_id"])
      ..selfdeclInput = getString(g["selfdecl_input"])
      ..absences = ListBuilder(
        (g["group"] as List).map<Absence>(
          (dynamic a) {
            return Absence(
              (b) => b
                ..id = getInt(a["id"])
                ..minutes = getInt(a["minutes"])
                ..date = UtcDateTime.parse(
                  getString(a["date"])!.replaceFirst(" ", "T"),
                )
                ..hour = getInt(a["hour"])
                ..minutesCameTooLate = getInt(a["minutes_begin"])
                ..minutesLeftTooEarly = getInt(a["minutes_end"])
                ..justified = getInt(a["justified"]) != null
                    ? AbsenceJustified.fromInt(getInt(a["justified"])!)
                    : null
                ..note = getString(a["note"])
                ..reason = getString(a["reason"])
                ..reasonSignature = getString(a["reason_signature"])
                ..reasonTimestamp = a["reason_timestamp"] is String
                    ? UtcDateTime.tryParse(
                        (a["reason_timestamp"] as String)
                            .replaceFirst(" ", "T"),
                      )
                    : null
                ..reasonUser = getInt(a["reason_user"])
                ..selfdeclId = getInt(a["selfdecl_id"])
                ..selfdeclInput = getString(a["selfdecl_input"]),
            );
          },
        ),
      )
      ..minutes = b.absences.build().fold<int>(0, (minutes, a) {
        if (a.minutes != 50) {
          return minutes + a.minutesCameTooLate + a.minutesLeftTooEarly;
        }
        return minutes;
      })
      ..hours = b.absences.build().fold<int>(0, (hours, a) {
        if (a.minutes == 50) {
          return hours + 1;
        }
        return hours;
      }),
  );
}

FutureAbsence _parseFutureAbsence(dynamic absence) {
  return FutureAbsence(
    (b) => b
      ..id = getInt(absence["id"])
      ..studentId = getInt(absence["studentId"])
      ..reasonUser = getInt(absence["reason_user"])
      ..note = getString(absence["note"])
      ..startDate = UtcDateTime.parse(
        getString(absence["startDate"])!.replaceFirst(" ", "T"),
      )
      ..endDate = UtcDateTime.parse(
        getString(absence["endDate"])!.replaceFirst(" ", "T"),
      )
      ..startHour = getInt(absence["startTime"])
      ..endHour = getInt(absence["endTime"])
      ..justified = AbsenceJustified.fromInt(getInt(absence["justified"])!)
      ..reason = getString(absence["reason"])
      ..reasonSignature = getString(absence["reason_signature"])
      ..reasonTimestamp = absence["reason_timestamp"] is String
          ? UtcDateTime.tryParse(
              (absence["reason_timestamp"] as String).replaceFirst(" ", "T"),
            )
          : null,
  );
}
