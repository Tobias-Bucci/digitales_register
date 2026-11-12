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

/// The settings in the new design: the frame of the main page and of its
/// sub-pages, and the glass card of a section. The rows themselves are the
/// ones of the Legacy design (`settings_page_widget.dart`), so both designs
/// offer the same settings.
library;

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// The main page of the settings: the [sections] one below the other in
/// readable width, and the button to the debug menu for the debug user.
class SettingsPageNew extends StatelessWidget {
  const SettingsPageNew({
    super.key,
    required this.sections,
    this.onShowDebug,
  });

  /// Usually [SettingsSectionNew]s.
  final List<Widget> sections;

  /// Null hides the button to the debug menu.
  final VoidCallback? onShowDebug;

  @override
  Widget build(BuildContext context) {
    final onShowDebug = this.onShowDebug;
    return GlassPage(
      header: GlassPageHeader(
        surfaceKey: const Key('settings-app-header'),
        titleKey: const Key('settings-header-title'),
        title: context.t('settings.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
      ),
      body: GlassListBody(
        listKey: const Key('settings-list'),
        children: [
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            section,
          ],
          if (onShowDebug != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const Key('settings-debug-button'),
                style: glassControlStyle(Theme.of(context).colorScheme),
                onPressed: onShowDebug,
                icon: const Icon(Icons.bug_report_outlined, size: 20),
                label: Text(context.t('ui.debug')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The frame of a page of the settings that the main page opens, such as the
/// subject colours: the glass header with its back button above a list.
class SettingsDetailPageNew extends StatelessWidget {
  const SettingsDetailPageNew({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('settings-detail-app-header'),
          title: title,
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        ),
        body: GlassListBody(
          listKey: const Key('settings-detail-list'),
          children: children,
        ),
      );
}

/// A section of the settings: a heading in the style of the grades page above
/// a glass card that holds the rows, usually list tiles. An optional
/// [description] says what the section is about, at the top of the card.
///
/// A section inside a section is a smaller heading inside the same card.
///
/// Without a [title] the card stands alone, as the first card of a sub-page
/// does below its header.
class SettingsSectionNew extends StatelessWidget {
  const SettingsSectionNew({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
    this.count,
  });

  final String? title;
  final String? description;

  /// How many entries the section lists, after the [title].
  final int? count;

  /// Beside the heading, such as a progress indicator.
  final Widget? trailing;
  final List<Widget> children;

  static const _shape = RoundedRectangleBorder(
    borderRadius: DesignTokens.cardBorderRadius,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = this.description;
    final title = this.title;
    final rows = [
      if (description != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ...children,
    ];
    final nested =
        context.dependOnInheritedWidgetOfExactType<_InSettingsSection>() !=
            null;
    if (nested) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ...rows,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          GlassSectionHeading(title: title, count: count, trailing: trailing),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Material(
            // The ink of the rows stays on the card and inside its corners.
            type: MaterialType.transparency,
            shape: _shape,
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme.merge(
              contentPadding: const EdgeInsetsDirectional.only(
                start: 16,
                end: 12,
              ),
              iconColor: scheme.onSurfaceVariant,
              titleTextStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              child: _InSettingsSection(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InSettingsSection extends InheritedWidget {
  const _InSettingsSection({required super.child});

  @override
  bool updateShouldNotify(_InSettingsSection oldWidget) => false;
}

/// A segmented control as wide as the card, which gets smaller rather than
/// cut off when its labels do not fit, with the gaps of a row.
class SettingsSegmentedRow extends StatelessWidget {
  const SettingsSegmentedRow({super.key, required this.child});

  /// Usually a `GlassSegmentedControl`.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: child,
            ),
          ),
        ),
      );
}

/// One answer of [showSettingsChoiceSheet].
class SettingsChoice<T> {
  const SettingsChoice({
    required this.value,
    required this.label,
    this.key,
    this.primary = false,
  });

  final T value;
  final String label;
  final Key? key;

  /// The answer the sheet suggests, as a filled button.
  final bool primary;
}

/// Asks the question [title] with the explanation [body] in a glass sheet and
/// returns the chosen [SettingsChoice.value], or null when the sheet is closed
/// or cancelled.
Future<T?> showSettingsChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required String body,
  required List<SettingsChoice<T>> choices,
}) =>
    showGlassSheet<T>(
      context: context,
      builder: (context) => GlassPanel(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 16),
            SettingsSheetActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.t('common.cancel')),
                ),
                for (final choice in choices)
                  if (choice.primary)
                    FilledButton(
                      key: choice.key,
                      onPressed: () => Navigator.of(context).pop(choice.value),
                      child: Text(choice.label),
                    )
                  else
                    TextButton(
                      key: choice.key,
                      onPressed: () => Navigator.of(context).pop(choice.value),
                      child: Text(choice.label),
                    ),
              ],
            ),
          ],
        ),
      ),
    );

/// The buttons at the end of a sheet of the settings, at the end of the line
/// and one below the other when they do not fit.
class SettingsSheetActions extends StatelessWidget {
  const SettingsSheetActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 4,
        children: children,
      );
}

/// The add button of a list of the settings beside its heading, as a disc
/// ([SettingsSectionNew.trailing]). Null [onPressed] shows it disabled, for a
/// list that has nothing left to add.
class SettingsHeadingButton extends StatelessWidget {
  const SettingsHeadingButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: HeaderDiscButton.iconSize,
        style: HeaderDiscButton.styleOf(Theme.of(context).colorScheme),
        icon: Icon(icon),
      );
}

/// What a list of the settings says when it is empty, as a quiet row of its
/// card.
class SettingsEmptyRow extends StatelessWidget {
  const SettingsEmptyRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The colour of a subject as a disc, as the swatches of the colour sheet
/// show it: outlined, so that pale colours do not melt into the card.
class SettingsColorDisc extends StatelessWidget {
  const SettingsColorDisc({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 28,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      );
}

/// Keeps a form in a sheet above the keyboard on phones. The centred panel
/// of wide windows does that by itself.
class SettingsSheetKeyboardInset extends StatelessWidget {
  const SettingsSheetKeyboardInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < tabletLayoutBreakpoint;
    return Padding(
      padding: EdgeInsets.only(
        bottom: phone ? MediaQuery.viewInsetsOf(context).bottom : 0,
      ),
      child: child,
    );
  }
}
