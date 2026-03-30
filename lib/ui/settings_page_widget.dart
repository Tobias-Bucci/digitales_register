// Copyright (C) 2021 Michael Debertol
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
import 'package:dr/container/settings_page.dart';
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
  final OnSettingChanged<bool> onSetPlatformOverride;
  final OnSettingChanged<bool> onSetDashboardColorBorders;
  final OnSettingChanged<bool> onSetCalenderColorBackground;
  final OnSettingChanged<bool> onSetDashboardColorTestsInRed;
  final OnSettingChanged<bool> onSetPushNotificationsEnabled;
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
    super.initState();
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
      appBar: const ResponsiveAppBar(
        title: Text("Einstellungen"),
      ),
      body: ListView(
        controller: controller,
        children: <Widget>[
          if (!widget.vm.demoMode) ...[
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                "Profil",
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
                "Anmeldung",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Angemeldet bleiben"),
            subtitle: const Text("Deine Zugangsdaten werden lokal gespeichert"),
            onChanged: (bool value) {
              widget.onSetNoPassSaving(!value);
            },
            value: !widget.vm.noPassSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten lokal speichern"),
            subtitle: const Text('Sehen, wann etwas eingetragen wurde'),
            onChanged: (bool value) {
              widget.onSetNoDataSaving(!value);
            },
            value: !widget.vm.noDataSaving,
          ),
          SwitchListTile.adaptive(
            title: const Text("Daten beim Ausloggen löschen"),
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
                "Aussehen",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          RadioGroup<_Theme>(
            groupValue: currentTheme,
            onChanged: _selectTheme,
            child: const Column(
              children: [
                RadioListTile(
                  value: _Theme.followDevice,
                  title: Text("Geräte-Theme folgen"),
                ),
                RadioListTile(
                  value: _Theme.light,
                  title: Text("Hell"),
                ),
                RadioListTile(
                  value: _Theme.dark,
                  title: Text("Dunkel"),
                ),
                RadioListTile(
                  value: _Theme.amoled,
                  title: Text("Amoled"),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text("Kontrastfarbe"),
            subtitle: const Text("Wird appweit als Akzentfarbe verwendet"),
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
            title: const Text("Fächerfarben"),
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
            title: const Text(
              "Hausaufgaben mit diesen Farben umrahmen",
            ),
            value: widget.vm.dashboardColorBorders,
            onChanged: widget.onSetDashboardColorBorders,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Stunden im Kalender mit diesen Farben färben",
            ),
            value: widget.vm.calendarColorBackground,
            onChanged: widget.onSetCalenderColorBackground,
          ),
          SwitchListTile.adaptive(
            title: const Text(
              "Tests immer rot umrahmen",
            ),
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
                "Merkheft",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Push Notifications aktivieren"),
            subtitle: const Text(
              "Prueft neue Notifications periodisch im Hintergrund (OS-abhaengig, ca. 10-15 Min.)",
            ),
            onChanged: widget.onSetPushNotificationsEnabled,
            value: widget.vm.pushNotificationsEnabled,
          ),
          SwitchListTile.adaptive(
            title: const Text("Neue oder geänderte Einträge markieren"),
            onChanged: (bool value) {
              widget.onSetDashboardMarkNewOrChangedEntries(value);
            },
            value: widget.vm.dashboardMarkNewOrChangedEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Doppelte Einträge ignorieren"),
            onChanged: (bool value) {
              widget.onSetDashboardDeduplicateEntries(value);
            },
            value: widget.vm.dashboardDeduplicateEntries,
          ),
          SwitchListTile.adaptive(
            title: const Text("Beim Löschen von Erinnerungen fragen"),
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
                "Noten",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: const Text("Noten in einem Diagramm darstellen"),
            onChanged: (bool value) {
              widget.onSetShowGradesDiagram(value);
            },
            value: widget.vm.showGradesDiagram,
          ),
          SwitchListTile.adaptive(
            title: const Text('Durchschnitt aller Fächer anzeigen'),
            onChanged: (bool value) {
              widget.onSetShowAllSubjectsAverage(value);
            },
            value: widget.vm.showAllSubjectsAverage,
          ),
          ListTile(
            title: const Text("Fächer aus dem Notendurchschnitt ausschließen"),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                final newSubject = await showDialog<String>(
                  context: context,
                  builder: (context) => AddSubject(
                    availableSubjects: notYetIgnoredForAverageSubjects,
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
            firstChild: const Padding(
              padding: EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  "Kein Fach ausgeschlossen",
                  style: TextStyle(color: Colors.grey),
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
                "Kalender",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ExpansionTile(
            initiallyExpanded: widget.vm.showSubjectNicks,
            title: const Text("Fächerkürzel"),
            children: List.generate(
              widget.vm.subjectNicks.length + 1,
              (i) {
                if (i == 0) {
                  return ListTile(
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
            title: const Text("Hinweis zum Bearbeiten von Kürzeln"),
            subtitle: const Text(
                "Wird angezeigt, wenn für ein Fach kein Kürzel vorhanden ist"),
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
                "Fokusfächer",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          ListTile(
            title: const Text("Fokusfächer verwalten"),
            subtitle: const Text(
              "Schnellfilter in Dashboard, Kalender und Noten",
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: notYetFavoriteSubjects.isEmpty
                  ? null
                  : () async {
                      final newSubject = await showDialog<String>(
                        context: context,
                        builder: (context) => AddSubject(
                          availableSubjects: notYetFavoriteSubjects,
                          title: "Fokusfach hinzufügen",
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
            firstChild: const Padding(
              padding: EdgeInsets.only(left: 16),
              child: ListTile(
                title: Text(
                  "Kein Fokusfach ausgewählt",
                  style: TextStyle(color: Colors.grey),
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
            index: 6,
            key: const ObjectKey(6),
            child: ListTile(
              title: Text(
                "Erweitert",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (Platform.isAndroid)
            SwitchListTile.adaptive(
              title: const Text("Gay Mode"),
              subtitle: const Text("Imitiere das Aussehen einer iOS-App"),
              onChanged: (bool value) {
                widget.onSetPlatformOverride(value);
              },
              value: widget.platformOverride,
            ),
          ListTile(
            title: const Text("Netzwerkprotokoll"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) {
                    return NetworkProtocolPage();
                  },
                ),
              );
            },
          ),
          if (!Platform.isMacOS)
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: const Text(
                "Unterstütze uns jetzt!",
              ),
              onTap: () {
                Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (context) => Donate()));
              },
            ),
          ListTile(
            leading: const Icon(Icons.feedback),
            title: const Text("Feedback geben"),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              await launchUrl(
                Uri.parse(
                  "https://docs.google.com/forms/d/e/1FAIpQLSeRYFLq346UH6sMzKicMHwE8KhtnTm4KBv_yho5b0GSrRsluA/viewform?usp=sf_link&entry.1362624919=${Uri.encodeQueryComponent(appVersion)}",
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.code),
            trailing: const Icon(Icons.open_in_new),
            title: const Text("Zum Quellcode (Fork)"),
            onTap: () => launchUrl(
              Uri.parse("https://github.com/Tobias-Bucci/digitales_register"),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            trailing: const Icon(Icons.open_in_new),
            title: const Text("Zum originalem Quellcode"),
            onTap: () => launchUrl(
              Uri.parse("https://github.com/miDeb/digitales_register"),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            trailing: const Icon(Icons.chevron_right),
            title: const Text("Über diese App"),
            onTap: () => _showAboutAppDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            trailing: const Icon(Icons.chevron_right),
            title: const Text("Lizenzen"),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName:
                    "Digitales Register (Client) - Tobias Bucci Fork",
                applicationVersion: "v1.0",
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showAboutAppDialog(BuildContext context) async {
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
                    "Digitales Register",
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
                            "Digitales Register (Client) - Tobias Bucci Fork",
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text("v1.0"),
                          const SizedBox(height: 12),
                          const Text(
                            "Original Copyright: Michael Debertol und Simon Wachtler 2019-2022\n"
                            "Diese Version Copyright: Tobias Bucci 2026",
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Ein Client für das Digitale Register. Diese Version wurde von Tobias Bucci angepasst und weiterentwickelt.",
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "This is free software, and you are welcome to redistribute it under certain conditions (GPLv3).",
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "This program comes with ABSOLUTELY NO WARRANTY.",
                          ),
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
                              "See the GNU General Public License for more details.",
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
                    child: const Text("Schließen"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    return InfoDialog(
      title: Text("Kürzel ${forNewNick ? "hinzufügen" : "bearbeiten"}"),
      content: Row(
        children: [
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Fach"),
              SizedBox(
                height: 27,
              ),
              Text("Kürzel"),
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
          child: const Text("Abbrechen"),
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
          child: const Text("Fertig"),
        ),
      ],
    );
  }
}

class AddSubject extends StatefulWidget {
  final List<String>? availableSubjects;
  final String title;
  final bool requireSuggestionMatch;

  const AddSubject({
    super.key,
    this.availableSubjects,
    this.title = "Fach hinzufügen",
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
    return InfoDialog(
      title: Text(widget.title),
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
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: _selectedSubject != null
              ? () {
                  Navigator.of(context).pop(_selectedSubject);
                }
              : null,
          child: const Text("Fertig"),
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
    return InfoDialog(
      title: const Text("Farbe auswählen"),
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
          child: const Text("Abbrechen"),
        ),
        ElevatedButton(
          onPressed: color != widget.initialColor
              ? () {
                  Navigator.pop(context, color);
                }
              : null,
          child: const Text("Auswählen"),
        ),
      ],
    );
  }
}
