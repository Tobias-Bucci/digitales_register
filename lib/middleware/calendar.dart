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
  await loadExportCalendarYear(
      state: () => api.state,
      onLoaded: api.actions.calendarActions.loaded.call,
      progressive: true);
}

// Share network requests between the visible week and background history scan.
final _calendarWeekRequests =
    Expando<Map<UtcDateTime, Future<Map<String, dynamic>?>>>();

Future<Map<String, dynamic>?> _requestCalendarWeek(
    Wrapper session, UtcDateTime monday) async {
  final requests = _calendarWeekRequests[session] ??= {};
  final existing = requests[monday];
  if (existing != null) {
    logCalendarLoad(CalendarLoadEvent.coalesced);
    return existing;
  }
  final future = Future<Map<String, dynamic>?>(() async {
    final timer = Stopwatch()..start();
    logCalendarLoad(CalendarLoadEvent.weekStart);
    try {
      final dynamic data = await session.send('api/calendar/student',
          args: {'startDate': DateFormat('yyyy-MM-dd').format(monday)});
      final valid = data is Map<String, dynamic>;
      logCalendarLoad(
          valid ? CalendarLoadEvent.weekReceived : CalendarLoadEvent.weekFailed,
          elapsedMs: timer.elapsedMilliseconds,
          days: valid ? data.length : 0);
      return valid ? data : null;
    } catch (_) {
      logCalendarLoad(CalendarLoadEvent.weekError,
          elapsedMs: timer.elapsedMilliseconds);
      rethrow;
    }
  });
  requests[monday] = future;
  try {
    return await future;
  } finally {
    if (identical(requests[monday], future)) {
      final removed = requests.remove(monday);
      assert(identical(removed, future));
    }
  }
}

/// Exports reduce once; background loading publishes nearby weeks in batches
/// so holiday data becomes available before the whole school year completes.
Future<bool> loadExportCalendarYear(
    {required AppState Function() state,
    required Future<void> Function(CalendarLoadedPayload) onLoaded,
    bool progressive = false,
    bool Function()? isActive}) async {
  final initial = state();
  if (wrapper.demoMode) return true;
  if (initial.noInternet) return false;
  final year = schoolYearForDate(now);
  if (initial.calendarState.prefetchedSchoolYears.contains(year)) return true;
  final session = wrapper;
  final owner = (initial.url, initial.loginState.username);
  bool active() =>
      (isActive?.call() ?? true) &&
      identical(wrapper, session) &&
      state().loginState.loggedIn &&
      (state().url, state().loginState.username) == owner;
  var complete = true;
  await _runCoalescedLoad('calendar-school-year:${owner.$1}|${owner.$2}:$year',
      () async {
    final loaded = state().calendarState.days.keys.map(toMonday).toSet();
    final merged = <String, dynamic>{};
    final mondays = schoolYearCalendarMondays(year);
    if (progressive) {
      final anchor = toMonday(now);
      mondays.sort((a, b) {
        final aPast = a.isBefore(anchor), bPast = b.isBefore(anchor);
        if (aPast != bPast) return aPast ? 1 : -1;
        return aPast ? b.compareTo(a) : a.compareTo(b);
      });
    }
    final timer = Stopwatch()..start();
    var batchWeeks = 0;
    var requestedWeeks = 0;
    logCalendarLoad(CalendarLoadEvent.historyStart, weeks: mondays.length);
    Future<void> publish({int? completedYear}) async {
      if (!active()) return;
      final data = Map<String, dynamic>.from(merged);
      merged.clear();
      batchWeeks = 0;
      await onLoaded(CalendarLoadedPayload(
          data: data,
          config: _currentSubstituteDetectionConfig(state()),
          completedSchoolYear: completedYear));
      logCalendarLoad(CalendarLoadEvent.historyBatch,
          elapsedMs: timer.elapsedMilliseconds, days: data.length);
    }

    for (final monday in mondays) {
      if (!active()) {
        complete = false;
        logCalendarLoad(CalendarLoadEvent.cancelled,
            elapsedMs: timer.elapsedMilliseconds, weeks: requestedWeeks);
        return;
      }
      if (loaded.contains(monday)) continue;
      Map<String, dynamic>? data;
      try {
        data = await _requestCalendarWeek(session, monday);
      } catch (_) {
        complete = false;
        break;
      }
      requestedWeeks++;
      if (!active()) {
        complete = false;
        logCalendarLoad(CalendarLoadEvent.cancelled,
            elapsedMs: timer.elapsedMilliseconds, weeks: requestedWeeks);
        return;
      }
      if (data is Map<String, dynamic>) {
        merged.addAll(data);
        batchWeeks++;
        if (progressive && batchWeeks >= 4) await publish();
      } else {
        complete = false;
        // Stop on a provider/network failure rather than repeating it for
        // every remaining week; keep the successfully collected partial data.
        break;
      }
      if (state().noInternet) {
        complete = false;
        break;
      }
    }
    if (!active()) {
      complete = false;
      return;
    }
    await publish(completedYear: complete ? year : null);
    logCalendarLoad(
        complete
            ? CalendarLoadEvent.historyComplete
            : CalendarLoadEvent.historyIncomplete,
        elapsedMs: timer.elapsedMilliseconds,
        weeks: requestedWeeks);
  });
  return complete;
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
  if (_isRuntimeCacheFresh(cacheKey, _calendarCacheTtl) &&
      api.state.calendarState.daysForWeek(action.payload).isNotEmpty) {
    logCalendarLoad(CalendarLoadEvent.cacheHit);
    return;
  }

  await _runCoalescedLoad(cacheKey, () async {
    final guard = _Session.capture();
    await next(action);
    final session = guard.wrapper;
    final owner = (api.state.url, api.state.loginState.username);
    final data = await _requestCalendarWeek(session, action.payload);
    if (!guard.isCurrent ||
        (api.state.url, api.state.loginState.username) != owner) {
      logCalendarLoad(CalendarLoadEvent.cancelled);
      return;
    }

    if (data != null) {
      final timer = Stopwatch()..start();
      await api.actions.calendarActions.loaded(
        CalendarLoadedPayload(
          data: data,
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
      _markRuntimeCacheFresh(cacheKey, guard);
      logCalendarLoad(CalendarLoadEvent.weekApplied,
          elapsedMs: timer.elapsedMilliseconds, days: data.length);
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
