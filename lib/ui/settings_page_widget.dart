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
import 'package:scroll_to_index/scroll_to_index.dart';
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
  final controller = AutoScrollController(suggestedRowHeight: 250);
  late bool _translateSubjectsEnabled;
  late Future<List<CalendarSyncCalendar>> _calendarSyncCalendarsFuture;

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
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
        if (!mounted) return;
        final newValue =
            await showEditSubjectNick(context, "", "", subjectsWithoutNick);
        if (newValue != null) {
          widget.onSetSubjectNicks(
            Map.fromEntries(
                widget.vm.subjectNicks.entries.toList()..insert(0, newValue)),
          );
        }
      });
    }
    if (widget.vm.showGradesSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.scrollToIndex(3, preferPosition: AutoScrollPosition.begin);
      });
    }
    if (widget.vm.showCalendarSubstituteSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.scrollToIndex(
          5,
          preferPosition: AutoScrollPosition.begin,
        );
      });
    }
    super.initState();
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

  Future<void> _showAddSubstituteSubjectDialog() async {
    final availableSubjects = widget.vm.allSubjects
        .where(
          (subject) => !widget.vm.substitutePrimaryTeachers.keys.any(
            (existing) => equalsIgnoreCase(existing, subject),
          ),
        )
        .toList();
    final l10n = context.l10n;
    final subject = await showDialog<String>(
      context: context,
      builder: (context) => AddSubject(
        availableSubjects: availableSubjects,
        title: l10n.text('settings.calendar.substituteTeachers.addSubject'),
        requireSuggestionMatch: true,
      ),
    );
    if (subject == null) {
      return;
    }
    final updated = Map<String, List<String>>.from(widget.vm.substitutePrimaryTeachers)
      ..putIfAbsent(subject, () => <String>[]);
    widget.onSetSubstitutePrimaryTeachers(updated);
  }

  Future<void> _showAddTeacherDialog(String subject) async {
    final l10n = context.l10n;
    final currentTeachers = widget.vm.substitutePrimaryTeachers.entries
        .firstWhere((entry) => equalsIgnoreCase(entry.key, subject))
        .value;
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

    final updatedTeachers = <String>[...currentTeachers];
    if (!containsStringIgnoreCase(updatedTeachers, teacher)) {
      updatedTeachers.add(teacher);
    }

    final updatedSubjects =
        Map<String, List<String>>.from(widget.vm.substitutePrimaryTeachers);
    final resolvedSubject =
        findStringIgnoreCase(updatedSubjects.keys, subject) ?? subject;
    updatedSubjects[resolvedSubject] = updatedTeachers;
    widget.onSetSubstitutePrimaryTeachers(updatedSubjects);

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (widget.vm.showSubjectNicks) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await controller.scrollToIndex(4,
            preferPosition: AutoScrollPosition.begin);
      });
    }
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
        controller: controller,
        children: <Widget>[
          if (!widget.vm.demoMode) ...[
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                l10n.text('settings.section.profile'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onShowProfile,
            ),
            const Divider(),
          ],
          AutoScrollTag(
            controller: controller,
            index: 0,
            key: const ObjectKey(0),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.auth'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
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
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 1,
            key: const ObjectKey(1),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.appearance'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
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
            title: Text(l10n.text('settings.language.label')),
            trailing: SizedBox(
              width: 160,
              child: DropdownButton<AppLanguage>(
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
          const Divider(
            indent: 15,
            endIndent: 15,
            height: 0,
          ),
          ExpansionTile(
            title: Text(l10n.text('settings.subjectColors.title')),
            children: [
              for (final theme in widget.vm.subjectThemes.entries)
                ListTile(
                  onTap: () async {
                    final Color? color = await showDialog(
                      context: context,
                      builder: (context) => _ColorPicker(
                        initialColor: Color(theme.value.color),
                      ),
                    );
                    if (color != null) {
                      widget.onSetSubjectTheme(
                        MapEntry(
                          theme.key,
                          theme.value.rebuild(
                            (b) => b.color = color.toARGB32(),
                          ),
                        ),
                      );
                    }
                  },
                  title: Text(theme.key),
                  trailing: Container(
                    width: 50,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(theme.value.color),
                      //  border: Border.all(),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.subjectColors.borderHomework')),
            value: widget.vm.dashboardColorBorders,
            onChanged: widget.onSetDashboardColorBorders,
          ),
          SwitchListTile.adaptive(
            title: Text(
              l10n.text('settings.subjectColors.calendarBackground'),
            ),
            value: widget.vm.calendarColorBackground,
            onChanged: widget.onSetCalenderColorBackground,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.subjectColors.testsRed')),
            value: widget.vm.dashboardColorTestsInRed,
            onChanged: widget.onSetDashboardColorTestsInRed,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 2,
            key: const ObjectKey(2),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.dashboard'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.pushNotifications.title')),
            subtitle: Text(l10n.text('settings.pushNotifications.subtitle')),
            onChanged: widget.onSetPushNotificationsEnabled,
            value: widget.vm.pushNotificationsEnabled,
          ),
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
          if (isAndroidPlatform && widget.vm.calendarSyncEnabled)
            FutureBuilder<List<CalendarSyncCalendar>>(
              future: _calendarSyncCalendarsFuture,
              builder: (context, snapshot) {
                final calendars =
                    snapshot.data ?? const <CalendarSyncCalendar>[];
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
                  key: const Key('calendar-sync-calendar-picker'),
                  enabled: calendars.isNotEmpty,
                  title: Text(l10n.text('settings.calendarSync.select.title')),
                  subtitle: Text(
                    selectedCalendar == null
                        ? l10n.text('settings.calendarSync.select.none')
                        : '${selectedCalendar.displayName}\n${selectedCalendar.accountLabel}',
                  ),
                  isThreeLine: selectedCalendar != null,
                  trailing: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: calendars.isEmpty ? null : _changeCalendarSyncCalendar,
                );
              },
            ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.dashboard.markChanged')),
            onChanged: (bool value) {
              widget.onSetDashboardMarkNewOrChangedEntries(value);
            },
            value: widget.vm.dashboardMarkNewOrChangedEntries,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.dashboard.deduplicate')),
            onChanged: (bool value) {
              widget.onSetDashboardDeduplicateEntries(value);
            },
            value: widget.vm.dashboardDeduplicateEntries,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.dashboard.askDeleteReminder')),
            onChanged: (bool value) {
              widget.onSetAskWhenDelete(value);
            },
            value: widget.vm.askWhenDelete,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 3,
            key: const ObjectKey(3),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.grades'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.grades.diagram')),
            onChanged: (bool value) {
              widget.onSetShowGradesDiagram(value);
            },
            value: widget.vm.showGradesDiagram,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.grades.averageAllSubjects')),
            onChanged: (bool value) {
              widget.onSetShowAllSubjectsAverage(value);
            },
            value: widget.vm.showAllSubjectsAverage,
          ),
          ListTile(
            title: Text(l10n.text('settings.grades.excludeAverage')),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final newSubject = await showDialog<String>(
                  context: context,
                  builder: (context) => AddSubject(
                    availableSubjects: notYetIgnoredForAverageSubjects,
                    title: l10n.text('settings.addSubject'),
                  ),
                );
                if (newSubject != null) {
                  widget.onSetIgnoreForGradesAverage(
                      widget.vm.ignoreForGradesAverage..add(newSubject));
                }
              },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.vm.ignoreForGradesAverage.isEmpty
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  l10n.text('settings.grades.noExcludedSubject'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final subject in widget.vm.ignoreForGradesAverage)
                  Deleteable(
                    // don't show an animation if this is the only item
                    // in that case, the AnimatedCrossFade will do a different animation
                    showExitAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    showEntryAnimation:
                        widget.vm.ignoreForGradesAverage.length != 1,
                    key: ValueKey(subject),
                    builder: (context, delete) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: ListTile(
                        title: Text(subject),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                          ),
                          onPressed: () async {
                            await delete();
                            widget.onSetIgnoreForGradesAverage(
                              widget.vm.ignoreForGradesAverage..remove(subject),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 4,
            key: const ObjectKey(4),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.calendar'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ExpansionTile(
            initiallyExpanded: widget.vm.showSubjectNicks,
            title: Text(l10n.text('settings.calendar.subjectNicks')),
            children: List.generate(
              widget.vm.subjectNicks.length + 1,
              (i) {
                if (i == 0) {
                  return ListTile(
                    title: TextButton.icon(
                      onPressed: () {
                        widget.onSetSubjectNicks(Map.of(defaultSubjectNicks));
                      },
                      icon: const Icon(Icons.restore),
                      label: Text(
                        l10n.text('settings.calendar.subjectNicksReset'),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final newValue = await showEditSubjectNick(
                          context,
                          "",
                          "",
                          subjectsWithoutNick,
                        );
                        if (newValue != null) {
                          widget.onSetSubjectNicks(
                            Map.fromEntries(
                                widget.vm.subjectNicks.entries.toList()
                                  ..insert(0, newValue)),
                          );
                        }
                      },
                    ),
                  );
                }
                final index = i - 1;
                final key = widget.vm.subjectNicks.entries.toList()[index].key;
                final value = widget.vm.subjectNicks[key];
                return Deleteable(
                  key: ValueKey(key),
                  builder: (context, delete) => ListTile(
                    title: Text(key),
                    subtitle: Text(value!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            await delete();
                            widget.onSetSubjectNicks(
                              Map.of(widget.vm.subjectNicks)..remove(key),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final newValue = await showEditSubjectNick(
                              context,
                              key,
                              value,
                              subjectsWithoutNick..add(key),
                            );
                            if (newValue != null) {
                              widget.onSetSubjectNicks(
                                Map.fromEntries(
                                  List.of(widget.vm.subjectNicks.entries)
                                    ..[index] = newValue,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.calendar.subjectNicksHint')),
            subtitle: Text(
              l10n.text('settings.calendar.subjectNicksHintBody'),
            ),
            onChanged: (bool value) {
              widget.onSetShowCalendarEditNicksBar(value);
            },
            value: widget.vm.showCalendarEditNicksBar,
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 5,
            key: const ObjectKey(5),
            child: ListTile(
              title: Text(
                l10n.text('settings.calendar.substituteTeachers.title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.text('settings.calendar.substituteDetection.title')),
            subtitle:
                Text(l10n.text('settings.calendar.substituteDetection.subtitle')),
            onChanged: widget.onSetSubstituteDetectionEnabled,
            value: widget.vm.substituteDetectionEnabled,
          ),
          ListTile(
            title: Text(l10n.text('settings.calendar.substituteTeachers.title')),
            subtitle:
                Text(l10n.text('settings.calendar.substituteTeachers.subtitle')),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: widget.vm.allSubjects
                      .where(
                        (subject) => !widget.vm.substitutePrimaryTeachers.keys.any(
                          (existing) => equalsIgnoreCase(existing, subject),
                        ),
                      )
                      .isEmpty
                  ? null
                  : _showAddSubstituteSubjectDialog,
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.vm.substitutePrimaryTeachers.isEmpty
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  l10n.text('settings.calendar.substituteTeachers.none'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
            secondChild: Column(
              children: [
                for (final entry in widget.vm.substitutePrimaryTeachers.entries)
                  ExpansionTile(
                    key: ValueKey('substitute-subject-${entry.key}'),
                    title: Text(entry.key),
                    subtitle: Text(
                      entry.value.isEmpty
                          ? l10n.text(
                              'settings.calendar.substituteTeachers.noTeachers',
                            )
                          : entry.value.join(', '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        final updated = Map<String, List<String>>.from(
                          widget.vm.substitutePrimaryTeachers,
                        )..remove(entry.key);
                        widget.onSetSubstitutePrimaryTeachers(updated);
                      },
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
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: ListTile(
                            title: Text(
                              l10n.text(
                                'settings.calendar.substituteTeachers.noTeachers',
                              ),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      for (final teacher in entry.value)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: ListTile(
                            title: Text(teacher),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                final updated = Map<String, List<String>>.from(
                                  widget.vm.substitutePrimaryTeachers,
                                );
                                final teachers =
                                    List<String>.from(updated[entry.key] ?? []);
                                teachers.removeWhere(
                                  (item) => equalsIgnoreCase(item, teacher),
                                );
                                if (teachers.isEmpty) {
                                  updated.remove(entry.key);
                                } else {
                                  updated[entry.key] = teachers;
                                }
                                widget.onSetSubstitutePrimaryTeachers(updated);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 6,
            key: const ObjectKey(6),
            child: ListTile(
              title: Text(
                l10n.text('settings.calendar.favoriteSubjects'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ListTile(
            title: Text(l10n.text('settings.calendar.favoriteSubjects')),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: notYetFavoriteSubjects.isEmpty
                  ? null
                  : () async {
                      final newSubject = await showDialog<String>(
                        context: context,
                        builder: (context) => AddSubject(
                          availableSubjects: notYetFavoriteSubjects,
                          title:
                              l10n.text('settings.calendar.favoriteSubjects'),
                          requireSuggestionMatch: true,
                        ),
                      );
                      if (newSubject != null &&
                          !containsSubjectIgnoreCase(
                            widget.vm.favoriteSubjects,
                            newSubject,
                          )) {
                        widget.onSetFavoriteSubjects(
                          widget.vm.favoriteSubjects..add(newSubject),
                        );
                      }
                    },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: widget.vm.favoriteSubjects.isEmpty
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  l10n.text('settings.calendar.noFavoriteSubject'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final subject in widget.vm.favoriteSubjects)
                  Deleteable(
                    showExitAnimation: widget.vm.favoriteSubjects.length != 1,
                    showEntryAnimation: widget.vm.favoriteSubjects.length != 1,
                    key: ValueKey(subject),
                    builder: (context, delete) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: ListTile(
                        title: Text(subject),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await delete();
                            widget.onSetFavoriteSubjects(
                              widget.vm.favoriteSubjects..remove(subject),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          AutoScrollTag(
            controller: controller,
            index: 7,
            key: const ObjectKey(7),
            child: ListTile(
              title: Text(
                l10n.text('settings.section.advanced'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (Platform.isAndroid)
            SwitchListTile.adaptive(
              title: Text(l10n.text('settings.advanced.iosMode')),
              subtitle: Text(l10n.text('settings.advanced.iosMode.subtitle')),
              onChanged: (bool value) {
                widget.onSetPlatformOverride(value);
              },
              value: widget.platformOverride,
            ),
          ListTile(
            title: Text(l10n.text('settings.advanced.networkProtocol')),
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
                    MaterialPageRoute<void>(builder: (context) => Donate()));
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
      ),
    );
  }

  Future<void> _showAboutAppDialog(BuildContext context) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
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
