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

// The page that sets up the detection of substitute teachers.

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
    final teacher = await _showAddSubject(
      context,
      availableSubjects: widget.allTeachers,
      title: context.l10n.text(
        'settings.calendar.substituteTeachers.addTeacher',
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
      ...updatedSubjects[resolvedSubject] ?? <String>[],
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

  void _removeTeacher(String subject, String teacher) {
    final updated = Map<String, List<String>>.from(
      _substitutePrimaryTeachers,
    );
    final teachers = List<String>.from(
      updated[subject] ?? <String>[],
    );
    teachers.removeWhere(
      (item) => equalsIgnoreCase(item, teacher),
    );
    updated[subject] = teachers;
    _applySubstituteTeachersUpdate(
      updated,
      manuallyLockedSubjects: [subject],
    );
  }

  /// A subject and its primary teachers as a row that opens in the card.
  Widget _newSubjectRow(
    BuildContext context,
    MapEntry<String, List<String>> entry,
  ) {
    final l10n = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: ExpansionTile(
        key: PageStorageKey<String>('substitute-subject-${entry.key}'),
        shape: const Border(),
        collapsedShape: const Border(),
        expansionAnimationStyle:
            reduceMotion ? AnimationStyle.noAnimation : null,
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
              ? l10n.text('settings.calendar.substituteTeachers.noTeachers')
              : entry.value.join(', '),
        ),
        childrenPadding: const EdgeInsetsDirectional.only(start: 16),
        children: [
          for (final teacher in entry.value)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(teacher),
              trailing: _RemoveButton(
                onPressed: () => _removeTeacher(entry.key, teacher),
              ),
            ),
          ListTile(
            key: ValueKey('substitute-add-teacher-${entry.key}'),
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text(
              l10n.text('settings.calendar.substituteTeachers.addTeacher'),
            ),
            onTap: () => _showAddTeacherDialog(entry.key),
          ),
        ],
      ),
    );
  }

  Widget _newDesignBuild(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsDetailPage(
      key: const Key('settings-substitute-page'),
      title: l10n.text('settings.calendar.substituteTeachers.title'),
      children: [
        SettingsSectionNew(
          title: null,
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
          ],
        ),
        const SizedBox(height: 8),
        SettingsSectionNew(
          key: const Key('settings-substitute-subjects'),
          title: l10n.text('grades.subjects'),
          count: _substitutePrimaryTeachers.length,
          description:
              l10n.text('settings.calendar.substituteTeachers.subtitle'),
          children: [
            if (_substitutePrimaryTeachers.isEmpty)
              SettingsEmptyRow(
                text: l10n.text('settings.calendar.substituteTeachers.none'),
              ),
            for (final entry in _substitutePrimaryTeachers.entries)
              _newSubjectRow(context, entry),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ResponsiveNavigationScope.isActive(context)) {
      return _newDesignBuild(context);
    }
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
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
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
                                  updated[entry.key] ?? <String>[],
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
