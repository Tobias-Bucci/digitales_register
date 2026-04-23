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

import 'dart:io';

import 'package:built_collection/built_collection.dart';
import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/app_state.dart';
import 'package:dr/app_subject_translation_controller.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/autocomplete_options.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/donations.dart';
import 'package:dr/ui/network_protocol_page.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

enum _Theme {
  light,
  dark,
  amoled,
  followDevice,
}

class SettingsPageWidget extends StatefulWidget {
  final OnSettingChanged<bool> onSetNoPassSaving;
  final OnSettingChanged<bool> onSetNoDataSaving;
  final OnSettingChanged<bool> onSetAskWhenDelete;
  final OnSettingChanged<bool> onSetDeleteDataOnLogout;
  final OnSettingChanged<bool> onSetShowCalendarEditNicksBar;
  final OnSettingChanged<bool> onSetShowGradesDiagram;
  final OnSettingChanged<bool> onSetShowAllSubjectsAverage;
  final OnSettingChanged<bool> onSetDashboardMarkNewOrChangedEntries;
  final OnSettingChanged<bool> onSetDashboardDeduplicateEntries;
  final OnSettingChanged<AppThemePreference> onSetThemePreference;
  final OnSettingChanged<AppLanguage> onSetLanguage;
  final OnSettingChanged<bool> onSetPlatformOverride;
  final OnSettingChanged<bool> onSetDashboardColorBorders;
  final OnSettingChanged<bool> onSetCalenderColorBackground;
  final OnSettingChanged<bool> onSetDashboardColorTestsInRed;
  final OnSettingChanged<bool> onSetPushNotificationsEnabled;
  final OnSettingChanged<bool> onSetSubstituteDetectionEnabled;
  final OnSettingChanged<Map<String, List<String>>>
      onSetSubstitutePrimaryTeachers;
  final OnSettingChanged<List<String>> onSetSubstituteKnownTeachers;
  final OnSettingChanged<List<String>>
      onSetSubstitutePrimaryTeachersLockedSubjects;
  final Future<void> Function(bool enabled) onSetCalendarSyncEnabled;
  final Future<void> Function(int? calendarId) onSetCalendarSyncCalendarId;
  final Future<void> Function() onRemoveCalendarSyncEvents;
  final OnSettingChanged<bool> onSetAmoledMode;
  final OnSettingChanged<Color> onSetContrastColor;
  final OnSettingChanged<MapEntry<String, SubjectTheme>> onSetSubjectTheme;
  final OnSettingChanged<Map<String, String>> onSetSubjectNicks;
  final OnSettingChanged<List<String>> onSetIgnoreForGradesAverage;
  final OnSettingChanged<List<String>> onSetFavoriteSubjects;
  final VoidCallback onShowProfile;
  final SettingsViewModel vm;
  final AppThemePreference currentThemePreference;
  final bool platformOverride;

  const SettingsPageWidget({
    super.key,
    required this.onSetNoPassSaving,
    required this.onSetNoDataSaving,
    required this.onSetAskWhenDelete,
    required this.onSetDeleteDataOnLogout,
    required this.onSetShowCalendarEditNicksBar,
    required this.onSetShowGradesDiagram,
    required this.onSetShowAllSubjectsAverage,
    required this.onSetDashboardMarkNewOrChangedEntries,
    required this.onSetDashboardDeduplicateEntries,
    required this.onSetThemePreference,
    required this.onSetLanguage,
    required this.onSetSubjectNicks,
    required this.vm,
    required this.onSetPlatformOverride,
    required this.onShowProfile,
    required this.onSetIgnoreForGradesAverage,
    required this.onSetDashboardColorBorders,
    required this.onSetCalenderColorBackground,
    required this.onSetSubjectTheme,
    required this.onSetDashboardColorTestsInRed,
    required this.onSetPushNotificationsEnabled,
    required this.onSetSubstituteDetectionEnabled,
    required this.onSetSubstitutePrimaryTeachers,
    required this.onSetSubstituteKnownTeachers,
    required this.onSetSubstitutePrimaryTeachersLockedSubjects,
    required this.onSetCalendarSyncEnabled,
    required this.onSetCalendarSyncCalendarId,
    required this.onRemoveCalendarSyncEvents,
    required this.onSetAmoledMode,
    required this.onSetContrastColor,
    required this.onSetFavoriteSubjects,
    required this.currentThemePreference,
    required this.platformOverride,
  });

  @override
  _SettingsPageWidgetState createState() => _SettingsPageWidgetState();
}

class _SettingsPageWidgetState extends State<SettingsPageWidget> {
  late bool _translateSubjectsEnabled;
  late Future<List<CalendarSyncCalendar>> _calendarSyncCalendarsFuture;
  bool _handledSubjectNicksIntent = false;
  bool _handledGradesIntent = false;
  bool _handledCalendarSubstituteIntent = false;

  List<String> get subjectsWithoutNick => widget.vm.allSubjects
      .where((element) => !widget.vm.subjectNicks.keys.contains(element))
      .toList();
  List<String> get notYetIgnoredForAverageSubjects => widget.vm.allSubjects
      .where((element) => !widget.vm.ignoreForGradesAverage.contains(element))
      .toList();
  List<String> get notYetFavoriteSubjects => widget.vm.allSubjects
      .where(
        (element) =>
            !containsSubjectIgnoreCase(widget.vm.favoriteSubjects, element),
      )
      .toList();

  @override
  void initState() {
    _translateSubjectsEnabled = appSubjectTranslationController.enabled;
    _calendarSyncCalendarsFuture = _loadCalendarSyncCalendars();
    super.initState();
    _handleScrollIntents();
  }

  @override
  void didUpdateWidget(covariant SettingsPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.vm.showSubjectNicks) {
      _handledSubjectNicksIntent = false;
    }
    if (!widget.vm.showGradesSettings) {
      _handledGradesIntent = false;
    }
    if (!widget.vm.showCalendarSubstituteSettings) {
      _handledCalendarSubstituteIntent = false;
    }
    _handleScrollIntents();
  }

  void _handleScrollIntents() {
    if (widget.vm.showSubjectNicks && !_handledSubjectNicksIntent) {
      _handledSubjectNicksIntent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _openSubjectNicksPage(showAddDialogOnStart: true);
      });
    }
    if (widget.vm.showGradesSettings && !_handledGradesIntent) {
      _handledGradesIntent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _openGradesSettingsPage();
      });
    }
    if (widget.vm.showCalendarSubstituteSettings &&
        !_handledCalendarSubstituteIntent) {
      _handledCalendarSubstituteIntent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _openSubstituteSettingsPage();
      });
    }
  }

  void _applySubstituteTeachersUpdate(
    Map<String, List<String>> updated, {
    Iterable<String> manuallyLockedSubjects = const <String>[],
  }) {
    widget.onSetSubstitutePrimaryTeachers(updated);
    if (manuallyLockedSubjects.isEmpty) {
      return;
    }
    final lockedSubjects = <String>[
      ...widget.vm.substitutePrimaryTeachersLockedSubjects,
    ];
    for (final subject in manuallyLockedSubjects) {
      if (!containsSubjectIgnoreCase(lockedSubjects, subject)) {
        lockedSubjects.add(subject);
      }
    }
    widget.onSetSubstitutePrimaryTeachersLockedSubjects(lockedSubjects);
  }

  Future<List<CalendarSyncCalendar>> _loadCalendarSyncCalendars() {
    return CalendarSyncService.loadWritableCalendars();
  }

  void _refreshCalendarSyncCalendars() {
    setState(() {
      _calendarSyncCalendarsFuture = _loadCalendarSyncCalendars();
    });
  }

  void _showCalendarSyncError(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAddTeacherDialog(String subject) async {
    final l10n = context.l10n;
    final teacher = await showDialog<String>(
      context: context,
      builder: (context) => AddSubject(
        availableSubjects: widget.vm.allTeachers,
        title: l10n.text('settings.calendar.substituteTeachers.addTeacher'),
      ),
    );
    if (teacher == null) {
      return;
    }

    final updatedSubjects =
        Map<String, List<String>>.from(widget.vm.substitutePrimaryTeachers);
    final resolvedSubject =
        findStringIgnoreCase(updatedSubjects.keys, subject) ?? subject;
    final updatedTeachers = <String>[
      ...updatedSubjects[resolvedSubject] ?? const <String>[],
    ];
    if (!containsStringIgnoreCase(updatedTeachers, teacher)) {
      updatedTeachers.add(teacher);
    }
    updatedSubjects[resolvedSubject] = updatedTeachers;
    _applySubstituteTeachersUpdate(
      updatedSubjects,
      manuallyLockedSubjects: [resolvedSubject],
    );

    final knownTeachers = <String>[...widget.vm.allTeachers];
    if (!containsStringIgnoreCase(knownTeachers, teacher)) {
      knownTeachers.add(teacher);
      widget.onSetSubstituteKnownTeachers(knownTeachers);
    }
  }

  String _calendarSyncMessageForResult(
    AppLocalizations l10n,
    CalendarSyncEnableResult result,
  ) {
    return switch (result) {
      CalendarSyncEnableResult.permissionDenied => l10n.text(
          'calendarSync.permissionDenied',
        ),
      CalendarSyncEnableResult.noWritableCalendar => l10n.text(
          'calendarSync.noWritableCalendar',
        ),
      _ => l10n.text('calendarSync.unavailable'),
    };
  }

  Future<CalendarSyncCalendar?> _showCalendarSyncCalendarDialog(
    List<CalendarSyncCalendar> calendars,
  ) {
    final defaultCalendar = calendars.firstWhere(
      (calendar) => calendar.isPrimary,
      orElse: () => calendars.first,
    );
    var selectedId = widget.vm.calendarSyncCalendarId ?? defaultCalendar.id;
    final l10n = context.l10n;
    return showDialog<CalendarSyncCalendar>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => InfoDialog(
          title: Text(l10n.text('settings.calendarSync.select.title')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.text('settings.calendarSync.select.subtitle'),
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<int>(
                    groupValue: selectedId,
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedId = value;
                      });
                    },
                    child: Column(
                      children: [
                        for (final calendar in calendars)
                          RadioListTile<int>(
                            value: calendar.id,
                            contentPadding: EdgeInsets.zero,
                            title: Text(calendar.displayName),
                            subtitle: Text(calendar.accountLabel),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.text('common.cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(
                calendars.firstWhere((calendar) => calendar.id == selectedId),
              ),
              child: Text(l10n.text('common.select')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableCalendarSync() async {
    final l10n = context.l10n;
    final enableResult = await CalendarSyncService.prepareForEnable();
    if (!mounted) {
      return;
    }
    if (enableResult != CalendarSyncEnableResult.ready) {
      _showCalendarSyncError(_calendarSyncMessageForResult(l10n, enableResult));
      return;
    }

    final calendars = await CalendarSyncService.loadWritableCalendars();
    if (!mounted) {
      return;
    }
    if (calendars.isEmpty) {
      _showCalendarSyncError(
        l10n.text('calendarSync.noWritableCalendar'),
      );
      return;
    }

    final selectedCalendar = await _showCalendarSyncCalendarDialog(calendars);
    if (!mounted || selectedCalendar == null) {
      return;
    }

    await widget.onSetCalendarSyncCalendarId(selectedCalendar.id);
    await widget.onSetCalendarSyncEnabled(true);
    _refreshCalendarSyncCalendars();
  }

  Future<void> _changeCalendarSyncCalendar() async {
    final calendars = await _calendarSyncCalendarsFuture;
    if (!mounted || calendars.isEmpty) {
      return;
    }
    final selectedCalendar = await _showCalendarSyncCalendarDialog(calendars);
    if (!mounted || selectedCalendar == null) {
      return;
    }
    await widget.onSetCalendarSyncCalendarId(selectedCalendar.id);
    _refreshCalendarSyncCalendars();
  }

  void _selectTheme(_Theme? theme) {
    switch (theme!) {
      case _Theme.light:
        widget.onSetThemePreference(AppThemePreference.light);
        widget.onSetAmoledMode(false);
      case _Theme.dark:
        widget.onSetThemePreference(AppThemePreference.dark);
        widget.onSetAmoledMode(false);
      case _Theme.amoled:
        widget.onSetThemePreference(AppThemePreference.dark);
        widget.onSetAmoledMode(true);
      case _Theme.followDevice:
        widget.onSetThemePreference(AppThemePreference.system);
        widget.onSetAmoledMode(false);
    }
  }

  Future<void> _openSubjectColorsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SubjectColorsSettingsPage(
          subjectThemes: widget.vm.subjectThemes,
          dashboardColorBorders: widget.vm.dashboardColorBorders,
          calendarColorBackground: widget.vm.calendarColorBackground,
          dashboardColorTestsInRed: widget.vm.dashboardColorTestsInRed,
          onSetSubjectTheme: widget.onSetSubjectTheme,
          onSetDashboardColorBorders: widget.onSetDashboardColorBorders,
          onSetCalenderColorBackground: widget.onSetCalenderColorBackground,
          onSetDashboardColorTestsInRed: widget.onSetDashboardColorTestsInRed,
        ),
      ),
    );
  }

  Future<void> _openGradesSettingsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _GradesSettingsPage(
          showGradesDiagram: widget.vm.showGradesDiagram,
          showAllSubjectsAverage: widget.vm.showAllSubjectsAverage,
          allSubjects: widget.vm.allSubjects,
          ignoreForGradesAverage: widget.vm.ignoreForGradesAverage,
          onSetShowGradesDiagram: widget.onSetShowGradesDiagram,
          onSetShowAllSubjectsAverage: widget.onSetShowAllSubjectsAverage,
          onSetIgnoreForGradesAverage: widget.onSetIgnoreForGradesAverage,
        ),
      ),
    );
  }

  Future<void> _openSubjectNicksPage({
    bool showAddDialogOnStart = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SubjectNicksSettingsPage(
          subjectNicks: widget.vm.subjectNicks,
          allSubjects: widget.vm.allSubjects,
          showCalendarEditNicksBar: widget.vm.showCalendarEditNicksBar,
          onSetSubjectNicks: widget.onSetSubjectNicks,
          onSetShowCalendarEditNicksBar: widget.onSetShowCalendarEditNicksBar,
          showAddDialogOnStart: showAddDialogOnStart,
        ),
      ),
    );
  }

  Future<void> _openSubstituteSettingsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _SubstituteSettingsPage(
          substituteDetectionEnabled: widget.vm.substituteDetectionEnabled,
          substitutePrimaryTeachers: widget.vm.substitutePrimaryTeachers,
          lockedSubjects: widget.vm.substitutePrimaryTeachersLockedSubjects,
          allSubjects: widget.vm.allSubjects,
          allTeachers: widget.vm.allTeachers,
          onSetSubstituteDetectionEnabled:
              widget.onSetSubstituteDetectionEnabled,
          onSetSubstitutePrimaryTeachers: widget.onSetSubstitutePrimaryTeachers,
          onSetSubstituteKnownTeachers: widget.onSetSubstituteKnownTeachers,
          onSetSubstitutePrimaryTeachersLockedSubjects:
              widget.onSetSubstitutePrimaryTeachersLockedSubjects,
        ),
      ),
    );
  }

  Future<void> _openFavoriteSubjectsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _FavoriteSubjectsSettingsPage(
          favoriteSubjects: widget.vm.favoriteSubjects,
          allSubjects: widget.vm.allSubjects,
          onSetFavoriteSubjects: widget.onSetFavoriteSubjects,
        ),
      ),
    );
  }

  Future<void> _openCalendarSyncDetailsPage() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CalendarSyncSettingsDetailPage(
          calendarSyncEnabled: widget.vm.calendarSyncEnabled,
          calendarSyncCalendarId: widget.vm.calendarSyncCalendarId,
          calendarsFuture: _calendarSyncCalendarsFuture,
          onChangeCalendar: _changeCalendarSyncCalendar,
          onRemoveCalendarSyncEvents: widget.onRemoveCalendarSyncEvents,
        ),
      ),
    );
  }

  String _favoriteSubjectsSummary(AppLocalizations l10n) {
    if (widget.vm.favoriteSubjects.isEmpty) {
      return l10n.text('settings.calendar.noFavoriteSubject');
    }
    return widget.vm.favoriteSubjects.join(', ');
  }

  String _gradesSummary() {
    return [
      if (widget.vm.showGradesDiagram) 'Diagramm',
      if (widget.vm.showAllSubjectsAverage) 'Durchschnitt',
      if (widget.vm.ignoreForGradesAverage.isNotEmpty)
        '${widget.vm.ignoreForGradesAverage.length} ausgeblendet',
    ].join(' | ');
  }

  Widget _buildAccountSection(AppLocalizations l10n) {
    return _SettingsSectionCard(
      title: l10n.text('settings.section.auth'),
      children: [
        if (!widget.vm.demoMode)
          ListTile(
            title: Text(l10n.text('settings.section.profile')),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onShowProfile,
          ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.keepLoggedIn.title')),
          subtitle: Text(l10n.text('settings.keepLoggedIn.subtitle')),
          onChanged: (bool value) {
            widget.onSetNoPassSaving(!value);
          },
          value: !widget.vm.noPassSaving,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.storeData.title')),
          subtitle: Text(l10n.text('settings.storeData.subtitle')),
          onChanged: (bool value) {
            widget.onSetNoDataSaving(!value);
          },
          value: !widget.vm.noDataSaving,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.deleteDataOnLogout.title')),
          onChanged: !widget.vm.noPassSaving && !widget.vm.noDataSaving
              ? (bool value) {
                  widget.onSetDeleteDataOnLogout(value);
                }
              : null,
          value: widget.vm.deleteDataOnLogout,
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(AppLocalizations l10n, _Theme currentTheme) {
    return _SettingsSectionCard(
      title: l10n.text('settings.section.appearance'),
      children: [
        RadioGroup<_Theme>(
          groupValue: currentTheme,
          onChanged: _selectTheme,
          child: Column(
            children: [
              RadioListTile(
                value: _Theme.followDevice,
                title: Text(l10n.text('settings.theme.followDevice')),
              ),
              RadioListTile(
                value: _Theme.light,
                title: Text(l10n.text('settings.theme.light')),
              ),
              RadioListTile(
                value: _Theme.dark,
                title: Text(l10n.text('settings.theme.dark')),
              ),
              RadioListTile(
                value: _Theme.amoled,
                title: Text(l10n.text('settings.theme.amoled')),
              ),
            ],
          ),
        ),
        ListTile(
          key: const Key('settings-language-tile'),
          title: Text(l10n.text('settings.language.label')),
          trailing: SizedBox(
            width: 160,
            child: DropdownButton<AppLanguage>(
              key: const Key('settings-language-dropdown'),
              isExpanded: true,
              value: widget.vm.language,
              onChanged: (language) {
                if (language != null) {
                  widget.onSetLanguage(language);
                }
              },
              items: [
                DropdownMenuItem(
                  value: AppLanguage.de,
                  child: Text(l10n.text('settings.language.de')),
                ),
                DropdownMenuItem(
                  value: AppLanguage.it,
                  child: Text(l10n.text('settings.language.it')),
                ),
                DropdownMenuItem(
                  value: AppLanguage.lld,
                  child: Text(l10n.text('settings.language.lld')),
                ),
                DropdownMenuItem(
                  value: AppLanguage.en,
                  child: Text(l10n.text('settings.language.en')),
                ),
              ],
            ),
          ),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.subjectTranslation.title')),
          subtitle: Text(l10n.text('settings.subjectTranslation.subtitle')),
          value: _translateSubjectsEnabled,
          onChanged: (enabled) async {
            setState(() {
              _translateSubjectsEnabled = enabled;
            });
            await appSubjectTranslationController.setEnabled(enabled);
            if (enabled) {
              widget.onSetSubjectNicks(const {});
            } else {
              widget.onSetSubjectNicks(Map.of(defaultSubjectNicks));
            }
          },
        ),
        ListTile(
          title: Text(l10n.text('settings.contrastColor.title')),
          subtitle: Text(l10n.text('settings.contrastColor.subtitle')),
          trailing: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
            ),
          ),
          onTap: () async {
            final color = await showDialog<Color>(
              context: context,
              builder: (context) => _ColorPicker(
                initialColor: Theme.of(context).colorScheme.primary,
              ),
            );
            if (color != null) {
              widget.onSetContrastColor(color);
            }
          },
        ),
        ListTile(
          key: const Key('settings-subject-colors-tile'),
          title: Text(l10n.text('settings.subjectColors.title')),
          subtitle: Text('${widget.vm.subjectThemes.length}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _openSubjectColorsPage();
          },
        ),
      ],
    );
  }

  Widget _buildDashboardSection(AppLocalizations l10n) {
    return _SettingsSectionCard(
      title: l10n.text('settings.section.dashboard'),
      children: [
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.pushNotifications.title')),
          subtitle: Text(l10n.text('settings.pushNotifications.subtitle')),
          onChanged: widget.onSetPushNotificationsEnabled,
          value: widget.vm.pushNotificationsEnabled,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.dashboard.markChanged')),
          onChanged: widget.onSetDashboardMarkNewOrChangedEntries,
          value: widget.vm.dashboardMarkNewOrChangedEntries,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.dashboard.deduplicate')),
          onChanged: widget.onSetDashboardDeduplicateEntries,
          value: widget.vm.dashboardDeduplicateEntries,
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.text('settings.dashboard.askDeleteReminder')),
          onChanged: widget.onSetAskWhenDelete,
          value: widget.vm.askWhenDelete,
        ),
        ListTile(
          key: const Key('settings-grades-tile'),
          title: Text(l10n.text('settings.section.grades')),
          subtitle: Text(
            _gradesSummary().isEmpty
                ? l10n.text('settings.grades.noExcludedSubject')
                : _gradesSummary(),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _openGradesSettingsPage();
          },
        ),
      ],
    );
  }

  Widget _buildCalendarSection(AppLocalizations l10n) {
    return _SettingsSectionCard(
      title: l10n.text('settings.section.calendar'),
      children: [
        if (isAndroidPlatform)
          SwitchListTile.adaptive(
            key: const Key('calendar-sync-toggle'),
            title: Text(l10n.text('settings.calendarSync.title')),
            subtitle: Text(l10n.text('settings.calendarSync.subtitle')),
            value: widget.vm.calendarSyncEnabled,
            onChanged: (enabled) async {
              if (enabled) {
                await _enableCalendarSync();
                return;
              }

              final disableAction = await _showCalendarSyncDisableDialog(
                context,
              );
              if (disableAction == null) {
                return;
              }

              await widget.onSetCalendarSyncEnabled(false);
              if (disableAction == _CalendarSyncDisableAction.remove) {
                await widget.onRemoveCalendarSyncEvents();
              }
            },
          ),
        if (isAndroidPlatform)
          FutureBuilder<List<CalendarSyncCalendar>>(
            future: _calendarSyncCalendarsFuture,
            builder: (context, snapshot) {
              final calendars = snapshot.data ?? const <CalendarSyncCalendar>[];
              CalendarSyncCalendar? selectedCalendar;
              for (final calendar in calendars) {
                if (calendar.id == widget.vm.calendarSyncCalendarId) {
                  selectedCalendar = calendar;
                  break;
                }
              }
              selectedCalendar ??= calendars.isEmpty
                  ? null
                  : calendars.firstWhere(
                      (calendar) => calendar.isPrimary,
                      orElse: () => calendars.first,
                    );
              return ListTile(
                key: const Key('settings-calendar-sync-details-tile'),
                enabled: widget.vm.calendarSyncEnabled,
                title: Text(l10n.text('settings.calendarSync.select.title')),
                subtitle: Text(
                  !widget.vm.calendarSyncEnabled
                      ? l10n.text('settings.calendarSync.subtitle')
                      : selectedCalendar == null
                          ? l10n.text('settings.calendarSync.select.none')
                          : '${selectedCalendar.displayName}\n${selectedCalendar.accountLabel}',
                ),
                isThreeLine:
                    widget.vm.calendarSyncEnabled && selectedCalendar != null,
                trailing: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: widget.vm.calendarSyncEnabled
                    ? () async {
                        await _openCalendarSyncDetailsPage();
                      }
                    : null,
              );
            },
          ),
        ListTile(
          key: const Key('settings-subject-nicks-tile'),
          title: Text(l10n.text('settings.calendar.subjectNicks')),
          subtitle: Text(
            widget.vm.subjectNicks.isEmpty
                ? l10n.text('settings.calendar.subjectNicksHintBody')
                : '${widget.vm.subjectNicks.length}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _openSubjectNicksPage();
          },
        ),
        ListTile(
          key: const Key('settings-substitute-tile'),
          title: Text(l10n.text('settings.calendar.substituteTeachers.title')),
          subtitle: Text(
            widget.vm.substituteDetectionEnabled
                ? l10n.text('settings.calendar.substituteTeachers.subtitle')
                : l10n.text('settings.calendar.substituteDetection.subtitle'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _openSubstituteSettingsPage();
          },
        ),
        ListTile(
          key: const Key('settings-favorite-subjects-tile'),
          title: Text(l10n.text('settings.calendar.favoriteSubjects')),
          subtitle: Text(_favoriteSubjectsSummary(l10n)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _openFavoriteSubjectsPage();
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedSection(AppLocalizations l10n) {
    return _SettingsSectionCard(
      title: l10n.text('settings.section.advanced'),
      children: [
        if (Platform.isAndroid)
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.advanced.iosMode')),
            subtitle: Text(l10n.text('settings.advanced.iosMode.subtitle')),
            onChanged: widget.onSetPlatformOverride,
            value: widget.platformOverride,
          ),
        ListTile(
          title: Text(l10n.text('settings.advanced.networkProtocol')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) {
                  return const NetworkProtocolPage();
                },
              ),
            );
          },
        ),
        if (!Platform.isMacOS)
          ListTile(
            leading: const Icon(Icons.monetization_on),
            title: Text(l10n.text('settings.advanced.supportUs')),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (context) => Donate()),
              );
            },
          ),
        ListTile(
          leading: const Icon(Icons.feedback),
          title: Text(l10n.text('settings.advanced.feedback')),
          trailing: const Icon(Icons.open_in_new),
          onTap: () async {
            await launchUrl(
              Uri.parse(
                "https://docs.google.com/forms/d/e/1FAIpQLSdvhDufKHMVh4FzAUj5FiaGUjc8ma1DbD3NkRRHdWr4eE16hg/viewform?usp=pp_url&entry.804572866=${Uri.encodeQueryComponent(appVersion)}",
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.code),
          trailing: const Icon(Icons.open_in_new),
          title: Text(l10n.text('settings.advanced.sourceFork')),
          onTap: () => launchUrl(
            Uri.parse("https://github.com/Tobias-Bucci/digitales_register"),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          trailing: const Icon(Icons.open_in_new),
          title: Text(l10n.text('settings.advanced.sourceOriginal')),
          onTap: () => launchUrl(
            Uri.parse("https://github.com/miDeb/digitales_register"),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          trailing: const Icon(Icons.chevron_right),
          title: Text(l10n.text('settings.advanced.about')),
          onTap: () => _showAboutAppDialog(context),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          trailing: const Icon(Icons.chevron_right),
          title: Text(l10n.text('settings.advanced.licenses')),
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: l10n.text('settings.about.title'),
              applicationVersion: l10n.text('settings.about.version'),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentTheme = switch (widget.currentThemePreference) {
      AppThemePreference.light => _Theme.light,
      AppThemePreference.dark =>
        widget.vm.amoledMode ? _Theme.amoled : _Theme.dark,
      AppThemePreference.system => _Theme.followDevice,
    };
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Text(l10n.text('settings.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _buildAccountSection(l10n),
          const SizedBox(height: 16),
          _buildAppearanceSection(l10n, currentTheme),
          const SizedBox(height: 16),
          _buildDashboardSection(l10n),
          const SizedBox(height: 16),
          _buildCalendarSection(l10n),
          const SizedBox(height: 16),
          _buildAdvancedSection(l10n),
        ],
      ),
    );
  }

  Future<void> _showAboutAppDialog(BuildContext context) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final officialSourceUrl = Uri.parse("https://digitalesregister.it");
    final accentBg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.24 : 0.14),
      theme.colorScheme.surface,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.text('settings.about.appName'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 68,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.text('settings.about.title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.text('settings.about.version')),
                          const SizedBox(height: 12),
                          Text(l10n.text('settings.about.copyright')),
                          const SizedBox(height: 12),
                          Text(l10n.text('settings.about.description')),
                          const SizedBox(height: 12),
                          Text(l10n.text('settings.about.disclaimer')),
                          const SizedBox(height: 12),
                          Text(
                            l10n.text('settings.about.officialSourcesTitle'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.text('settings.about.officialSourcesBody')),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () {
                              launchUrl(
                                officialSourceUrl,
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: Text(
                              l10n.text('settings.about.officialSourcesLink'),
                              style: TextStyle(color: accent),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(l10n.text('settings.about.gpl')),
                          const SizedBox(height: 4),
                          Text(l10n.text('settings.about.warranty')),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () {
                              launchUrl(
                                Uri.parse(
                                  "https://www.gnu.org/licenses/gpl-3.0.html",
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            child: Text(
                              l10n.text('settings.about.gnuDetails'),
                              style: TextStyle(color: accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentBg,
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.text('common.close')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_CalendarSyncDisableAction?> _showCalendarSyncDisableDialog(
    BuildContext context,
  ) {
    final l10n = context.l10n;
    return showDialog<_CalendarSyncDisableAction>(
      context: context,
      builder: (context) => InfoDialog(
        title: Text(l10n.text('settings.calendarSync.disable.title')),
        content: Text(l10n.text('settings.calendarSync.disable.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.text('common.cancel')),
          ),
          TextButton(
            key: const Key('calendar-sync-keep-events'),
            onPressed: () => Navigator.of(context).pop(
              _CalendarSyncDisableAction.keep,
            ),
            child: Text(l10n.text('settings.calendarSync.disable.keep')),
          ),
          ElevatedButton(
            key: const Key('calendar-sync-remove-events'),
            onPressed: () => Navigator.of(context).pop(
              _CalendarSyncDisableAction.remove,
            ),
            child: Text(l10n.text('settings.calendarSync.disable.remove')),
          ),
        ],
      ),
    );
  }

  Future<MapEntry<String, String>?> showEditSubjectNick(BuildContext context,
      String key, String? value, List<String> suggestions) {
    return showDialog(
      context: context,
      builder: (context) => EditSubjectsNicks(
        subjectName: key,
        subjectNick: value,
        suggestions: suggestions,
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text(
                title,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsDetailPage extends StatelessWidget {
  const _SettingsDetailPage({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: children,
      ),
    );
  }
}

class _SubjectColorsSettingsPage extends StatefulWidget {
  const _SubjectColorsSettingsPage({
    required this.subjectThemes,
    required this.dashboardColorBorders,
    required this.calendarColorBackground,
    required this.dashboardColorTestsInRed,
    required this.onSetSubjectTheme,
    required this.onSetDashboardColorBorders,
    required this.onSetCalenderColorBackground,
    required this.onSetDashboardColorTestsInRed,
  });

  final BuiltMap<String, SubjectTheme> subjectThemes;
  final bool dashboardColorBorders;
  final bool calendarColorBackground;
  final bool dashboardColorTestsInRed;
  final OnSettingChanged<MapEntry<String, SubjectTheme>> onSetSubjectTheme;
  final OnSettingChanged<bool> onSetDashboardColorBorders;
  final OnSettingChanged<bool> onSetCalenderColorBackground;
  final OnSettingChanged<bool> onSetDashboardColorTestsInRed;

  @override
  State<_SubjectColorsSettingsPage> createState() =>
      _SubjectColorsSettingsPageState();
}

class _SubjectColorsSettingsPageState
    extends State<_SubjectColorsSettingsPage> {
  late Map<String, SubjectTheme> _subjectThemes;
  late bool _dashboardColorBorders;
  late bool _calendarColorBackground;
  late bool _dashboardColorTestsInRed;

  @override
  void initState() {
    super.initState();
    _subjectThemes =
        Map<String, SubjectTheme>.from(widget.subjectThemes.toMap());
    _dashboardColorBorders = widget.dashboardColorBorders;
    _calendarColorBackground = widget.calendarColorBackground;
    _dashboardColorTestsInRed = widget.dashboardColorTestsInRed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-subject-colors-page'),
      title: l10n.text('settings.subjectColors.title'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(l10n.text('settings.subjectColors.borderHomework')),
                value: _dashboardColorBorders,
                onChanged: (value) {
                  setState(() {
                    _dashboardColorBorders = value;
                  });
                  widget.onSetDashboardColorBorders(value);
                },
              ),
              SwitchListTile.adaptive(
                title: Text(
                  l10n.text('settings.subjectColors.calendarBackground'),
                ),
                value: _calendarColorBackground,
                onChanged: (value) {
                  setState(() {
                    _calendarColorBackground = value;
                  });
                  widget.onSetCalenderColorBackground(value);
                },
              ),
              SwitchListTile.adaptive(
                title: Text(l10n.text('settings.subjectColors.testsRed')),
                value: _dashboardColorTestsInRed,
                onChanged: (value) {
                  setState(() {
                    _dashboardColorTestsInRed = value;
                  });
                  widget.onSetDashboardColorTestsInRed(value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final entry in _subjectThemes.entries)
                ListTile(
                  title: Text(entry.key),
                  trailing: Container(
                    width: 44,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(entry.value.color),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onTap: () async {
                    final color = await showDialog<Color>(
                      context: context,
                      builder: (context) => _ColorPicker(
                        initialColor: Color(entry.value.color),
                      ),
                    );
                    if (color == null) {
                      return;
                    }
                    final updatedTheme = entry.value.rebuild(
                      (b) => b.color = color.toARGB32(),
                    );
                    setState(() {
                      _subjectThemes[entry.key] = updatedTheme;
                    });
                    widget.onSetSubjectTheme(
                      MapEntry(entry.key, updatedTheme),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradesSettingsPage extends StatefulWidget {
  const _GradesSettingsPage({
    required this.showGradesDiagram,
    required this.showAllSubjectsAverage,
    required this.allSubjects,
    required this.ignoreForGradesAverage,
    required this.onSetShowGradesDiagram,
    required this.onSetShowAllSubjectsAverage,
    required this.onSetIgnoreForGradesAverage,
  });

  final bool showGradesDiagram;
  final bool showAllSubjectsAverage;
  final List<String> allSubjects;
  final List<String> ignoreForGradesAverage;
  final OnSettingChanged<bool> onSetShowGradesDiagram;
  final OnSettingChanged<bool> onSetShowAllSubjectsAverage;
  final OnSettingChanged<List<String>> onSetIgnoreForGradesAverage;

  @override
  State<_GradesSettingsPage> createState() => _GradesSettingsPageState();
}

class _GradesSettingsPageState extends State<_GradesSettingsPage> {
  late bool _showGradesDiagram;
  late bool _showAllSubjectsAverage;
  late List<String> _ignoreForGradesAverage;

  List<String> get _notYetIgnoredForAverageSubjects => widget.allSubjects
      .where((subject) => !_ignoreForGradesAverage.contains(subject))
      .toList();

  @override
  void initState() {
    super.initState();
    _showGradesDiagram = widget.showGradesDiagram;
    _showAllSubjectsAverage = widget.showAllSubjectsAverage;
    _ignoreForGradesAverage = List<String>.from(widget.ignoreForGradesAverage);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-grades-page'),
      title: l10n.text('settings.section.grades'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(l10n.text('settings.grades.diagram')),
                value: _showGradesDiagram,
                onChanged: (value) {
                  setState(() {
                    _showGradesDiagram = value;
                  });
                  widget.onSetShowGradesDiagram(value);
                },
              ),
              SwitchListTile.adaptive(
                title: Text(l10n.text('settings.grades.averageAllSubjects')),
                value: _showAllSubjectsAverage,
                onChanged: (value) {
                  setState(() {
                    _showAllSubjectsAverage = value;
                  });
                  widget.onSetShowAllSubjectsAverage(value);
                },
              ),
              ListTile(
                title: Text(l10n.text('settings.grades.excludeAverage')),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    final newSubject = await showDialog<String>(
                      context: context,
                      builder: (context) => AddSubject(
                        availableSubjects: _notYetIgnoredForAverageSubjects,
                        title: l10n.text('settings.addSubject'),
                      ),
                    );
                    if (newSubject == null) {
                      return;
                    }
                    setState(() {
                      _ignoreForGradesAverage = [
                        ..._ignoreForGradesAverage,
                        newSubject,
                      ];
                    });
                    widget.onSetIgnoreForGradesAverage(_ignoreForGradesAverage);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: _ignoreForGradesAverage.isEmpty
              ? ListTile(
                  title: Text(
                    l10n.text('settings.grades.noExcludedSubject'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    for (final subject in _ignoreForGradesAverage)
                      Deleteable(
                        showExitAnimation: _ignoreForGradesAverage.length != 1,
                        showEntryAnimation: _ignoreForGradesAverage.length != 1,
                        key: ValueKey(subject),
                        builder: (context, delete) => ListTile(
                          title: Text(subject),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              await delete();
                              setState(() {
                                _ignoreForGradesAverage.remove(subject);
                              });
                              widget.onSetIgnoreForGradesAverage(
                                _ignoreForGradesAverage,
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SubjectNicksSettingsPage extends StatefulWidget {
  const _SubjectNicksSettingsPage({
    required this.subjectNicks,
    required this.allSubjects,
    required this.showCalendarEditNicksBar,
    required this.onSetSubjectNicks,
    required this.onSetShowCalendarEditNicksBar,
    required this.showAddDialogOnStart,
  });

  final Map<String, String> subjectNicks;
  final List<String> allSubjects;
  final bool showCalendarEditNicksBar;
  final OnSettingChanged<Map<String, String>> onSetSubjectNicks;
  final OnSettingChanged<bool> onSetShowCalendarEditNicksBar;
  final bool showAddDialogOnStart;

  @override
  State<_SubjectNicksSettingsPage> createState() =>
      _SubjectNicksSettingsPageState();
}

class _SubjectNicksSettingsPageState extends State<_SubjectNicksSettingsPage> {
  late Map<String, String> _subjectNicks;
  late bool _showCalendarEditNicksBar;

  List<String> get _subjectsWithoutNick => widget.allSubjects
      .where((subject) => !_subjectNicks.keys.contains(subject))
      .toList();

  @override
  void initState() {
    super.initState();
    _subjectNicks = Map<String, String>.from(widget.subjectNicks);
    _showCalendarEditNicksBar = widget.showCalendarEditNicksBar;
    if (widget.showAddDialogOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _addNick();
      });
    }
  }

  Future<MapEntry<String, String>?> _showEditSubjectNickDialog(
    String key,
    String? value,
    List<String> suggestions,
  ) {
    return showDialog<MapEntry<String, String>>(
      context: context,
      builder: (context) => EditSubjectsNicks(
        subjectName: key,
        subjectNick: value,
        suggestions: suggestions,
      ),
    );
  }

  Future<void> _addNick() async {
    final newValue = await _showEditSubjectNickDialog(
      '',
      '',
      _subjectsWithoutNick,
    );
    if (newValue == null) {
      return;
    }
    setState(() {
      _subjectNicks = Map<String, String>.from(_subjectNicks)
        ..[newValue.key] = newValue.value;
    });
    widget.onSetSubjectNicks(_subjectNicks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = _subjectNicks.entries.toList();
    return _SettingsDetailPage(
      key: const Key('settings-subject-nicks-page'),
      title: l10n.text('settings.calendar.subjectNicks'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                title: TextButton.icon(
                  onPressed: () {
                    final reset = Map<String, String>.of(defaultSubjectNicks);
                    setState(() {
                      _subjectNicks = reset;
                    });
                    widget.onSetSubjectNicks(reset);
                  },
                  icon: const Icon(Icons.restore),
                  label: Text(
                    l10n.text('settings.calendar.subjectNicksReset'),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addNick,
                ),
              ),
              SwitchListTile.adaptive(
                title: Text(l10n.text('settings.calendar.subjectNicksHint')),
                subtitle: Text(
                  l10n.text('settings.calendar.subjectNicksHintBody'),
                ),
                value: _showCalendarEditNicksBar,
                onChanged: (value) {
                  setState(() {
                    _showCalendarEditNicksBar = value;
                  });
                  widget.onSetShowCalendarEditNicksBar(value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: entries.isEmpty
              ? ListTile(
                  title: Text(
                    l10n.text('settings.calendar.subjectNicksHintBody'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    for (final entry in entries)
                      ListTile(
                        key: ValueKey(entry.key),
                        title: Text(entry.key),
                        subtitle: Text(entry.value),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() {
                                  _subjectNicks.remove(entry.key);
                                });
                                widget.onSetSubjectNicks(_subjectNicks);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final newValue =
                                    await _showEditSubjectNickDialog(
                                  entry.key,
                                  entry.value,
                                  [..._subjectsWithoutNick, entry.key],
                                );
                                if (newValue == null) {
                                  return;
                                }
                                setState(() {
                                  final updated = <String, String>{};
                                  for (final item in entries) {
                                    if (item.key == entry.key) {
                                      updated[newValue.key] = newValue.value;
                                    } else {
                                      updated[item.key] = item.value;
                                    }
                                  }
                                  _subjectNicks = updated;
                                });
                                widget.onSetSubjectNicks(_subjectNicks);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SubstituteSettingsPage extends StatefulWidget {
  const _SubstituteSettingsPage({
    required this.substituteDetectionEnabled,
    required this.substitutePrimaryTeachers,
    required this.lockedSubjects,
    required this.allSubjects,
    required this.allTeachers,
    required this.onSetSubstituteDetectionEnabled,
    required this.onSetSubstitutePrimaryTeachers,
    required this.onSetSubstituteKnownTeachers,
    required this.onSetSubstitutePrimaryTeachersLockedSubjects,
  });

  final bool substituteDetectionEnabled;
  final Map<String, List<String>> substitutePrimaryTeachers;
  final List<String> lockedSubjects;
  final List<String> allSubjects;
  final List<String> allTeachers;
  final OnSettingChanged<bool> onSetSubstituteDetectionEnabled;
  final OnSettingChanged<Map<String, List<String>>>
      onSetSubstitutePrimaryTeachers;
  final OnSettingChanged<List<String>> onSetSubstituteKnownTeachers;
  final OnSettingChanged<List<String>>
      onSetSubstitutePrimaryTeachersLockedSubjects;

  @override
  State<_SubstituteSettingsPage> createState() =>
      _SubstituteSettingsPageState();
}

class _SubstituteSettingsPageState extends State<_SubstituteSettingsPage> {
  late bool _substituteDetectionEnabled;
  late Map<String, List<String>> _substitutePrimaryTeachers;
  late List<String> _lockedSubjects;
  bool _showSubstituteSubjects = false;
  final Set<String> _expandedSubstituteSubjects = <String>{};

  @override
  void initState() {
    super.initState();
    _substituteDetectionEnabled = widget.substituteDetectionEnabled;
    _substitutePrimaryTeachers = widget.substitutePrimaryTeachers.map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
    _lockedSubjects = List<String>.from(widget.lockedSubjects);
  }

  void _applySubstituteTeachersUpdate(
    Map<String, List<String>> updated, {
    Iterable<String> manuallyLockedSubjects = const <String>[],
  }) {
    setState(() {
      _substitutePrimaryTeachers = updated.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      );
      for (final subject in manuallyLockedSubjects) {
        if (!containsSubjectIgnoreCase(_lockedSubjects, subject)) {
          _lockedSubjects.add(subject);
        }
      }
    });
    widget.onSetSubstitutePrimaryTeachers(_substitutePrimaryTeachers);
    widget.onSetSubstitutePrimaryTeachersLockedSubjects(_lockedSubjects);
  }

  Future<void> _showAddTeacherDialog(String subject) async {
    final teacher = await showDialog<String>(
      context: context,
      builder: (context) => AddSubject(
        availableSubjects: widget.allTeachers,
        title: context.l10n.text(
          'settings.calendar.substituteTeachers.addTeacher',
        ),
      ),
    );
    if (teacher == null) {
      return;
    }

    final updatedSubjects =
        Map<String, List<String>>.from(_substitutePrimaryTeachers);
    final resolvedSubject =
        findStringIgnoreCase(updatedSubjects.keys, subject) ?? subject;
    final updatedTeachers = <String>[
      ...updatedSubjects[resolvedSubject] ?? const <String>[],
    ];
    if (!containsStringIgnoreCase(updatedTeachers, teacher)) {
      updatedTeachers.add(teacher);
    }
    updatedSubjects[resolvedSubject] = updatedTeachers;
    _applySubstituteTeachersUpdate(
      updatedSubjects,
      manuallyLockedSubjects: [resolvedSubject],
    );

    final knownTeachers = <String>[...widget.allTeachers];
    if (!containsStringIgnoreCase(knownTeachers, teacher)) {
      knownTeachers.add(teacher);
      widget.onSetSubstituteKnownTeachers(knownTeachers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-substitute-page'),
      title: l10n.text('settings.calendar.substituteTeachers.title'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                title: Text(
                  l10n.text('settings.calendar.substituteDetection.title'),
                ),
                subtitle: Text(
                  l10n.text('settings.calendar.substituteDetection.subtitle'),
                ),
                value: _substituteDetectionEnabled,
                onChanged: (value) {
                  setState(() {
                    _substituteDetectionEnabled = value;
                  });
                  widget.onSetSubstituteDetectionEnabled(value);
                },
              ),
              ExpansionTile(
                key: const ValueKey('substitute-subjects-visibility'),
                initiallyExpanded: _showSubstituteSubjects,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _showSubstituteSubjects = expanded;
                  });
                },
                title: Text(
                  l10n.text('settings.calendar.substituteTeachers.title'),
                ),
                subtitle: Text(
                  l10n.text('settings.calendar.substituteTeachers.subtitle'),
                ),
                children: [
                  for (final entry in _substitutePrimaryTeachers.entries)
                    ExpansionTile(
                      key: PageStorageKey<String>(
                        'substitute-subject-${entry.key}',
                      ),
                      initiallyExpanded: _expandedSubstituteSubjects.any(
                        (subject) => equalsIgnoreCase(subject, entry.key),
                      ),
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _expandedSubstituteSubjects.removeWhere(
                            (subject) => equalsIgnoreCase(subject, entry.key),
                          );
                          if (expanded) {
                            _expandedSubstituteSubjects.add(entry.key);
                          }
                        });
                      },
                      title: Text(entry.key),
                      subtitle: Text(
                        entry.value.isEmpty
                            ? l10n.text(
                                'settings.calendar.substituteTeachers.noTeachers',
                              )
                            : entry.value.join(', '),
                      ),
                      children: [
                        ListTile(
                          title: Text(
                            l10n.text(
                              'settings.calendar.substituteTeachers.addTeacher',
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () => _showAddTeacherDialog(entry.key),
                          ),
                        ),
                        if (entry.value.isEmpty)
                          ListTile(
                            title: Text(
                              l10n.text(
                                'settings.calendar.substituteTeachers.noTeachers',
                              ),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        for (final teacher in entry.value)
                          ListTile(
                            title: Text(teacher),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                final updated = Map<String, List<String>>.from(
                                  _substitutePrimaryTeachers,
                                );
                                final teachers = List<String>.from(
                                  updated[entry.key] ?? const <String>[],
                                );
                                teachers.removeWhere(
                                  (item) => equalsIgnoreCase(item, teacher),
                                );
                                updated[entry.key] = teachers;
                                _applySubstituteTeachersUpdate(
                                  updated,
                                  manuallyLockedSubjects: [entry.key],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FavoriteSubjectsSettingsPage extends StatefulWidget {
  const _FavoriteSubjectsSettingsPage({
    required this.favoriteSubjects,
    required this.allSubjects,
    required this.onSetFavoriteSubjects,
  });

  final List<String> favoriteSubjects;
  final List<String> allSubjects;
  final OnSettingChanged<List<String>> onSetFavoriteSubjects;

  @override
  State<_FavoriteSubjectsSettingsPage> createState() =>
      _FavoriteSubjectsSettingsPageState();
}

class _FavoriteSubjectsSettingsPageState
    extends State<_FavoriteSubjectsSettingsPage> {
  late List<String> _favoriteSubjects;

  List<String> get _notYetFavoriteSubjects => widget.allSubjects
      .where(
          (subject) => !containsSubjectIgnoreCase(_favoriteSubjects, subject))
      .toList();

  @override
  void initState() {
    super.initState();
    _favoriteSubjects = List<String>.from(widget.favoriteSubjects);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-favorite-subjects-page'),
      title: l10n.text('settings.calendar.favoriteSubjects'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(l10n.text('settings.calendar.favoriteSubjects')),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _notYetFavoriteSubjects.isEmpty
                  ? null
                  : () async {
                      final newSubject = await showDialog<String>(
                        context: context,
                        builder: (context) => AddSubject(
                          availableSubjects: _notYetFavoriteSubjects,
                          title:
                              l10n.text('settings.calendar.favoriteSubjects'),
                          requireSuggestionMatch: true,
                        ),
                      );
                      if (newSubject == null ||
                          containsSubjectIgnoreCase(
                            _favoriteSubjects,
                            newSubject,
                          )) {
                        return;
                      }
                      setState(() {
                        _favoriteSubjects.add(newSubject);
                      });
                      widget.onSetFavoriteSubjects(_favoriteSubjects);
                    },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: _favoriteSubjects.isEmpty
              ? ListTile(
                  title: Text(
                    l10n.text('settings.calendar.noFavoriteSubject'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    for (final subject in _favoriteSubjects)
                      Deleteable(
                        showExitAnimation: _favoriteSubjects.length != 1,
                        showEntryAnimation: _favoriteSubjects.length != 1,
                        key: ValueKey(subject),
                        builder: (context, delete) => ListTile(
                          title: Text(subject),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              await delete();
                              setState(() {
                                _favoriteSubjects.remove(subject);
                              });
                              widget.onSetFavoriteSubjects(_favoriteSubjects);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CalendarSyncSettingsDetailPage extends StatelessWidget {
  const _CalendarSyncSettingsDetailPage({
    required this.calendarSyncEnabled,
    required this.calendarSyncCalendarId,
    required this.calendarsFuture,
    required this.onChangeCalendar,
    required this.onRemoveCalendarSyncEvents,
  });

  final bool calendarSyncEnabled;
  final int? calendarSyncCalendarId;
  final Future<List<CalendarSyncCalendar>> calendarsFuture;
  final Future<void> Function() onChangeCalendar;
  final Future<void> Function() onRemoveCalendarSyncEvents;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-calendar-sync-page'),
      title: l10n.text('settings.calendarSync.title'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: FutureBuilder<List<CalendarSyncCalendar>>(
            future: calendarsFuture,
            builder: (context, snapshot) {
              final calendars = snapshot.data ?? const <CalendarSyncCalendar>[];
              CalendarSyncCalendar? selectedCalendar;
              for (final calendar in calendars) {
                if (calendar.id == calendarSyncCalendarId) {
                  selectedCalendar = calendar;
                  break;
                }
              }
              selectedCalendar ??= calendars.isEmpty
                  ? null
                  : calendars.firstWhere(
                      (calendar) => calendar.isPrimary,
                      orElse: () => calendars.first,
                    );
              return Column(
                children: [
                  ListTile(
                    key: const Key('calendar-sync-calendar-picker'),
                    enabled: calendarSyncEnabled && calendars.isNotEmpty,
                    title:
                        Text(l10n.text('settings.calendarSync.select.title')),
                    subtitle: Text(
                      selectedCalendar == null
                          ? l10n.text('settings.calendarSync.select.none')
                          : '${selectedCalendar.displayName}\n${selectedCalendar.accountLabel}',
                    ),
                    isThreeLine: selectedCalendar != null,
                    trailing: snapshot.connectionState ==
                            ConnectionState.waiting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: calendarSyncEnabled && calendars.isNotEmpty
                        ? () async {
                            await onChangeCalendar();
                          }
                        : null,
                  ),
                  ListTile(
                    title:
                        Text(l10n.text('settings.calendarSync.disable.remove')),
                    subtitle: Text(
                      l10n.text('settings.calendarSync.disable.body'),
                    ),
                    enabled: calendarSyncEnabled,
                    onTap: calendarSyncEnabled
                        ? () async {
                            await onRemoveCalendarSyncEvents();
                          }
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _CalendarSyncDisableAction {
  keep,
  remove,
}

class EditSubjectsNicks extends StatefulWidget {
  final String? subjectName;
  final String? subjectNick;
  final List<String>? suggestions;

  const EditSubjectsNicks(
      {super.key, this.subjectName, this.subjectNick, this.suggestions});
  @override
  _EditSubjectsNicksState createState() => _EditSubjectsNicksState();
}

class _EditSubjectsNicksState extends State<EditSubjectsNicks> {
  late TextEditingController nickController;
  late TextEditingController subjectNameController;
  late FocusNode nickFocusNode, nameFocusNode;
  late bool forNewNick;

  @override
  void initState() {
    forNewNick = widget.subjectName!.isEmpty;
    nickController = TextEditingController(text: widget.subjectNick);
    subjectNameController = TextEditingController(text: widget.subjectName)
      ..addListener(
        () {
          setState(() {});
        },
      );
    nickFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    nickController.dispose();
    subjectNameController.dispose();
    nickFocusNode.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InfoDialog(
      title: Text(
        forNewNick
            ? l10n.text('settings.subjectNick.add')
            : l10n.text('settings.subjectNick.edit'),
      ),
      content: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.text('settings.subject.field')),
              const SizedBox(
                height: 27,
              ),
              Text(l10n.text('settings.subject.nick')),
            ],
          ),
          const SizedBox(
            width: 16,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RawAutocomplete<String>(
                  focusNode: nameFocusNode,
                  textEditingController: subjectNameController,
                  optionsBuilder: (textEditingValue) {
                    return widget.suggestions!.where((suggestion) => suggestion
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return AutocompleteOptions(
                      displayStringForOption:
                          RawAutocomplete.defaultStringForOption,
                      onSelected: onSelected,
                      options: options,
                      maxOptionsHeight: 200,
                      // We can't use a LayoutBuilder to get the size inside an AlertDialog,
                      // so we hardcode it here.
                      // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
                      width: 170,
                    );
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode,
                      onFieldSubmitted) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onFieldSubmitted: (String value) {
                        onFieldSubmitted();
                      },
                      autofocus: subjectNameController.text.isEmpty,
                    );
                  },
                  onSelected: (_) {
                    nameFocusNode.unfocus();
                  },
                ),
                TextField(
                  controller: nickController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  focusNode: nickFocusNode,
                  onSubmitted: (_) {
                    if (subjectNameController.text != "" &&
                        nickController.text != "") {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(l10n.text('common.cancel')),
        ),
        ElevatedButton(
          onPressed:
              subjectNameController.text != "" && nickController.text != ""
                  ? () {
                      Navigator.of(context).pop(
                        MapEntry(
                          subjectNameController.text,
                          nickController.text,
                        ),
                      );
                    }
                  : null,
          child: Text(l10n.text('common.done')),
        ),
      ],
    );
  }
}

class AddSubject extends StatefulWidget {
  final List<String>? availableSubjects;
  final String? title;
  final bool requireSuggestionMatch;

  const AddSubject({
    super.key,
    this.availableSubjects,
    this.title,
    this.requireSuggestionMatch = false,
  });
  @override
  _AddSubjectState createState() => _AddSubjectState();
}

class _AddSubjectState extends State<AddSubject> {
  late TextEditingController subjectNameController;
  late FocusNode focusNode;

  String? get _selectedSubject {
    if (widget.requireSuggestionMatch) {
      return findSubjectIgnoreCase(
        widget.availableSubjects ?? const [],
        subjectNameController.text,
      );
    }
    final trimmed = subjectNameController.text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    subjectNameController = TextEditingController()
      ..addListener(
        () {
          setState(() {});
        },
      );
  }

  @override
  void dispose() {
    subjectNameController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InfoDialog(
      title: Text(widget.title ?? l10n.text('settings.addSubject')),
      content: RawAutocomplete<String>(
        focusNode: focusNode,
        textEditingController: subjectNameController,
        optionsBuilder: (textEditingValue) {
          return widget.availableSubjects!.where(
            (suggestion) => suggestion
                .toLowerCase()
                .contains(textEditingValue.text.toLowerCase()),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return AutocompleteOptions(
            displayStringForOption: RawAutocomplete.defaultStringForOption,
            onSelected: onSelected,
            options: options,
            maxOptionsHeight: 200,
            // We can't use a LayoutBuilder to get the size inside an AlertDialog,
            // so we hardcode it here.
            // TODO: Remove once https://github.com/flutter/flutter/issues/78746 is fixed.
            width: 233,
          );
        },
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) {
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
            },
            autofocus: subjectNameController.text.isEmpty,
          );
        },
        onSelected: (_) {
          focusNode.unfocus();
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(l10n.text('common.cancel')),
        ),
        ElevatedButton(
          onPressed: _selectedSubject != null
              ? () {
                  Navigator.of(context).pop(_selectedSubject);
                }
              : null,
          child: Text(l10n.text('common.done')),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatefulWidget {
  final Color? initialColor;

  const _ColorPicker({this.initialColor});
  @override
  _ColorPickerState createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  Color? color;

  @override
  void initState() {
    color = widget.initialColor;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InfoDialog(
      title: Text(l10n.text('settings.colorPicker.title')),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: color!,
          onColorChanged: (pickedColor) {
            setState(() {
              color = pickedColor;
            });
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(l10n.text('common.cancel')),
        ),
        ElevatedButton(
          onPressed: color != widget.initialColor
              ? () {
                  Navigator.pop(context, color);
                }
              : null,
          child: Text(l10n.text('common.select')),
        ),
      ],
    );
  }
}
