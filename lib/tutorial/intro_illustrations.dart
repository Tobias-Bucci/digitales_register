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
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';

/// The pictures of the intro: the new design in miniature, drawn from the
/// same pieces as the app (cards, lens, navigation tint, subject palettes).
///
/// Each one is laid out once on a fixed canvas and scaled to the space it
/// gets, so it looks the same on every screen and with every text size. It has
/// no blur and no images; the text of the page says what it shows, so screen
/// readers skip it.
class IntroStage extends StatelessWidget {
  const IntroStage({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  /// The canvas every picture is drawn on.
  static const Size canvas = Size(320, 210);

  final double width, height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = (width / canvas.width) < (height / canvas.height)
        ? width / canvas.width
        : height / canvas.height;
    return ExcludeSemantics(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: MediaQuery(
            // Decorative text inside the picture scales with the picture.
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: SizedBox(
              width: canvas.width * scale,
              height: canvas.height * scale,
              child: FittedBox(
                child: SizedBox.fromSize(
                  size: canvas,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                            scheme.primary.withValues(alpha: 0.10),
                            scheme.surfaceContainerLow,
                          ),
                          scheme.surfaceContainerLow,
                        ],
                      ),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      // A picture that runs a little long is cut at the
                      // bottom, like a screen that scrolls on.
                      child: child is NavigationIllustration
                          ? child
                          : OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: child,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded bar standing in for a line of text.
class _Line extends StatelessWidget {
  const _Line({required this.width, required this.color, this.height = 6});

  final double width, height;
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

Color _textLine(ColorScheme scheme) => scheme.onSurface.withValues(alpha: 0.72);
Color _faintLine(ColorScheme scheme) =>
    scheme.onSurfaceVariant.withValues(alpha: 0.32);

/// The small text of a picture.
TextStyle _label(BuildContext context, {Color? color, double size = 11}) =>
    TextStyle(
      fontSize: size,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );

/// The subject letter of a row of the compact list.
class _SubjectMark extends StatelessWidget {
  const _SubjectMark({
    required this.color,
    required this.letter,
    this.size = 22,
  });

  final Color color;
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: Text(
          letter,
          style: _label(
            context,
            size: size * 0.5,
            color: AppPalette.onSubjectColor(color),
          ),
        ),
      );
}

/// A tick box of the notepad, done or not.
class _Tick extends StatelessWidget {
  const _Tick({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? scheme.primary : null,
        border: Border.all(
          color: done ? scheme.primary : scheme.outline,
          width: 1.5,
        ),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 11, color: scheme.onPrimary)
          : null,
    );
  }
}

/// One line of the compact list: subject, type and title, notepad tick.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.color,
    required this.letter,
    required this.titleWidth,
    required this.done,
  });

  final Color color;
  final String letter;
  final double titleWidth;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _SubjectMark(color: color, letter: letter, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(
                width: titleWidth,
                color: done ? _faintLine(scheme) : _textLine(scheme),
              ),
              const SizedBox(height: 4),
              _Line(
                  width: titleWidth * 0.6,
                  color: _faintLine(scheme),
                  height: 4),
            ],
          ),
        ),
        _Tick(done: done),
      ],
    );
  }
}

/// A coloured notice of the top of the dashboard.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.fill,
    required this.accent,
  });

  final IconData icon;
  final Color fill, accent;

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(width: 46, color: accent.withValues(alpha: 0.85)),
                  const SizedBox(height: 4),
                  _Line(
                      width: 30,
                      color: accent.withValues(alpha: 0.45),
                      height: 4),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A pill of glass, like the bar of the navigation, without its blur.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, this.radius = 999});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape.copyWith(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        color: navigationBarTint(scheme),
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: GlassEdge(shape: shape, child: child),
    );
  }
}

/// The dashboard: header with the bell, two notices and one day of the
/// compact list.
class DashboardIllustration extends StatelessWidget {
  const DashboardIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const swatches = AppPalette.subjectSwatches;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.school_rounded,
                    size: 14, color: scheme.onPrimary),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(width: 84, color: _textLine(scheme)),
                  const SizedBox(height: 4),
                  _Line(width: 52, color: _faintLine(scheme), height: 4),
                ],
              ),
              const Spacer(),
              Icon(Icons.notifications_none_rounded,
                  size: 20, color: _textLine(scheme)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Notice(
                  icon: Icons.beach_access_rounded,
                  fill: scheme.primaryContainer,
                  accent: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Notice(
                  icon: Icons.event_note_rounded,
                  fill: scheme.tertiaryContainer,
                  accent: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    _Line(width: 70, color: _textLine(scheme), height: 7),
                    const Spacer(),
                    _Line(width: 26, color: scheme.primary, height: 5),
                  ],
                ),
                const SizedBox(height: 10),
                _EntryRow(
                    color: swatches[0],
                    letter: 'M',
                    titleWidth: 120,
                    done: true),
                const SizedBox(height: 9),
                _EntryRow(
                    color: swatches[3],
                    letter: 'D',
                    titleWidth: 96,
                    done: false),
                const SizedBox(height: 9),
                _EntryRow(
                    color: swatches[8],
                    letter: 'E',
                    titleWidth: 110,
                    done: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A phone with the floating bar and a wide window with the rail, and where
/// Extras and Profile are.
class NavigationIllustration extends StatelessWidget {
  const NavigationIllustration({super.key});

  static const _marked = {AppDestination.extras, AppDestination.profile};

  /// The destinations of the bar or the rail, the first under the lens.
  Widget _track(BuildContext context, Axis axis) {
    final scheme = Theme.of(context).colorScheme;
    final horizontal = axis == Axis.horizontal;
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: 3)
          : const EdgeInsets.symmetric(vertical: 3),
      child: Flex(
        direction: axis,
        children: [
          for (final destination in AppDestination.values)
            Expanded(
              child: Padding(
                padding: horizontal
                    ? const EdgeInsets.symmetric(vertical: 3, horizontal: 0.5)
                    : const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (destination == AppDestination.dashboard)
                      const GlassLens(),
                    Center(
                      child: Icon(
                        destination == AppDestination.dashboard
                            ? destination.selectedIcon
                            : destination.icon,
                        size: 12,
                        color: destination == AppDestination.dashboard
                            ? scheme.onPrimaryContainer
                            : _marked.contains(destination)
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final screen = scheme.surfaceContainerLowest;
    final frame = scheme.outlineVariant;

    Widget content(int rows, double width) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows; i++) ...[
              Row(
                children: [
                  _SubjectMark(
                    color: AppPalette.subjectSwatches[(i * 3) % 12],
                    letter: '',
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  _Line(
                    width: width * (0.75 - (i % 3) * 0.12),
                    color: i.isEven ? _textLine(scheme) : _faintLine(scheme),
                    height: 5,
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        );

    Widget legend(AppDestination destination) => Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(destination.icon,
                  size: 14, color: scheme.onPrimaryContainer),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  l10n.text(destination.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(context, color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        );

    return Stack(
      children: [
        // The phone.
        Positioned(
          left: 16,
          top: 16,
          width: 120,
          height: 210,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: screen,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: frame, width: 2),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 16,
                  right: 8,
                  child: content(6, 70),
                ),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 30,
                  height: 26,
                  child: _GlassPill(
                    child: _track(context, Axis.horizontal),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The wide window.
        Positioned(
          left: 148,
          top: 16,
          width: 156,
          height: 118,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: screen,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: frame, width: 2),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                  child: SizedBox(
                    width: 28,
                    child: _GlassPill(
                      radius: 14,
                      child: _track(context, Axis.vertical),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 8, 0),
                    child: ClipRect(child: content(4, 90)),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 148,
          top: 144,
          right: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              legend(AppDestination.extras),
              const SizedBox(height: 8),
              legend(AppDestination.profile),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bell with unread notifications over the notification centre with its
/// filters.
class NotificationsIllustration extends StatelessWidget {
  const NotificationsIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final segments = [
      'notifications.filter.all',
      'notifications.sourceSchool',
      'notifications.sourceApp',
    ];

    Widget notification(IconData icon, double width, {required bool unread}) =>
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(width: width, color: _textLine(scheme)),
                  const SizedBox(height: 4),
                  _Line(
                      width: width * 0.7, color: _faintLine(scheme), height: 4),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.text('notifications.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(context, size: 14).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _GlassPill(
                child: SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: Badge(
                      label: const Text('3'),
                      backgroundColor: scheme.error,
                      textColor: scheme.onError,
                      child: Icon(Icons.notifications_rounded,
                          size: 20, color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The source filter, with the lens of the navigation.
          SizedBox(
            height: 30,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.onSurface.withValues(alpha: 0.06),
                shape: const StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (i == 0) const GlassLens(),
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  l10n.text(segments[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _label(
                                    context,
                                    color: i == 0
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded,
                      size: 13, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      l10n.text('notifications.filter.unread'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          _label(context, color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            child: Column(
              children: [
                notification(Icons.school_outlined, 130, unread: true),
                const SizedBox(height: 9),
                notification(Icons.campaign_outlined, 100, unread: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subjects with their colours, and the four palettes they come from.
class SubjectColorsIllustration extends StatelessWidget {
  const SubjectColorsIllustration({super.key});

  /// The hues shown of each palette, as indices of the swatches.
  static const _hues = [0, 2, 3, 5, 8, 9];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    const standard = AppPalette.subjectSwatches;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              child: Column(
                children: [
                  for (final (index, letter) in [
                    (0, 'M'),
                    (3, 'D'),
                    (8, 'E'),
                    (5, 'G'),
                  ]) ...[
                    Row(
                      children: [
                        _SubjectMark(color: standard[index], letter: letter),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Line(width: 56, color: _textLine(scheme)),
                              const SizedBox(height: 4),
                              _Line(
                                  width: 36,
                                  color: standard[index].withValues(alpha: 0.6),
                                  height: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (letter != 'G') const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final palette in AppPalette.subjectPalettes) ...[
                    Text(
                      l10n.text(palette.nameKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _label(context,
                          size: 9, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final hue in _hues)
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: palette.swatches[hue],
                              shape: BoxShape.circle,
                              border:
                                  palette == AppPalette.subjectPalettes[0] &&
                                          hue == 2
                                      ? Border.all(
                                          color: scheme.onSurface, width: 2)
                                      : null,
                            ),
                          ),
                      ],
                    ),
                    if (palette != AppPalette.subjectPalettes.last)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The settings with the places the page names: language, design, reminders
/// and this intro.
class SettingsIllustration extends StatelessWidget {
  const SettingsIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    Widget row(IconData icon, String key, Widget trailing,
            {bool highlighted = false}) =>
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: highlighted
              ? BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      highlighted ? scheme.primary : scheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 14,
                  color: highlighted
                      ? scheme.onPrimary
                      : scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.text(key),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(
                    context,
                    size: 12,
                    color: highlighted
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        );

    final chevron =
        Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppDestination.profile.icon,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${l10n.text('sidebar.profile')}  ›  '
                  '${l10n.text('sidebar.settings')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(context, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                row(Icons.translate_rounded, 'tutorial.language.label',
                    _Line(width: 34, color: _faintLine(scheme))),
                row(
                  Icons.auto_awesome_rounded,
                  'settings.design.title',
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.text('settings.design.new'),
                      style: _label(context,
                          size: 10, color: scheme.onSecondaryContainer),
                    ),
                  ),
                ),
                row(
                  Icons.alarm_rounded,
                  'reminders.settings.title',
                  Container(
                    width: 30,
                    height: 18,
                    padding: const EdgeInsets.all(2),
                    alignment: AlignmentDirectional.centerEnd,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: scheme.onPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                row(Icons.explore_outlined, 'tutorial.settings.open', chevron,
                    highlighted: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
