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

final _calendarMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(CalendarActionsNames.load, _loadCalendar)
      ..add(CalendarActionsNames.select, _selectionChanged)
      ..add(CalendarActionsNames.setCurrentMonday, _weekChanged)
      ..add(CalendarActionsNames.onOpenFile, _openSubmission)
      ..add(RoutingActionsNames.showCalendar, _clearSelection);

Future<void> _ensureSchoolYearCalendarLoaded(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  if (wrapper.demoMode || api.state.noInternet) return;

  final schoolYear = schoolYearForDate(now);
  if (api.state.calendarState.prefetchedSchoolYears.contains(schoolYear)) {
    return;
  }
  final sessionKey =
      '${api.state.url ?? ''}|${api.state.loginState.username ?? ''}';

  await _runCoalescedLoad('calendar-school-year:$sessionKey:$schoolYear',
      () async {
    if (api.state.calendarState.prefetchedSchoolYears.contains(schoolYear)) {
      return;
    }

    final loadedMondays = {
      for (final date in api.state.calendarState.days.keys) toMonday(date),
    };
    var complete = true;
    for (final monday in schoolYearCalendarMondays(schoolYear)) {
      final currentSessionKey =
          '${api.state.url ?? ''}|${api.state.loginState.username ?? ''}';
      if (!api.state.loginState.loggedIn || currentSessionKey != sessionKey) {
        return;
      }
      if (loadedMondays.contains(monday)) continue;
      final dynamic data = await wrapper.send(
        'api/calendar/student',
        args: {'startDate': DateFormat('yyyy-MM-dd').format(monday)},
      );
      if (data is! Map<String, dynamic>) {
        complete = false;
        continue;
      }
      await api.actions.calendarActions.loaded(
        CalendarLoadedPayload(
          data: data,
          config: _currentSubstituteDetectionConfig(api.state),
        ),
      );
      loadedMondays.add(monday);
    }

    if (!complete) return;
    await api.actions.calendarActions.loaded(
      CalendarLoadedPayload(
        data: const <String, dynamic>{},
        config: _currentSubstituteDetectionConfig(api.state),
        completedSchoolYear: schoolYear,
      ),
    );
    await api.actions.saveState();
  });
}

SubstituteDetectionConfig _currentSubstituteDetectionConfig(AppState state) =>
    SubstituteDetectionConfig(
      (b) => b
        ..enabled = state.settingsState.substituteDetectionEnabled
        ..primaryTeachers =
            state.settingsState.substitutePrimaryTeachers.toBuilder()
        ..lockedSubjects = state
            .settingsState.substitutePrimaryTeachersLockedSubjects
            .toBuilder(),
    );

int schoolYearForDate(DateTime date) =>
    date.month >= DateTime.july ? date.year : date.year - 1;

List<UtcDateTime> schoolYearCalendarMondays(int schoolYear) {
  final first = toMonday(UtcDateTime(schoolYear, DateTime.september));
  final last = toMonday(UtcDateTime(schoolYear + 1, DateTime.june, 30));
  final mondays = <UtcDateTime>[];
  for (var monday = first;
      !monday.isAfter(last);
      monday = monday.add(const Duration(days: 7))) {
    mondays.add(UtcDateTime(monday.year, monday.month, monday.day));
  }
  return mondays;
}

Future<void> _loadCalendar(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<UtcDateTime> action,
) async {
  if (api.state.noInternet) return;

  final cacheKey = _calendarCacheKey(action.payload);
  if (_isRuntimeCacheFresh(cacheKey, _calendarCacheTtl)) {
    return;
  }

  await _runCoalescedLoad(cacheKey, () async {
    await next(action);
    final dynamic data = await wrapper.send(
      "api/calendar/student",
      args: {"startDate": DateFormat("yyyy-MM-dd").format(action.payload)},
    );

    if (data != null) {
      await api.actions.calendarActions.loaded(
        CalendarLoadedPayload(
          data: data as Map<String, dynamic>,
          config: SubstituteDetectionConfig(
            (b) => b
              ..enabled = api.state.settingsState.substituteDetectionEnabled
              ..primaryTeachers =
                  api.state.settingsState.substitutePrimaryTeachers.toBuilder()
              ..lockedSubjects = api
                  .state.settingsState.substitutePrimaryTeachersLockedSubjects
                  .toBuilder(),
          ),
        ),
      );
      _markRuntimeCacheFresh(cacheKey);
    }
  });
}

Future<void> _selectionChanged(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<CalendarSelection?> action,
) async {
  await next(action);
  if (action.payload == null) {
    return;
  }
  final newWeek = toMonday(action.payload!.date);
  if (api.state.calendarState.currentMonday != newWeek) {
    await api.actions.calendarActions.setCurrentMonday(newWeek);
    await api.actions.calendarActions.load(newWeek);
  }
}

Future<void> _weekChanged(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<UtcDateTime> action,
) async {
  await next(action);
  final selectedDate = api.state.calendarState.selection?.date;
  if (selectedDate != null && toMonday(selectedDate) != action.payload) {
    await api.actions.calendarActions.select(
      CalendarSelection(
        (b) => b
          ..date = UtcDateTime(
            action.payload.year,
            action.payload.month,
            action.payload.day,
          ),
      ),
    );
  }
}

Future<void> _clearSelection(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  await api.actions.calendarActions.select(null);
}

Future<void> _openSubmission(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<LessonContentSubmission> action,
) async {
  await next(action);

  if (!action.payload.fileAvailable ||
      !await canOpenFile(action.payload.uniqueName)) {
    await api.actions.calendarActions.onDownloadFile(action.payload);
    final success = await downloadFile(
      "${wrapper.baseAddress}api/lessonContent/lessonContentSubmissionDownloadEntry",
      action.payload.uniqueName,
      <String, dynamic>{
        "parentId": action.payload.lessonContentId,
        "submissionId": action.payload.id,
      },
    );
    await api.actions.calendarActions.fileAvailable(
      action.payload.rebuild((b) => b..fileAvailable = success),
    );
    if (!success) {
      return;
    }
  }

  await openFile(action.payload.uniqueName);
}
