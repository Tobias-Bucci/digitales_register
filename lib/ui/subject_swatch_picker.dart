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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Lets the user pick a subject color from the curated palette.
Future<Color?> showSubjectSwatchPicker(
  BuildContext context, {
  required String subject,
  required Color current,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => SubjectSwatchPicker(
      subject: subject,
      current: current,
      onSelected: (color) => Navigator.pop(context, color),
    ),
  );
}

class SubjectSwatchPicker extends StatelessWidget {
  const SubjectSwatchPicker({
    super.key,
    required this.subject,
    required this.current,
    required this.onSelected,
  });

  final String subject;
  final Color current;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.text('palette.picker.title'),
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.translateSubjectName(subject),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < AppPalette.subjectSwatches.length; i++)
                _SwatchButton(
                  color: AppPalette.subjectSwatches[i],
                  label: l10n.text(AppPalette.subjectSwatchNameKeys[i]),
                  selected: AppPalette.subjectSwatches[i].toARGB32() ==
                      current.toARGB32(),
                  onTap: () => onSelected(AppPalette.subjectSwatches[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
