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

// The page of the subject nicknames, and the list that edits them.

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
    if (ResponsiveNavigationScope.isActive(context)) {
      return showGlassSheet<MapEntry<String, String>>(
        context: context,
        builder: (context) => EditSubjectsNicks(
          subjectName: key,
          subjectNick: value,
          suggestions: suggestions,
          sheet: true,
        ),
      );
    }
    return showDialog<MapEntry<String, String>>(
      context: context,
      builder: (context) => EditSubjectsNicks(
        subjectName: key,
        subjectNick: value,
        suggestions: suggestions,
      ),
    );
  }

  void _removeNick(String subject) {
    setState(() {
      _subjectNicks.remove(subject);
    });
    widget.onSetSubjectNicks(_subjectNicks);
  }

  void _resetNicks() {
    final reset = Map<String, String>.of(defaultSubjectNicks);
    setState(() {
      _subjectNicks = reset;
    });
    widget.onSetSubjectNicks(reset);
  }

  Future<void> _editNick(
    List<MapEntry<String, String>> entries,
    MapEntry<String, String> entry,
  ) async {
    final newValue = await _showEditSubjectNickDialog(
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
  }

  Widget _newDesignBuild(BuildContext context) {
    final l10n = context.l10n;
    final entries = _subjectNicks.entries.toList();
    return _SettingsDetailPage(
      key: const Key('settings-subject-nicks-page'),
      title: l10n.text('settings.calendar.subjectNicks'),
      children: [
        SettingsSectionNew(
          title: null,
          children: [
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
            ListTile(
              key: const Key('settings-subject-nicks-reset'),
              leading: const Icon(Icons.restore),
              title: Text(l10n.text('settings.calendar.subjectNicksReset')),
              onTap: _resetNicks,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SettingsSectionNew(
          key: const Key('settings-subject-nicks-list'),
          title: l10n.text('settings.subject.nick'),
          count: entries.length,
          trailing: SettingsHeadingButton(
            key: const Key('settings-subject-nicks-add'),
            tooltip: l10n.text('settings.subjectNick.add'),
            onPressed: _addNick,
          ),
          children: [
            if (entries.isEmpty)
              SettingsEmptyRow(
                text: l10n.text('settings.calendar.subjectNicksHintBody'),
              ),
            for (final entry in entries)
              ListTile(
                key: ValueKey(entry.key),
                title: Text(entry.key),
                subtitle: Text(entry.value),
                onTap: () => _editNick(entries, entry),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.text('settings.subjectNick.edit'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editNick(entries, entry),
                    ),
                    _RemoveButton(
                      icon: Icons.delete_outline,
                      onPressed: () => _removeNick(entry.key),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
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
    if (ResponsiveNavigationScope.isActive(context)) {
      return _newDesignBuild(context);
    }
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
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
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

class EditSubjectsNicks extends StatefulWidget {
  final String? subjectName;
  final String? subjectNick;
  final List<String>? suggestions;

  /// In a glass sheet of the new design rather than a dialog.
  final bool sheet;

  const EditSubjectsNicks({
    super.key,
    this.subjectName,
    this.subjectNick,
    this.suggestions,
    this.sheet = false,
  });
  @override
  _EditSubjectsNicksState createState() => _EditSubjectsNicksState();
}

class _EditSubjectsNicksState extends State<EditSubjectsNicks> {
  late TextEditingController nickController;
  late TextEditingController subjectNameController;
  late FocusNode nickFocusNode, nameFocusNode;
  late bool forNewNick;

  void _onSubjectChanged() => setState(() {});

  @override
  void initState() {
    forNewNick = widget.subjectName!.isEmpty;
    nickController = TextEditingController(text: widget.subjectNick);
    subjectNameController = TextEditingController(text: widget.subjectName)
      ..addListener(_onSubjectChanged);
    nickFocusNode = FocusNode();
    nameFocusNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    subjectNameController.removeListener(_onSubjectChanged);
    nickController.dispose();
    subjectNameController.dispose();
    nickFocusNode.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }

  bool get _complete =>
      subjectNameController.text != "" && nickController.text != "";

  void _submit() {
    if (_complete) {
      Navigator.of(context).pop(
        MapEntry(subjectNameController.text, nickController.text),
      );
    }
  }

  Widget _sheet(BuildContext context) {
    final l10n = context.l10n;
    return SettingsSheetKeyboardInset(
      child: GlassPanel(
        title: forNewNick
            ? l10n.text('settings.subjectNick.add')
            : l10n.text('settings.subjectNick.edit'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('subject-nick-subject-field'),
              controller: subjectNameController,
              focusNode: nameFocusNode,
              decoration: InputDecoration(
                labelText: l10n.text('settings.subject.field'),
              ),
              onSubmitted: (_) => nickFocusNode.requestFocus(),
              autofocus: subjectNameController.text.isEmpty,
            ),
            _SheetSuggestions(
              query: subjectNameController.text,
              suggestions: widget.suggestions ?? const [],
              onSelected: (suggestion) {
                subjectNameController.value = TextEditingValue(
                  text: suggestion,
                  selection: TextSelection.collapsed(offset: suggestion.length),
                );
                nickFocusNode.requestFocus();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('subject-nick-nick-field'),
              controller: nickController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.text('settings.subject.nick'),
              ),
              onChanged: (_) => setState(() {}),
              focusNode: nickFocusNode,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SettingsSheetActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.text('common.cancel')),
                ),
                FilledButton(
                  key: const Key('subject-nick-done'),
                  onPressed: _complete ? _submit : null,
                  child: Text(l10n.text('common.done')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheet) return _sheet(context);
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
