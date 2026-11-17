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

// Shared pieces of the sub-pages: the sheet or dialog that adds a
// subject, the remove button of a row, and suggestions below a field.

class AddSubject extends StatefulWidget {
  final List<String>? availableSubjects;
  final String? title;
  final bool requireSuggestionMatch;

  /// In a glass sheet of the new design rather than a dialog.
  final bool sheet;

  const AddSubject({
    super.key,
    this.availableSubjects,
    this.title,
    this.requireSuggestionMatch = false,
    this.sheet = false,
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
        widget.availableSubjects ?? [],
        subjectNameController.text,
      );
    }
    final trimmed = subjectNameController.text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  void _onSubjectChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    subjectNameController = TextEditingController()
      ..addListener(_onSubjectChanged);
  }

  @override
  void dispose() {
    subjectNameController.removeListener(_onSubjectChanged);
    subjectNameController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Widget _sheet(BuildContext context) {
    final l10n = context.l10n;
    final selected = _selectedSubject;
    return SettingsSheetKeyboardInset(
      child: GlassPanel(
        title: widget.title ?? l10n.text('settings.addSubject'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('add-subject-field'),
              controller: subjectNameController,
              focusNode: focusNode,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) {
                if (selected != null) Navigator.of(context).pop(selected);
              },
              autofocus: subjectNameController.text.isEmpty,
            ),
            _SheetSuggestions(
              query: subjectNameController.text,
              suggestions: widget.availableSubjects ?? const [],
              onSelected: (suggestion) {
                subjectNameController.value = TextEditingValue(
                  text: suggestion,
                  selection: TextSelection.collapsed(offset: suggestion.length),
                );
                focusNode.unfocus();
              },
            ),
            const SizedBox(height: 16),
            SettingsSheetActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.text('common.cancel')),
                ),
                FilledButton(
                  key: const Key('add-subject-done'),
                  onPressed: selected != null
                      ? () => Navigator.of(context).pop(selected)
                      : null,
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

/// Asks for a subject, or a teacher, to add: in a glass sheet in the new
/// design, in a dialog in the legacy one.
Future<String?> _showAddSubject(
  BuildContext context, {
  required List<String> availableSubjects,
  required String title,
  bool requireSuggestionMatch = false,
}) {
  if (ResponsiveNavigationScope.isActive(context)) {
    return showGlassSheet<String>(
      context: context,
      builder: (context) => AddSubject(
        availableSubjects: availableSubjects,
        title: title,
        requireSuggestionMatch: requireSuggestionMatch,
        sheet: true,
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (context) => AddSubject(
      availableSubjects: availableSubjects,
      title: title,
      requireSuggestionMatch: requireSuggestionMatch,
    ),
  );
}

/// How long a row of a list of the settings takes to come and go; at once
/// with reduced motion.
Duration _settingsMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);

/// Takes an entry off a list of the settings, in the new design.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({
    required this.onPressed,
    this.icon = Icons.close_rounded,
  });

  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.text('button.delete'),
        icon: Icon(icon),
        onPressed: onPressed,
      );
}

/// The suggestions for the field of a sheet that match [query], as rows below
/// it. A sheet sits at the bottom of the screen, where a list that opens below
/// the field would run off it.
class _SheetSuggestions extends StatelessWidget {
  const _SheetSuggestions({
    required this.query,
    required this.suggestions,
    required this.onSelected,
  });

  final String query;
  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final matches = [
      for (final suggestion in suggestions)
        if (suggestion.toLowerCase().contains(normalized) &&
            suggestion.toLowerCase() != normalized)
          suggestion,
    ];
    if (matches.isEmpty) return const SizedBox(height: 4);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 192),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: DesignTokens.cardBorderRadius,
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            clipBehavior: Clip.antiAlias,
            borderRadius: DesignTokens.cardBorderRadius,
            child: ListView.builder(
              key: const Key('sheet-suggestions'),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: matches.length,
              itemBuilder: (context, index) => ListTile(
                key: ValueKey('suggestion-${matches[index]}'),
                visualDensity: VisualDensity.compact,
                title: Text(
                  matches[index],
                  style: theme.textTheme.bodyLarge,
                ),
                onTap: () => onSelected(matches[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
