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
  ..add(
      SettingsActionsNames.substitutePrimaryTeachers, _recalculateSubstitutes)
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
