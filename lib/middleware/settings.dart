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

final _settingsMiddleware = MiddlewareBuilder<AppState, AppStateBuilder,
    AppActions>()
  ..add(GradesActionsNames.loaded, _updateSubjectThemes)
  ..add(DashboardActionsNames.loaded, _updateSubjectThemes)
  ..add(CalendarActionsNames.loaded, _updateSubjectThemes)
  ..add(CalendarActionsNames.loaded, _populateSubstitutePrimaryTeachers)
  ..add(CalendarActionsNames.loaded, _recalculateSubstitutes)
  ..add(DashboardActionsNames.loaded, _reconcileCalendarSync)
  ..add(CalendarActionsNames.loaded, _reconcileCalendarSync)
  ..add(DashboardActionsNames.homeworkAdded, _reconcileCalendarSync)
  ..add(DashboardActionsNames.reminderEdited, _reconcileCalendarSync)
  ..add(DashboardActionsNames.deleteHomework, _reconcileCalendarSync)
  ..add(DashboardActionsNames.toggleDone, _reconcileCalendarSync)
  ..add(SettingsActionsNames.setLanguage, _setLanguage)
  ..add(SettingsActionsNames.pushNotificationsEnabled,
      _setPushNotificationsEnabled)
  ..add(
      SettingsActionsNames.substituteDetectionEnabled, _recalculateSubstitutes)
  ..add(SettingsActionsNames.substitutePrimaryTeachers, _recalculateSubstitutes)
  ..add(SettingsActionsNames.calendarSyncEnabled, _setCalendarSyncEnabled)
  ..add(SettingsActionsNames.calendarSyncCalendarId, _setCalendarSyncCalendarId)
  ..add(
      SettingsActionsNames.removeCalendarSyncEvents, _removeCalendarSyncEvents);

final _substituteTeacherHistoryMutex = Mutex();
final Set<String> _substituteTeacherHistoryAttemptedKeys = <String>{};
final Set<String> _substituteTeacherHistoryLoadingKeys = <String>{};

const int _initialSubstituteTeacherPastWeeks = 4;
const int _initialSubstituteTeacherFutureWeeks = 8;
const int _extendedSubstituteTeacherFutureWeeks = 20;

Future<void> _updateSubjectThemes(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action action) async {
  await next(action);
  final allSubjects = api.state.extractAllSubjects();
  await api.actions.settingsActions.updateSubjectThemes(allSubjects);
}

Future<void> _populateSubstitutePrimaryTeachers(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action action) async {
  await next(action);

  final sessionKey = _substituteTeacherHistorySessionKey(api.state);
  if (_substituteTeacherHistoryLoadingKeys.contains(sessionKey)) {
    return;
  }

  await _applyDetectedSubstituteTeacherSettings(api);
}

Future<void> _applyDetectedSubstituteTeacherSettings(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {

  final settings = api.state.settingsState;
  final detectedPrimaryTeachers =
      _detectPrimaryTeachersFromCalendar(api.state.calendarState.days.toMap());
  final mergedPrimaryTeachers = {
    for (final entry in settings.substitutePrimaryTeachers.entries)
      entry.key: entry.value.toList(),
  };

  for (final subject in api.state.extractAllSubjects()) {
    final resolvedSubject =
        findStringIgnoreCase(mergedPrimaryTeachers.keys, subject) ?? subject;
    final configuredTeachers = mergedPrimaryTeachers[resolvedSubject] ?? const <String>[];
    if (configuredTeachers.isNotEmpty) {
      mergedPrimaryTeachers[resolvedSubject] = configuredTeachers;
      continue;
    }
    if (settings.substitutePrimaryTeachersLockedSubjects.any(
      (item) => equalsIgnoreCase(item, subject),
    )) {
      mergedPrimaryTeachers[resolvedSubject] = const <String>[];
      continue;
    }

    final detectedSubjectKey =
        findStringIgnoreCase(detectedPrimaryTeachers.keys, subject);
    final detectedTeacher = detectedSubjectKey == null
        ? null
        : detectedPrimaryTeachers[detectedSubjectKey];
    mergedPrimaryTeachers[resolvedSubject] = detectedTeacher == null
        ? const <String>[]
        : <String>[detectedTeacher];
  }

  final primaryTeachersChanged = !_samePrimaryTeacherMap(
    settings.substitutePrimaryTeachers,
    mergedPrimaryTeachers,
  );
  if (primaryTeachersChanged) {
    await api.actions.settingsActions.substitutePrimaryTeachers(
      BuiltMap<String, BuiltList<String>>(
        mergedPrimaryTeachers.map(
          (key, value) => MapEntry(key, BuiltList<String>.from(value)),
        ),
      ),
    );
  }

  final knownTeachers = <String>[
    ...settings.substituteKnownTeachers,
  ];
  for (final teacher in api.state.extractAllTeachers()) {
    if (!containsStringIgnoreCase(knownTeachers, teacher)) {
      knownTeachers.add(teacher);
    }
  }
  if (!_sameIgnoreCaseList(settings.substituteKnownTeachers, knownTeachers)) {
    await api.actions.settingsActions.substituteKnownTeachers(
      BuiltList<String>.from(knownTeachers),
    );
  }
}

String? generateAutomaticSubjectNick(String subject) {
  final words = subject
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length != 2 && words.length != 3) {
    return null;
  }

  return '${words.first.substring(0, 1).toUpperCase()}'
      '${words.last.substring(0, 1).toUpperCase()}';
}

Future<void> _setPushNotificationsEnabled(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  await next(action);
  final enabled = await NotificationBackgroundService.setEnabled(
    enabled: action.payload,
  );
  if (action.payload && !enabled) {
    showSnackBar(
      tr('notifications.permissionDeniedDisabled'),
    );
    if (api.state.settingsState.pushNotificationsEnabled) {
      await api.actions.settingsActions.pushNotificationsEnabled(false);
    }
  }
}

Future<void> _recalculateSubstitutes(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action action) async {
  await next(action);
  final sessionKey = _substituteTeacherHistorySessionKey(api.state);
  if (action is Action<CalendarLoadedPayload> &&
      _substituteTeacherHistoryLoadingKeys.contains(sessionKey)) {
    return;
  }
  await api.actions.calendarActions.recalculateSubstitutes(
    SubstituteDetectionConfig(
      (b) => b
        ..enabled = api.state.settingsState.substituteDetectionEnabled
        ..primaryTeachers =
            api.state.settingsState.substitutePrimaryTeachers.toBuilder()
        ..lockedSubjects = api
            .state.settingsState.substitutePrimaryTeachersLockedSubjects
            .toBuilder(),
    ),
  );
}

Future<void> _setCalendarSyncEnabled(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  await next(action);
  if (!isAndroidPlatform) {
    return;
  }

  if (!action.payload) {
    return;
  }

  final enableResult = await CalendarSyncService.prepareForEnable(
    preferredCalendarId: api.state.settingsState.calendarSyncCalendarId,
  );
  if (enableResult != CalendarSyncEnableResult.ready) {
    showSnackBar(
      switch (enableResult) {
        CalendarSyncEnableResult.permissionDenied => tr(
            'calendarSync.permissionDenied',
          ),
        CalendarSyncEnableResult.noWritableCalendar => tr(
            'calendarSync.noWritableCalendar',
          ),
        _ => tr('calendarSync.unavailable'),
      },
    );
    if (api.state.settingsState.calendarSyncEnabled) {
      await api.actions.settingsActions.calendarSyncEnabled(false);
    }
    return;
  }

  final success = await CalendarSyncService.reconcile(api.state);
  if (!success) {
    showSnackBar(tr('calendarSync.partialSyncFailure'));
  }
}

Map<String, String> _detectPrimaryTeachersFromCalendar(
  Map<UtcDateTime, CalendarDay> days,
) {
  final teacherCountsBySubject = <String, Map<String, int>>{};
  for (final entry in days.entries) {
    for (final hour in entry.value.hours) {
      if (hour.teachers.length != 1) {
        continue;
      }
      final teacherName = hour.teachers.single.fullName;
      if (teacherName.trim().isEmpty) {
        continue;
      }
      final subject =
          findStringIgnoreCase(teacherCountsBySubject.keys, hour.subject) ??
              hour.subject;
      final teacherCounts =
          teacherCountsBySubject.putIfAbsent(subject, () => <String, int>{});
      final resolvedTeacher =
          findStringIgnoreCase(teacherCounts.keys, teacherName) ?? teacherName;
      for (var lessonHour = hour.fromHour;
          lessonHour <= hour.toHour;
          lessonHour++) {
        teacherCounts.update(
          resolvedTeacher,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  final detectedBySubject = <String, String>{};
  for (final entry in teacherCountsBySubject.entries) {
    final sortedTeachers = entry.value.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    if (sortedTeachers.isNotEmpty) {
      detectedBySubject[entry.key] = sortedTeachers.first.key;
    }
  }

  return detectedBySubject;
}

bool _samePrimaryTeacherMap(
  BuiltMap<String, BuiltList<String>> current,
  Map<String, List<String>> next,
) {
  if (current.length != next.length) {
    return false;
  }
  for (final entry in current.entries) {
    final nextKey = findStringIgnoreCase(next.keys, entry.key);
    if (nextKey == null ||
        !_sameIgnoreCaseList(entry.value, next[nextKey] ?? const <String>[])) {
      return false;
    }
  }
  return true;
}

String? _singleTeacher(Iterable<String> teachers) {
  for (final teacher in teachers) {
    if (teacher.trim().isNotEmpty) {
      return teacher;
    }
  }
  return null;
}

Future<void> _ensureSubstituteTeacherHistoryLoaded(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  if (api.state.noInternet || !api.state.loginState.loggedIn) {
    return;
  }
  final sessionKey = _substituteTeacherHistorySessionKey(api.state);
  if (_substituteTeacherHistoryLoadingKeys.contains(sessionKey)) {
    return;
  }
  if (_substituteTeacherHistoryAttemptedKeys.contains(sessionKey) &&
      _allKnownSubjectsHavePrimaryTeacher(api.state)) {
    return;
  }
  await _substituteTeacherHistoryMutex.protect(() async {
    if (_substituteTeacherHistoryLoadingKeys.contains(sessionKey)) {
      return;
    }
    if (_substituteTeacherHistoryAttemptedKeys.contains(sessionKey) &&
        _allKnownSubjectsHavePrimaryTeacher(api.state)) {
      return;
    }

    _substituteTeacherHistoryLoadingKeys.add(sessionKey);
    try {
      final shouldGenerateInitialSubjectNicks =
          !api.state.settingsState.subjectNicksAutoGenerated;
      final anchorMonday = api.state.calendarState.currentMonday ?? toMonday(now);
      await _loadCalendarWeeksAround(
        api,
        anchorMonday,
        fromOffsetWeeks: -_initialSubstituteTeacherPastWeeks,
        toOffsetWeeks: _initialSubstituteTeacherFutureWeeks,
      );

      if (_allKnownSubjectsHavePrimaryTeacher(api.state)) {
        if (shouldGenerateInitialSubjectNicks) {
          await _populateInitialSubjectNicks(api);
        }
        await _applyDetectedSubstituteTeacherSettings(api);
        await api.actions.calendarActions.recalculateSubstitutes(
          SubstituteDetectionConfig(
            (b) => b
              ..enabled = api.state.settingsState.substituteDetectionEnabled
              ..primaryTeachers = api
                  .state.settingsState.substitutePrimaryTeachers
                  .toBuilder()
              ..lockedSubjects = api
                  .state.settingsState.substitutePrimaryTeachersLockedSubjects
                  .toBuilder(),
          ),
        );
        _substituteTeacherHistoryAttemptedKeys.add(sessionKey);
        return;
      }

      await _loadCalendarWeeksAround(
        api,
        anchorMonday,
        fromOffsetWeeks: _initialSubstituteTeacherFutureWeeks + 1,
        toOffsetWeeks: _extendedSubstituteTeacherFutureWeeks,
      );

      if (shouldGenerateInitialSubjectNicks) {
        await _populateInitialSubjectNicks(api);
      }

      await _applyDetectedSubstituteTeacherSettings(api);
      await api.actions.calendarActions.recalculateSubstitutes(
        SubstituteDetectionConfig(
          (b) => b
            ..enabled = api.state.settingsState.substituteDetectionEnabled
            ..primaryTeachers =
                api.state.settingsState.substitutePrimaryTeachers.toBuilder()
            ..lockedSubjects = api
                .state.settingsState.substitutePrimaryTeachersLockedSubjects
                .toBuilder(),
        ),
      );

      _substituteTeacherHistoryAttemptedKeys.add(sessionKey);
    } finally {
      _substituteTeacherHistoryLoadingKeys.remove(sessionKey);
    }
  });
}

String _substituteTeacherHistorySessionKey(AppState state) {
  return '${state.url ?? ''}|${state.loginState.username ?? ''}';
}

Future<void> _loadCalendarWeeksAround(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  UtcDateTime anchorMonday, {
  required int fromOffsetWeeks,
  required int toOffsetWeeks,
}) async {
  final loadedMondays = {
    for (final date in api.state.calendarState.days.keys) toMonday(date),
  };
  final formatter = DateFormat('yyyy-MM-dd');

  for (var weekOffset = fromOffsetWeeks;
      weekOffset <= toOffsetWeeks;
      weekOffset++) {
    final monday = anchorMonday.add(Duration(days: weekOffset * 7));
    final normalizedMonday = UtcDateTime(
      monday.year,
      monday.month,
      monday.day,
    );
    if (loadedMondays.contains(normalizedMonday)) {
      continue;
    }
    dynamic data;
    try {
      data = await wrapper.send(
        'api/calendar/student',
        args: {'startDate': formatter.format(normalizedMonday)},
      );
    } catch (_) {
      continue;
    }
    if (data is! Map<String, dynamic>) {
      continue;
    }
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
    loadedMondays.add(normalizedMonday);
  }
}

Future<void> _populateInitialSubjectNicks(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  final currentSubjectNicks = <String, String>{
    for (final entry in api.state.settingsState.subjectNicks.entries)
      entry.key: entry.value,
  };
  var changed = false;

  for (final subject in api.state.extractAllSubjects()) {
    if (findStringIgnoreCase(currentSubjectNicks.keys, subject) != null) {
      continue;
    }
    final generatedNick = generateAutomaticSubjectNick(subject);
    if (generatedNick == null) {
      continue;
    }
    currentSubjectNicks[subject] = generatedNick;
    changed = true;
  }

  if (changed) {
    await api.actions.settingsActions.subjectNicks(
      BuiltMap<String, String>(currentSubjectNicks),
    );
  }
  await api.actions.settingsActions.subjectNicksAutoGenerated(true);
}

bool _allKnownSubjectsHavePrimaryTeacher(AppState state) {
  final allSubjects = state.extractAllSubjects();
  if (allSubjects.isEmpty) {
    return false;
  }
  for (final subject in allSubjects) {
    final isLocked = state.settingsState.substitutePrimaryTeachersLockedSubjects
        .any((item) => equalsIgnoreCase(item, subject));
    final resolvedKey = findStringIgnoreCase(
      state.settingsState.substitutePrimaryTeachers.keys,
      subject,
    );
    if (resolvedKey == null) {
      if (isLocked) {
        continue;
      }
      return false;
    }
    final teacher = _singleTeacher(
      state.settingsState.substitutePrimaryTeachers[resolvedKey] ??
          BuiltList<String>(),
    );
    if (teacher == null) {
      if (isLocked) {
        continue;
      }
      return false;
    }
  }
  return true;
}

bool _shouldPrefetchSubstituteTeacherHistory(AppState state) {
  if (state.noInternet || !state.loginState.loggedIn) {
    return false;
  }
  final sessionKey = _substituteTeacherHistorySessionKey(state);
  return !_substituteTeacherHistoryAttemptedKeys.contains(sessionKey) ||
      !_allKnownSubjectsHavePrimaryTeacher(state);
}

bool _sameIgnoreCaseList(
  Iterable<String> current,
  Iterable<String> next,
) {
  final nextList = next.toList();
  final currentList = current.toList();
  if (currentList.length != nextList.length) {
    return false;
  }
  for (final value in currentList) {
    if (!containsStringIgnoreCase(nextList, value)) {
      return false;
    }
  }
  return true;
}

Future<void> _setCalendarSyncCalendarId(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<int?> action) async {
  await next(action);
  if (!api.state.settingsState.calendarSyncEnabled || !isAndroidPlatform) {
    return;
  }
  final success = await CalendarSyncService.reconcile(api.state);
  if (!success) {
    showSnackBar(tr('calendarSync.partialSyncFailure'));
  }
}

Future<void> _removeCalendarSyncEvents(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final success = await CalendarSyncService.deleteTrackedEvents();
  if (!success) {
    showSnackBar(tr('calendarSync.partialDeleteFailure'));
  }
}

Future<void> _reconcileCalendarSync(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action action) async {
  await next(action);
  if (!api.state.settingsState.calendarSyncEnabled) {
    return;
  }
  await CalendarSyncService.reconcile(api.state);
}

Future<void> _setLanguage(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<String> action) async {
  await next(action);
  await appLanguageController.setLanguage(AppLanguage.fromCode(action.payload));
  if (api.state.loginState.loggedIn) {
    final targetLanguage = _preferredServerLanguageForApp(action.payload);
    if (targetLanguage != null) {
      try {
        await wrapper.send(
          'api/profile/updateProfile',
          args: <String, Object?>{
            'language': targetLanguage,
          },
        );
      } catch (_) {
        // Keep local language selection even if the server-side sync fails.
      }
    }
  }
  if (api.state.settingsState.calendarSyncEnabled && isAndroidPlatform) {
    final success = await CalendarSyncService.reconcile(api.state);
    if (!success) {
      showSnackBar(tr('calendarSync.partialSyncFailure'));
    }
  }
}
