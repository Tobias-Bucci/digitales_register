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
import 'package:dr/ui/glass_surface.dart' show showGlassSheet;
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Lets the user pick a subject color from the curated palettes.
Future<Color?> showSubjectSwatchPicker(
  BuildContext context, {
  required String subject,
  required Color current,
}) {
  if (ResponsiveNavigationScope.isActive(context)) {
    return showGlassSheet<Color>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: SubjectSwatchPicker(
          subject: subject,
          current: current,
          onSelected: (color) => Navigator.pop(context, color),
        ),
      ),
    );
  }
  return showModalBottomSheet<Color>(
    context: context,
    useRootNavigator: ResponsiveNavigationScope.isActive(context),
    isScrollControlled: true,
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
    final currentArgb = current.toARGB32();
    final inPalette = AppPalette.subjectPalettes.any((palette) =>
        palette.swatches.any((swatch) => swatch.toARGB32() == currentArgb));
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
          if (!inPalette) ...[
            _PaletteHeader(l10n.text('palette.group.current')),
            _SwatchButton(
              color: current,
              label: l10n.text('palette.group.current'),
              selected: true,
              onTap: () => onSelected(current),
            ),
          ],
          for (final palette in AppPalette.subjectPalettes) ...[
            _PaletteHeader(l10n.text(palette.nameKey)),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < palette.swatches.length; i++)
                  _SwatchButton(
                    color: palette.swatches[i],
                    label: '${l10n.text(palette.nameKey)}, '
                        '${l10n.text(AppPalette.subjectSwatchNameKeys[i])}',
                    selected: palette.swatches[i].toARGB32() == currentArgb,
                    onTap: () => onSelected(palette.swatches[i]),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaletteHeader extends StatelessWidget {
  const _PaletteHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // Keeps pale colors from melting into the sheet.
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      color: AppPalette.onSubjectColor(color),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
