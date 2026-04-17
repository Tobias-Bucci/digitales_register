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

  final settings = api.state.settingsState;
  final detectedPrimaryTeachers =
      _detectPrimaryTeachersFromCalendar(api.state.calendarState.days.toMap());
  final lockedSubjects = settings.substitutePrimaryTeachersLockedSubjects;
  final mergedPrimaryTeachers = <String, List<String>>{
    for (final entry in settings.substitutePrimaryTeachers.entries)
      entry.key: entry.value.toList(),
  };

  for (final subject in api.state.extractAllSubjects()) {
    if (lockedSubjects.any((item) => equalsIgnoreCase(item, subject))) {
      continue;
    }

    final resolvedSubject =
        findStringIgnoreCase(mergedPrimaryTeachers.keys, subject) ?? subject;
    final mergedTeachers = <String>[
      ...?mergedPrimaryTeachers[resolvedSubject],
    ];
    final detectedTeachers = detectedPrimaryTeachers.entries
        .firstWhere(
          (entry) => equalsIgnoreCase(entry.key, subject),
          orElse: () => const MapEntry<String, List<String>>('', <String>[]),
        )
        .value;
    for (final teacher in detectedTeachers) {
      if (!containsStringIgnoreCase(mergedTeachers, teacher)) {
        mergedTeachers.add(teacher);
      }
    }
    mergedPrimaryTeachers[resolvedSubject] = mergedTeachers;
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
  await api.actions.calendarActions.recalculateSubstitutes(
    SubstituteDetectionConfig(
      (b) => b
        ..enabled = api.state.settingsState.substituteDetectionEnabled
        ..primaryTeachers =
            api.state.settingsState.substitutePrimaryTeachers.toBuilder(),
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

Map<String, List<String>> _detectPrimaryTeachersFromCalendar(
  Map<UtcDateTime, CalendarDay> days,
) {
  final teacherCountsBySlot = <String, Map<String, int>>{};

  for (final entry in days.entries) {
    for (final hour in entry.value.hours) {
      if (hour.teachers.length != 1) {
        continue;
      }
      final teacherName = hour.teachers.single.fullName;
      if (teacherName.trim().isEmpty) {
        continue;
      }
      for (var lessonHour = hour.fromHour;
          lessonHour <= hour.toHour;
          lessonHour++) {
        final slotKey = _slotKeyForLessonHour(entry.key, hour, lessonHour);
        final teacherCounts =
            teacherCountsBySlot.putIfAbsent(slotKey, () => <String, int>{});
        final resolvedTeacher =
            findStringIgnoreCase(teacherCounts.keys, teacherName) ??
                teacherName;
        teacherCounts.update(
          resolvedTeacher,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  final detectedBySubject = <String, List<String>>{};
  for (final entry in days.entries) {
    for (final hour in entry.value.hours) {
      if (hour.teachers.length != 1) {
        continue;
      }
      final teacherName = hour.teachers.single.fullName;
      if (teacherName.trim().isEmpty) {
        continue;
      }
      var matchesStableBaseline = false;
      for (var lessonHour = hour.fromHour;
          lessonHour <= hour.toHour;
          lessonHour++) {
        final slotKey = _slotKeyForLessonHour(entry.key, hour, lessonHour);
        final teacherCounts = teacherCountsBySlot[slotKey];
        if (teacherCounts == null || teacherCounts.length < 2) {
          continue;
        }
        final sortedCounts = teacherCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final leader = sortedCounts.first;
        final runnerUpCount =
            sortedCounts.length > 1 ? sortedCounts[1].value : 0;
        if (leader.value >= 2 &&
            leader.value > runnerUpCount &&
            equalsIgnoreCase(leader.key, teacherName)) {
          matchesStableBaseline = true;
          break;
        }
      }
      if (!matchesStableBaseline) {
        continue;
      }
      final subject =
          findStringIgnoreCase(detectedBySubject.keys, hour.subject) ??
              hour.subject;
      final teachers = detectedBySubject.putIfAbsent(subject, () => <String>[]);
      if (!containsStringIgnoreCase(teachers, teacherName)) {
        teachers.add(teacherName);
      }
    }
  }

  return detectedBySubject;
}

String _slotKeyForLessonHour(
  UtcDateTime date,
  CalendarHour hour,
  int lessonHour,
) {
  final classPart = hour.classId?.toString() ?? hour.className ?? '';
  final subjectPart = hour.subjectId?.toString() ?? hour.subject;
  return '$classPart|$subjectPart|${date.weekday}|$lessonHour';
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
