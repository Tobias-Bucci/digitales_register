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

part of '../settings_page_widget.dart';

// The page to choose a color for every subject.

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

  Future<void> _pickColor(MapEntry<String, SubjectTheme> entry) async {
    final color = await showSubjectSwatchPicker(
      context,
      subject: entry.key,
      current: Color(entry.value.color),
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final switches = [
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
    ];
    if (ResponsiveNavigationScope.isActive(context)) {
      return _SettingsDetailPage(
        key: const Key('settings-subject-colors-page'),
        title: l10n.text('settings.subjectColors.title'),
        children: [
          SettingsSectionNew(title: null, children: switches),
          if (_subjectThemes.isNotEmpty) ...[
            const SizedBox(height: 8),
            SettingsSectionNew(
              key: const Key('settings-subject-colors-list'),
              title: l10n.text('grades.subjects'),
              count: _subjectThemes.length,
              description: l10n.text('settings.subjectColors.subtitle'),
              children: [
                for (final entry in _subjectThemes.entries)
                  ListTile(
                    key: ValueKey('subject-color-${entry.key}'),
                    title: Text(entry.key),
                    trailing:
                        SettingsColorDisc(color: Color(entry.value.color)),
                    onTap: () => _pickColor(entry),
                  ),
              ],
            ),
          ],
        ],
      );
    }
    return _SettingsDetailPage(
      key: const Key('settings-subject-colors-page'),
      title: l10n.text('settings.subjectColors.title'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: switches,
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
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(entry.value.color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  onTap: () => _pickColor(entry),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
