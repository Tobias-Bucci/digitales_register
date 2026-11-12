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

import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_surface.dart' show NewDesignTheme;
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

typedef SetThickness = void Function(int thickness);

class GradesChartLegendEntry extends StatelessWidget {
  final SubjectTheme config;
  final String name;
  final SetThickness setThickness;

  // calls to setThickness are delayed by 100 ms to reduce jankiness. This leads
  // to some weird code.
  const GradesChartLegendEntry(
      {super.key,
      required this.config,
      required this.name,
      required this.setThickness});
  @override
  Widget build(BuildContext context) {
    var thickness = config.thick.toDouble();
    var call = 0;
    // Only the new design uses it; Legacy keeps its own below.
    Widget slider() => StatefulBuilder(builder: (context, setState) {
          return Slider(
            onChanged: (double val) {
              final thisCall = ++call;
              final value = val.toInt();
              if (value == config.thick) return;
              setState(() {
                thickness = val;
              });
              Future.delayed(const Duration(milliseconds: 100), () {
                if (call != thisCall || value == config.thick) {
                  return;
                }
                setThickness(value);
              });
            },
            value: thickness,
            max: 5,
            divisions: 5,
            semanticFormatterCallback: (value) =>
                '${context.l10n.translateSubjectName(name)}: ${value.toInt()}',
            mouseCursor: NewDesignTheme.clickCursor,
            activeColor: AppPalette.subjectMarker(
              Color(config.color),
              Theme.of(context).colorScheme,
            ),
            inactiveColor: AppPalette.subjectMarker(
              Color(config.color),
              Theme.of(context).colorScheme,
            ).withValues(alpha: 0.2),
          );
        });
    if (ResponsiveNavigationScope.isActive(context)) {
      // The new design: the colour of the line before the name, the slider
      // sets how thick it is, 0 hides it.
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final marker = AppPalette.subjectMarker(Color(config.color), scheme);
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const SizedBox(width: 4),
            DecoratedBox(
              decoration: ShapeDecoration(
                color:
                    config.thick == 0 ? marker.withValues(alpha: 0.35) : marker,
                shape: const CircleBorder(),
              ),
              child: const SizedBox.square(dimension: 12),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                context.l10n.translateSubjectName(name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: config.thick == 0
                      ? scheme.onSurfaceVariant
                      : scheme.onSurface,
                ),
              ),
            ),
            Expanded(flex: 5, child: slider()),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                context.l10n.translateSubjectName(name),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: StatefulBuilder(builder: (context, setState) {
              return Slider(
                onChanged: (double val) {
                  final thisCall = ++call;
                  final value = val.toInt();
                  if (value == config.thick) return;
                  setState(() {
                    thickness = val;
                  });
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (call != thisCall || value == config.thick) {
                      return;
                    }
                    setThickness(value);
                  });
                },
                value: thickness,
                max: 5,
                divisions: 5,
                activeColor: AppPalette.subjectMarker(
                  Color(config.color),
                  Theme.of(context).colorScheme,
                ),
                inactiveColor: AppPalette.subjectMarker(
                  Color(config.color),
                  Theme.of(context).colorScheme,
                ).withValues(alpha: 0.2),
              );
            }),
          ),
        ],
      ),
    );
  }
}
