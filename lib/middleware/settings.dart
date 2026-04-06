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
      ..add(SettingsActionsNames.setLanguage, _setLanguage)
      ..add(SettingsActionsNames.pushNotificationsEnabled,
          _setPushNotificationsEnabled);

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

Future<void> _setLanguage(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<String> action) async {
  await next(action);
  await appLanguageController.setLanguage(AppLanguage.fromCode(action.payload));
}
