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

final _settingsMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(GradesActionsNames.loaded, _updateSubjectThemes)
      ..add(DashboardActionsNames.loaded, _updateSubjectThemes)
      ..add(CalendarActionsNames.loaded, _updateSubjectThemes)
      ..add(DashboardActionsNames.loaded, _reconcileCalendarSync)
      ..add(CalendarActionsNames.loaded, _reconcileCalendarSync)
      ..add(DashboardActionsNames.homeworkAdded, _reconcileCalendarSync)
      ..add(DashboardActionsNames.reminderEdited, _reconcileCalendarSync)
      ..add(DashboardActionsNames.deleteHomework, _reconcileCalendarSync)
      ..add(SettingsActionsNames.setLanguage, _setLanguage)
      ..add(SettingsActionsNames.pushNotificationsEnabled,
          _setPushNotificationsEnabled)
      ..add(SettingsActionsNames.calendarSyncEnabled, _setCalendarSyncEnabled)
      ..add(SettingsActionsNames.removeCalendarSyncEvents,
          _removeCalendarSyncEvents);

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
      "Benachrichtigungen sind nicht erlaubt und wurden deaktiviert.",
    );
    if (api.state.settingsState.pushNotificationsEnabled) {
      await api.actions.settingsActions.pushNotificationsEnabled(false);
    }
  }
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

  final enableResult = await CalendarSyncService.prepareForEnable();
  if (enableResult != CalendarSyncEnableResult.ready) {
    showSnackBar(
      switch (enableResult) {
        CalendarSyncEnableResult.permissionDenied =>
          'Kalenderberechtigung wurde nicht erteilt.',
        CalendarSyncEnableResult.noWritableCalendar =>
          'Kein beschreibbarer Standardkalender gefunden.',
        _ => 'Kalendersynchronisierung ist auf diesem Geraet nicht verfuegbar.',
      },
    );
    if (api.state.settingsState.calendarSyncEnabled) {
      await api.actions.settingsActions.calendarSyncEnabled(false);
    }
    return;
  }

  final success = await CalendarSyncService.reconcile(api.state);
  if (!success) {
    showSnackBar('Kalenderereignisse konnten nicht vollstaendig synchronisiert werden.');
  }
}

Future<void> _removeCalendarSyncEvents(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final success = await CalendarSyncService.deleteTrackedEvents();
  if (!success) {
    showSnackBar('Nicht alle synchronisierten Kalenderereignisse konnten entfernt werden.');
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
}
