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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';

class FavoriteSubjectFilter extends StatelessWidget {
  final List<String> subjects;
  final String? selectedSubject;
  final ValueChanged<String?> onSelected;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final EdgeInsetsGeometry padding;

  const FavoriteSubjectFilter({
    super.key,
    required this.subjects,
    required this.selectedSubject,
    required this.onSelected,
    required this.subjectThemes,
    this.padding = EdgeInsets.zero,
  });

  SubjectTheme? _subjectTheme(String subject) {
    for (final entry in subjectThemes.entries) {
      if (equalsIgnoreCase(entry.key, subject)) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final normalizedSelected = selectedSubject == null
        ? null
        : findSubjectIgnoreCase(subjects, selectedSubject!);
    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text(l10n.text('filter.all')),
            selected: normalizedSelected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final subject in subjects)
            Builder(
              builder: (context) {
                final isSelected = normalizedSelected != null &&
                    equalsIgnoreCase(normalizedSelected, subject);
                final subjectTheme = _subjectTheme(subject);
                final chipColor = subjectTheme != null
                    ? Color(subjectTheme.color)
                    : theme.colorScheme.secondary;
                return ChoiceChip(
                  label: Text(l10n.translateSubjectName(subject)),
                  selected: isSelected,
                  onSelected: (_) => onSelected(subject),
                  selectedColor: chipColor.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.30 : 0.18,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? chipColor.withValues(alpha: 0.65)
                        : theme.colorScheme.outlineVariant,
                  ),
                  labelStyle: isSelected
                      ? TextStyle(
                          color: chipColor,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}
