import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
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
            label: const Text("Alle"),
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
                  label: Text(subject),
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
