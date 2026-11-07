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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Two cards, the new and the legacy design, each with a small drawn preview.
/// The new design carries the recommendation.
class DesignChoicePicker extends StatelessWidget {
  const DesignChoicePicker({
    super.key,
    required this.legacySelected,
    required this.onChanged,
  });

  final bool legacySelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Shorter previews where the screen is short, so both cards and the
    // button fit on small phones.
    final aspectRatio = MediaQuery.sizeOf(context).height < 700 ? 0.95 : 0.8;
    Widget cards(double previewWidth, {required bool stacked}) {
      final newCard = _DesignCard(
        key: const Key('design-choice-new'),
        label: l10n.text('settings.design.new'),
        caption: l10n.text('design.choice.newCaption'),
        recommended: true,
        selected: !legacySelected,
        preview: _NewDesignPreview(
            width: previewWidth, rows: aspectRatio < 0.9 ? 3 : 2),
        previewWidth: previewWidth,
        aspectRatio: aspectRatio,
        onTap: () => onChanged(false),
      );
      final legacyCard = _DesignCard(
        key: const Key('design-choice-legacy'),
        label: l10n.text('settings.design.legacy'),
        caption: l10n.text('design.choice.legacyCaption'),
        recommended: false,
        selected: legacySelected,
        preview: _LegacyDesignPreview(width: previewWidth),
        previewWidth: previewWidth,
        aspectRatio: aspectRatio,
        onTap: () => onChanged(true),
      );
      if (stacked) {
        return Column(
          children: [newCard, const SizedBox(height: 12), legacyCard],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: newCard),
            const SizedBox(width: 12),
            Expanded(child: legacyCard),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.text('settings.design.title'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side down to the narrowest phones; stacked only when
          // large text leaves no room for two columns.
          final width = constraints.maxWidth;
          if (width < 260) {
            return cards((width - 2 * _cardPadding).clamp(0, 200),
                stacked: true);
          }
          return cards((width - 12) / 2 - 2 * _cardPadding, stacked: false);
        },
      ),
    );
  }
}

const _cardPadding = 10.0;

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    super.key,
    required this.label,
    required this.caption,
    required this.recommended,
    required this.selected,
    required this.preview,
    required this.previewWidth,
    required this.aspectRatio,
    required this.onTap,
  });

  final String label;
  final String caption;
  final bool recommended;
  final bool selected;
  final Widget preview;
  final double previewWidth;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(20);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: [
        label,
        if (recommended) l10n.text('design.choice.recommended'),
        caption,
      ].join(', '),
      onTap: onTap,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : scheme.surfaceContainerLow,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(_cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SizedBox(
                      width: previewWidth,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                            aspectRatio: aspectRatio, child: preview),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _SelectionMark(selected: selected),
                    ],
                  ),
                  if (recommended) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: Text(
                              l10n.text('design.choice.recommended'),
                              maxLines: 1,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(selected),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : scheme.surface,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: 2,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
            : null,
      ),
    );
  }
}

/// Content of a preview that may be taller than the preview: it is cut at
/// the bottom, like a screen that scrolls on.
class _TopClipped extends StatelessWidget {
  const _TopClipped({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: child,
        ),
      );
}

/// A rounded bar standing in for a line of text.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color, this.height = 5});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height),
        ),
      );
}

/// The new dashboard in miniature: a light header, coloured notices, a
/// compact list with subject colours and the floating bar at the bottom.
class _NewDesignPreview extends StatelessWidget {
  const _NewDesignPreview({required this.width, required this.rows});

  final double width;

  /// Lines of the list; fewer on the shorter previews of small phones.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = scheme.onSurface.withValues(alpha: 0.75);
    final faint = scheme.onSurfaceVariant.withValues(alpha: 0.35);
    final subjects = [scheme.primary, scheme.secondary, scheme.tertiary];
    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: Builder(builder: (context) {
          final w = width;
          return Stack(
            children: [
              Positioned.fill(
                child: _TopClipped(
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(w * 0.08, w * 0.08, w * 0.08, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: w * 0.1,
                              height: w * 0.1,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(w * 0.03),
                              ),
                            ),
                            SizedBox(width: w * 0.05),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Bar(width: w * 0.4, color: text),
                                  SizedBox(height: w * 0.025),
                                  _Bar(
                                      width: w * 0.26, color: faint, height: 4),
                                ],
                              ),
                            ),
                            Icon(Icons.notifications_none_rounded,
                                size: w * 0.1, color: text),
                          ],
                        ),
                        SizedBox(height: w * 0.07),
                        Row(
                          children: [
                            Expanded(
                              child: _Notice(
                                color: scheme.primaryContainer,
                                accent: scheme.primary,
                                width: w,
                              ),
                            ),
                            SizedBox(width: w * 0.04),
                            Expanded(
                              child: _Notice(
                                color: scheme.tertiaryContainer,
                                accent: scheme.tertiary,
                                width: w,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: w * 0.06),
                        for (var i = 0; i < rows; i++) ...[
                          Row(
                            children: [
                              Container(
                                width: w * 0.035,
                                height: w * 0.1,
                                decoration: BoxDecoration(
                                  color: subjects[i],
                                  borderRadius: BorderRadius.circular(w),
                                ),
                              ),
                              SizedBox(width: w * 0.04),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Bar(
                                      width: w * (0.42 - i * 0.06),
                                      color: text),
                                  SizedBox(height: w * 0.02),
                                  _Bar(
                                      width: w * (0.3 + i * 0.05),
                                      color: faint,
                                      height: 4),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: w * 0.045),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.1,
                right: w * 0.1,
                bottom: w * 0.06,
                child: Container(
                  height: w * 0.15,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(w),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.12),
                        blurRadius: w * 0.05,
                        offset: Offset(0, w * 0.015),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: i == 0 ? w * 0.13 : w * 0.06,
                          height: w * 0.06,
                          decoration: BoxDecoration(
                            color: i == 0 ? scheme.primary : faint,
                            borderRadius: BorderRadius.circular(w),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.accent,
    required this.width,
  });

  final Color color;
  final Color accent;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width;
    return Container(
      height: w * 0.2,
      padding: EdgeInsets.all(w * 0.035),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(w * 0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: w * 0.06,
            height: w * 0.06,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          _Bar(
              width: w * 0.22, color: accent.withValues(alpha: 0.7), height: 4),
        ],
      ),
    );
  }
}

/// The previous dashboard in miniature: a solid app bar with the menu button
/// and the bell, and plain day cards with dividers.
class _LegacyDesignPreview extends StatelessWidget {
  const _LegacyDesignPreview({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = scheme.onSurface.withValues(alpha: 0.6);
    final faint = scheme.onSurfaceVariant.withValues(alpha: 0.3);
    final bar = scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerHighest
        : scheme.primary;
    final onBar = scheme.brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.onPrimary;
    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.surfaceContainer,
        child: Builder(builder: (context) {
          final w = width;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: w * 0.2,
                color: bar,
                padding: EdgeInsets.symmetric(horizontal: w * 0.06),
                child: Row(
                  children: [
                    Icon(Icons.menu_rounded, size: w * 0.1, color: onBar),
                    SizedBox(width: w * 0.06),
                    _Bar(width: w * 0.36, color: onBar.withValues(alpha: 0.85)),
                    const Spacer(),
                    Icon(Icons.notifications_rounded,
                        size: w * 0.09, color: onBar),
                  ],
                ),
              ),
              Expanded(
                child: _TopClipped(
                  child: Padding(
                    padding: EdgeInsets.all(w * 0.06),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Bar(width: w * 0.3, color: text),
                        SizedBox(height: w * 0.04),
                        for (var i = 0; i < 2; i++) ...[
                          Container(
                            padding: EdgeInsets.all(w * 0.04),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(w * 0.02),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Bar(width: w * 0.5, color: text),
                                SizedBox(height: w * 0.03),
                                Divider(
                                    height: w * 0.02,
                                    thickness: 1,
                                    color: scheme.outlineVariant),
                                SizedBox(height: w * 0.03),
                                _Bar(
                                    width: w * (0.4 + i * 0.1),
                                    color: faint,
                                    height: 4),
                                SizedBox(height: w * 0.025),
                                _Bar(width: w * 0.3, color: faint, height: 4),
                              ],
                            ),
                          ),
                          SizedBox(height: w * 0.04),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// The question on its own, for people who used the app before it asked.
/// Pops with the chosen value of `legacyDesign`, or null when closed without
/// a choice.
class DesignChoiceScreen extends StatefulWidget {
  const DesignChoiceScreen({super.key, required this.legacyDesign});

  /// The design in use, selected until the user picks another.
  final bool legacyDesign;

  static Route<bool> route({required bool legacyDesign}) =>
      PageRouteBuilder<bool>(
        settings: const RouteSettings(name: '/design-choice'),
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            DesignChoiceScreen(legacyDesign: legacyDesign),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  State<DesignChoiceScreen> createState() => _DesignChoiceScreenState();
}

class _DesignChoiceScreenState extends State<DesignChoiceScreen> {
  late bool _legacy = widget.legacyDesign;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.text('design.choice.eyebrow').toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.text('design.choice.title'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.text('design.choice.body'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DesignChoicePicker(
                          legacySelected: _legacy,
                          onChanged: (legacy) =>
                              setState(() => _legacy = legacy),
                        ),
                        const SizedBox(height: 16),
                        DesignChoiceLaterNote(legacySelected: _legacy),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('design-choice-confirm'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(112, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_legacy),
                      child: Text(l10n.text(_legacy
                          ? 'design.choice.confirmLegacy'
                          : 'design.choice.confirmNew')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says that the choice can be changed in the settings, and what keeping the
/// legacy design means.
class DesignChoiceLaterNote extends StatelessWidget {
  const DesignChoiceLaterNote({super.key, required this.legacySelected});

  final bool legacySelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            legacySelected ? Icons.info_outline_rounded : Icons.tune_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.text(legacySelected
                ? 'design.choice.legacyNote'
                : 'design.choice.later'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
