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

// The page of the grade averages: subjects left out and rounding.

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

  Future<void> _addExcludedSubject() async {
    final newSubject = await _showAddSubject(
      context,
      availableSubjects: _notYetIgnoredForAverageSubjects,
      title: context.l10n.text('settings.addSubject'),
    );
    if (newSubject == null || !mounted) {
      return;
    }
    setState(() {
      _ignoreForGradesAverage = [
        ..._ignoreForGradesAverage,
        newSubject,
      ];
    });
    widget.onSetIgnoreForGradesAverage(_ignoreForGradesAverage);
  }

  Widget _excludedSubject(
    String subject,
    Widget Function(BuildContext, Future<void> Function()) builder, {
    Duration duration = const Duration(milliseconds: 250),
  }) =>
      CommittedDeleteable(
        onDeleted: () {
          _ignoreForGradesAverage.remove(subject);
          widget.onSetIgnoreForGradesAverage(List.of(_ignoreForGradesAverage));
          if (mounted) setState(() {});
        },
        showExitAnimation: _ignoreForGradesAverage.length != 1,
        showEntryAnimation: _ignoreForGradesAverage.length != 1,
        duration: duration,
        key: ValueKey(subject),
        builder: builder,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final switches = [
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
    ];
    if (ResponsiveNavigationScope.isActive(context)) {
      return _SettingsDetailPage(
        key: const Key('settings-grades-page'),
        title: l10n.text('settings.section.grades'),
        children: [
          SettingsSectionNew(title: null, children: switches),
          const SizedBox(height: 8),
          SettingsSectionNew(
            key: const Key('settings-grades-excluded'),
            title: l10n.text('settings.grades.excludeAverage'),
            count: _ignoreForGradesAverage.length,
            trailing: SettingsHeadingButton(
              key: const Key('settings-grades-exclude-add'),
              tooltip: l10n.text('settings.addSubject'),
              onPressed: _addExcludedSubject,
            ),
            children: [
              if (_ignoreForGradesAverage.isEmpty)
                SettingsEmptyRow(
                  text: l10n.text('settings.grades.noExcludedSubject'),
                ),
              for (final subject in _ignoreForGradesAverage)
                _excludedSubject(
                  subject,
                  duration: _settingsMotion(context),
                  (context, delete) => ListTile(
                    title: Text(subject),
                    trailing: _RemoveButton(onPressed: delete),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    return _SettingsDetailPage(
      key: const Key('settings-grades-page'),
      title: l10n.text('settings.section.grades'),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ...switches,
              ListTile(
                title: Text(l10n.text('settings.grades.excludeAverage')),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addExcludedSubject,
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
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : Column(
                  children: [
                    for (final subject in _ignoreForGradesAverage)
                      _excludedSubject(
                        subject,
                        (context, delete) => ListTile(
                          title: Text(subject),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: delete,
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
