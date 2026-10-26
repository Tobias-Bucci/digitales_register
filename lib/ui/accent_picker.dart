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

/// A row of the curated accents. Each swatch previews the accent as it will
/// look in the current light or dark theme.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AppAccent selected;
  final ValueChanged<AppAccent> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final accent in AppAccent.values)
          _AccentSwatch(
            key: Key('accent-${accent.name}'),
            scheme: AppPalette.scheme(
              brightness: brightness,
              amoled: false,
              accent: accent,
            ),
            label: context.l10n.text(accent.nameKey),
            selected: accent == selected,
            onTap: () => onSelected(accent),
          ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    super.key,
    required this.scheme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ColorScheme scheme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? ring : Colors.transparent,
                width: 2.5,
              ),
            ),
            // Primary with a slice of the matching container hints at how
            // the accent family looks together.
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  startAngle: 0.8,
                  endAngle: 0.8 + 6.283,
                  colors: [
                    scheme.primary,
                    scheme.primary,
                    scheme.primaryContainer,
                    scheme.primaryContainer,
                  ],
                  stops: const [0, 0.72, 0.72, 1],
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, color: scheme.onPrimary)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
