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

import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/main.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/settings_page_widget.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class SettingsPageContainer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, SettingsViewModel>(
      builder: (context, vm, actions) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) => SettingsPageWidget(
            vm: vm,
            currentThemePreference: themeController.themePreference,
            platformOverride: themeController.platformOverride,
            onSetThemePreference: themeController.setThemePreference,
            onSetPlatformOverride: themeController.setPlatformOverride,
            onSetLanguage: (language) =>
                actions.settingsActions.setLanguage(language.code),
            onSetNoPassSaving: actions.settingsActions.saveNoPass.call,
            onSetNoDataSaving: actions.settingsActions.saveNoData.call,
            onSetAskWhenDelete:
                actions.settingsActions.askWhenDeleteReminder.call,
            onSetDeleteDataOnLogout:
                actions.settingsActions.deleteDataOnLogout.call,
            onSetSubjectNicks: (map) =>
                actions.settingsActions.subjectNicks(BuiltMap(map)),
            onSetShowCalendarEditNicksBar:
                actions.settingsActions.showCalendarSubjectNicksBar.call,
            onSetShowGradesDiagram:
                actions.settingsActions.showGradesDiagram.call,
            onSetShowAllSubjectsAverage:
                actions.settingsActions.showAllSubjectsAverage.call,
            onSetDashboardMarkNewOrChangedEntries:
                actions.settingsActions.markNotSeenDashboardEntries.call,
            onSetDashboardDeduplicateEntries:
                actions.settingsActions.deduplicateDashboardEntries.call,
            onShowProfile: actions.routingActions.showProfile.call,
            onSetIgnoreForGradesAverage: (list) => actions.settingsActions
                .ignoreSubjectsForAverage(BuiltList(list)),
            onSetFavoriteSubjects: (list) =>
                actions.settingsActions.favoriteSubjects(BuiltList(list)),
            onSetDashboardColorBorders:
                actions.settingsActions.dashboardColorBorders.call,
            onSetCalenderColorBackground:
                actions.settingsActions.calendarColorBackground.call,
            onSetDashboardColorTestsInRed:
                actions.settingsActions.dashboardColorTestsInRed.call,
            onSetPushNotificationsEnabled:
                actions.settingsActions.pushNotificationsEnabled.call,
            onSetSubstituteDetectionEnabled: (enabled) async {
              await actions.settingsActions.substituteDetectionEnabled(enabled);
              await actions.calendarActions.recalculateSubstitutes(
                _substituteDetectionConfig(
                  enabled: enabled,
                  primaryTeachers: vm.substitutePrimaryTeachers,
                  lockedSubjects: vm.substitutePrimaryTeachersLockedSubjects,
                ),
              );
            },
            onSetSubstitutePrimaryTeachers: (map) async {
              final normalized = _normalizedSubstitutePrimaryTeachers(
                vm.allSubjects,
                map,
              );
              await actions.settingsActions.substitutePrimaryTeachers(
                BuiltMap(normalized.map(
                  (key, value) => MapEntry(key, BuiltList<String>.from(value)),
                )),
              );
              await actions.calendarActions.recalculateSubstitutes(
                _substituteDetectionConfig(
                  enabled: vm.substituteDetectionEnabled,
                  primaryTeachers: normalized,
                  lockedSubjects: vm.substitutePrimaryTeachersLockedSubjects,
                ),
              );
            },
            onSetSubstituteKnownTeachers: (teachers) => actions.settingsActions
                .substituteKnownTeachers(BuiltList<String>.from(teachers)),
            onSetSubstitutePrimaryTeachersLockedSubjects: (subjects) =>
                actions.settingsActions.substitutePrimaryTeachersLockedSubjects(
              BuiltList<String>.from(subjects),
            ),
            onSetCalendarSyncEnabled:
                actions.settingsActions.calendarSyncEnabled.call,
            onSetCalendarSyncCalendarId:
                actions.settingsActions.calendarSyncCalendarId.call,
            onRemoveCalendarSyncEvents:
                actions.settingsActions.removeCalendarSyncEvents.call,
            onSetAmoledMode: actions.settingsActions.amoledMode.call,
            onSetSubjectTheme: actions.settingsActions.setSubjectTheme.call,
            onSetContrastColor: (color) {
              unawaited(setGlobalContrastColor(color));
            },
          ),
        );
      },
      connect: (state) {
        return SettingsViewModel(state);
      },
    );
  }
}

typedef OnSettingChanged<T> = void Function(T newValue);

class SettingsViewModel {
  final Map<String, String> subjectNicks;
  final bool noPassSaving;
  final AppLanguage language;
  final bool noDataSaving;
  final bool askWhenDelete;
  final bool deleteDataOnLogout;
  final bool showCalendarEditNicksBar;
  final bool showGradesDiagram;
  final bool showAllSubjectsAverage;
  final bool dashboardMarkNewOrChangedEntries;
  final bool dashboardDeduplicateEntries;
  final bool showSubjectNicks;
  final bool showGradesSettings;
  final bool showCalendarSubstituteSettings;
  final bool dashboardColorBorders;
  final bool calendarColorBackground;
  final bool dashboardColorTestsInRed;
  final bool pushNotificationsEnabled;
  final bool substituteDetectionEnabled;
  final bool calendarSyncEnabled;
  final int? calendarSyncCalendarId;
  final bool amoledMode;
  final bool demoMode;
  final List<String> allSubjects;
  final List<String> ignoreForGradesAverage;
  final List<String> favoriteSubjects;
  final Map<String, List<String>> substitutePrimaryTeachers;
  final List<String> substitutePrimaryTeachersLockedSubjects;
  final List<String> allTeachers;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  SettingsViewModel(AppState state)
      : language = AppLanguage.fromCode(state.settingsState.languageCode),
        noPassSaving = state.settingsState.noPasswordSaving,
        noDataSaving = state.settingsState.noDataSaving,
        askWhenDelete = state.settingsState.askWhenDelete,
        deleteDataOnLogout = state.settingsState.deleteDataOnLogout,
        subjectNicks = state.settingsState.subjectNicks.toMap(),
        showSubjectNicks = state.settingsState.scrollToSubjectNicks,
        showGradesSettings = state.settingsState.scrollToGrades,
        showCalendarSubstituteSettings =
            state.settingsState.scrollToCalendarSubstituteSettings,
        showCalendarEditNicksBar = state.settingsState.showCalendarNicksBar,
        showGradesDiagram = state.settingsState.showGradesDiagram,
        showAllSubjectsAverage = state.settingsState.showAllSubjectsAverage,
        dashboardMarkNewOrChangedEntries =
            state.settingsState.dashboardMarkNewOrChangedEntries,
        dashboardDeduplicateEntries =
            state.settingsState.dashboardDeduplicateEntries,
        dashboardColorBorders = state.settingsState.dashboardColorBorders,
        calendarColorBackground = state.settingsState.calendarColorBackground,
        dashboardColorTestsInRed = state.settingsState.dashboardColorTestsInRed,
        pushNotificationsEnabled = state.settingsState.pushNotificationsEnabled,
        substituteDetectionEnabled =
            state.settingsState.substituteDetectionEnabled,
        calendarSyncEnabled = state.settingsState.calendarSyncEnabled,
        calendarSyncCalendarId = state.settingsState.calendarSyncCalendarId,
        amoledMode = state.settingsState.amoledMode,
        allSubjects = _sortedIgnoreCase(state.extractAllSubjects()),
        allTeachers = _mergedTeachers(
          state.extractAllTeachers(),
          state.settingsState.substituteKnownTeachers.toList(),
        ),
        ignoreForGradesAverage =
            state.settingsState.ignoreForGradesAverage.toList(),
        favoriteSubjects = state.settingsState.favoriteSubjects.toList(),
        substitutePrimaryTeachers = _normalizedSubstitutePrimaryTeachers(
          state.extractAllSubjects(),
          {
            for (final entry
                in state.settingsState.substitutePrimaryTeachers.entries)
              entry.key: entry.value.toList(),
          },
        ),
        substitutePrimaryTeachersLockedSubjects = state
            .settingsState.substitutePrimaryTeachersLockedSubjects
            .toList(),
        subjectThemes = state.settingsState.subjectThemes,
        demoMode = state.isDemo;
}

List<String> _mergedTeachers(
  List<String> extractedTeachers,
  List<String> storedTeachers,
) {
  final merged = <String>[];
  for (final teacher in [...extractedTeachers, ...storedTeachers]) {
    if (!merged.any((existing) => equalsIgnoreCase(existing, teacher))) {
      merged.add(teacher);
    }
  }
  return _sortedIgnoreCase(merged);
}

Map<String, List<String>> _normalizedSubstitutePrimaryTeachers(
  Iterable<String> allSubjects,
  Map<String, List<String>> primaryTeachers,
) {
  final normalized = <String, List<String>>{};
  final orderedSubjects = _sortedIgnoreCase({
    ...allSubjects,
    ...primaryTeachers.keys,
  });
  for (final subject in orderedSubjects) {
    final resolvedKey = findStringIgnoreCase(primaryTeachers.keys, subject);
    final teachers = resolvedKey == null
        ? const <String>[]
        : _normalizeTeacherList(primaryTeachers[resolvedKey] ?? const []);
    normalized[resolvedKey ?? subject] = teachers;
  }
  return normalized;
}

List<String> _normalizeTeacherList(Iterable<String> teachers) {
  final normalized = <String>[];
  for (final teacher in teachers) {
    if (teacher.trim().isEmpty) {
      continue;
    }
    if (!containsStringIgnoreCase(normalized, teacher)) {
      normalized.add(teacher);
    }
  }
  return normalized;
}

List<String> _sortedIgnoreCase(Iterable<String> values) {
  final result = values.toList();
  result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

SubstituteDetectionConfig _substituteDetectionConfig({
  required bool enabled,
  required Map<String, List<String>> primaryTeachers,
  required List<String> lockedSubjects,
}) {
  return SubstituteDetectionConfig(
    (b) => b
      ..enabled = enabled
      ..primaryTeachers = MapBuilder<String, BuiltList<String>>(
        primaryTeachers.map(
          (key, value) => MapEntry(key, BuiltList<String>.from(value)),
        ),
      )
      ..lockedSubjects = ListBuilder<String>(lockedSubjects),
  );
}
