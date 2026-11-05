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

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Shared shape tokens of the new design: containers use the corner radius of
/// the dashboard cards, single-line controls are pills.
abstract final class DesignTokens {
  static const double cardRadius = 16;
  static const double gutter = 12;
  static const BorderRadius cardBorderRadius =
      BorderRadius.all(Radius.circular(cardRadius));

  /// How opaque the glass is. High enough that text keeps WCAG AA contrast even
  /// with content of the opposite brightness below and no blur at all.
  static const double headerOpacity = 0.8;
  static const double navigationBarOpacity = 0.84;
  static const double sheetOpacity = 0.88;

  /// The fill of controls that stay in the list, so without blur. They only
  /// ever lie on the page or on the summary box, never over content.
  static const double controlOpacity = 0.62;

  /// Dashboard content stops growing here, so that a row stays readable in a
  /// wide desktop window.
  static const double contentMaxWidth = 840;
}

/// Decides whether blur is affordable on this device.
///
/// A blurred backdrop is re-rendered in every frame of a scroll, which a
/// low-end GPU may not manage. Instead of guessing from a device list, this
/// watches the time the raster thread really needs and permanently turns blur
/// off for the session once too many frames have missed their budget.
class GlassPerformance {
  GlassPerformance._();

  static final GlassPerformance instance = GlassPerformance._();

  static const _sampleSize = 120;
  static const _frameBudget = Duration(milliseconds: 16);
  static const _maxSlowShare = 0.25;

  /// Whether surfaces may blur what is behind them.
  final ValueNotifier<bool> blurAllowed = ValueNotifier(true);

  bool _watching = false;
  int _frames = 0;
  int _slowFrames = 0;

  void watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      record(timing.rasterDuration);
    }
  }

  /// Takes the raster duration of one frame into account.
  @visibleForTesting
  void record(Duration rasterDuration) {
    if (!blurAllowed.value) return;
    _frames++;
    if (rasterDuration > _frameBudget) _slowFrames++;
    if (_frames < _sampleSize) return;
    if (_slowFrames / _frames > _maxSlowShare) {
      blurAllowed.value = false;
      if (_watching) {
        SchedulerBinding.instance.removeTimingsCallback(_onTimings);
        _watching = false;
      }
    }
    _frames = 0;
    _slowFrames = 0;
  }

  @visibleForTesting
  void reset() {
    blurAllowed.value = true;
    _frames = 0;
    _slowFrames = 0;
  }
}

/// How light falls on the glass of the new design, in roles of the theme: from
/// straight above, so that every surface is lit the same on its left and right.
/// The upper edge catches the light, and it fades towards the lower edge, which
/// keeps a faint reflection (dark) or a soft shade (light).
@immutable
class GlassLight {
  const GlassLight._({
    required this.highlight,
    required this.shade,
    required this.rimStrength,
    required this.shadeStrength,
    required this.sheenStrength,
  });

  factory GlassLight.of(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return GlassLight._(
      highlight: dark ? scheme.onSurface : scheme.surfaceContainerLowest,
      shade: dark ? scheme.onSurface : scheme.outline,
      rimStrength: dark ? 0.42 : 0.95,
      shadeStrength: dark ? 0.1 : 0.26,
      sheenStrength: dark ? 0.06 : 0.26,
    );
  }

  final Color highlight, shade;
  final double rimStrength, shadeStrength, sheenStrength;

  @override
  bool operator ==(Object other) =>
      other is GlassLight &&
      other.highlight == highlight &&
      other.shade == shade &&
      other.rimStrength == rimStrength &&
      other.shadeStrength == shadeStrength &&
      other.sheenStrength == sheenStrength;

  @override
  int get hashCode =>
      Object.hash(highlight, shade, rimStrength, shadeStrength, sheenStrength);
}

/// Where a surface shows the rim of its glass.
enum GlassRim {
  none,

  /// All around, for floating surfaces.
  around,

  /// A line along the lower edge, for surfaces that run from edge to edge.
  bottom,
}

/// The glass of a surface without the blur: a thin rim that catches the light
/// and a soft sheen. It costs two gradients and no backdrop, so unlike blur it
/// may also be used in a scrolling list.
///
/// In high contrast mode it leaves [child] alone.
class GlassEdge extends StatelessWidget {
  const GlassEdge({
    super.key,
    required this.shape,
    required this.child,
    this.rim = GlassRim.around,
    this.sheen = true,
  });

  final ShapeBorder shape;
  final GlassRim rim;
  final bool sheen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return child;
    final light = GlassLight.of(Theme.of(context).colorScheme);
    return CustomPaint(
      painter: sheen ? GlassSheenPainter(shape: shape, light: light) : null,
      foregroundPainter: rim == GlassRim.none
          ? null
          : GlassRimPainter(shape: shape, rim: rim, light: light),
      child: child,
    );
  }
}

/// [GlassEdge] on a card of the new design, for a card that also serves Legacy.
class GlassEdgeIf extends StatelessWidget {
  const GlassEdgeIf({
    super.key,
    required this.enabled,
    required this.child,
    this.rim = GlassRim.around,
    this.sheen = true,
    this.shape = const RoundedRectangleBorder(
      borderRadius: DesignTokens.cardBorderRadius,
    ),
  });

  final bool enabled, sheen;
  final GlassRim rim;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => enabled
      ? GlassEdge(
          shape: shape,
          rim: rim,
          sheen: sheen,
          child: child,
        )
      : child;
}

/// Light on the upper part of the glass.
class GlassSheenPainter extends CustomPainter {
  const GlassSheenPainter({required this.shape, required this.light});

  static const double _maxDepth = 72;

  final ShapeBorder shape;
  final GlassLight light;

  /// Straight down, so that the left and right of a surface stay the same.
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          light.highlight.withValues(alpha: light.sheenStrength),
          light.highlight.withValues(alpha: 0),
        ],
      );

  @override
  void paint(Canvas canvas, Size size) {
    final top = Rect.fromLTWH(
      0,
      0,
      size.width,
      math.min(size.height * 0.6, _maxDepth),
    );
    canvas
      ..save()
      ..clipPath(shape.getOuterPath(Offset.zero & size))
      ..drawRect(top, Paint()..shader = gradient.createShader(top))
      ..restore();
  }

  // Taps belong to whatever lies below the light.
  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(GlassSheenPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.light != light;
}

/// The specular edge: brightest along the top and fading evenly down both
/// sides, the same on the left and on the right.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({
    required this.shape,
    required this.rim,
    required this.light,
  });

  /// How far down the highlight fades, whatever the height of the surface. A
  /// small button and a tall sheet are thereby lit with the same emphasis.
  static const double _fadeDepth = 56;

  final ShapeBorder shape;
  final GlassRim rim;
  final GlassLight light;

  /// The light of [GlassRim.around] on a surface of [height].
  LinearGradient aroundGradient(double height) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, math.min(1, _fadeDepth / height), 1],
        colors: [
          light.highlight.withValues(alpha: light.rimStrength),
          light.highlight.withValues(alpha: light.rimStrength * 0.2),
          light.shade.withValues(alpha: light.shadeStrength),
        ],
      );

  /// The light of [GlassRim.bottom], which is widest in the middle.
  LinearGradient get bottomGradient => LinearGradient(
        colors: [
          light.highlight.withValues(alpha: 0),
          light.highlight.withValues(alpha: light.rimStrength),
          light.highlight.withValues(alpha: 0),
        ],
      );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (rim == GlassRim.bottom) {
      final y = size.height - 0.5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        stroke..shader = bottomGradient.createShader(rect),
      );
      return;
    }
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(0.5)),
      stroke..shader = aroundGradient(size.height).createShader(rect),
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(GlassRimPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.rim != rim ||
      oldDelegate.light != light;
}

/// [shape] with the rim of the glass, for places that only take a shape, such
/// as dialogs and the indicator of a navigation rail.
class GlassRimBorder extends ShapeBorder {
  const GlassRimBorder({required this.shape, required this.light});

  final ShapeBorder shape;
  final GlassLight light;

  @override
  EdgeInsetsGeometry get dimensions => shape.dimensions;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    shape.paint(canvas, rect, textDirection: textDirection);
    canvas
      ..save()
      ..translate(rect.left, rect.top);
    GlassRimPainter(shape: shape, rim: GlassRim.around, light: light)
        .paint(canvas, rect.size);
    canvas.restore();
  }

  @override
  ShapeBorder scale(double t) =>
      GlassRimBorder(shape: shape.scale(t), light: light);

  @override
  bool operator ==(Object other) =>
      other is GlassRimBorder && other.shape == shape && other.light == light;

  @override
  int get hashCode => Object.hash(shape, light);
}

/// What everything below it shares in the new design. Dialogs and sheets take
/// over the theme of the place they are opened from, which keeps Legacy out.
///
/// Dialogs get the rim of the glass, and whatever can be clicked gets the hand
/// cursor, which Flutter leaves out in native desktop apps.
class NewDesignTheme extends StatelessWidget {
  const NewDesignTheme({super.key, required this.child});

  /// For the places that are not covered by a theme of a component.
  static const MouseCursor clickCursor = WidgetStateMouseCursor.clickable;

  static const _clickable = ButtonStyle(
    mouseCursor: WidgetStatePropertyAll(clickCursor),
  );

  final Widget child;

  ButtonStyle _clickableStyle(ButtonStyle? style) =>
      style?.merge(_clickable) ?? _clickable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dialogTheme: MediaQuery.highContrastOf(context)
            ? null
            : theme.dialogTheme.copyWith(
                shape: GlassRimBorder(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                  light: GlassLight.of(theme.colorScheme),
                ),
              ),
        filledButtonTheme: FilledButtonThemeData(
          style: _clickableStyle(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: _clickableStyle(theme.outlinedButtonTheme.style),
        ),
        textButtonTheme: TextButtonThemeData(
          style: _clickableStyle(theme.textButtonTheme.style),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: _clickableStyle(theme.elevatedButtonTheme.style),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: _clickableStyle(theme.iconButtonTheme.style),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          mouseCursor: const WidgetStatePropertyAll(clickCursor),
        ),
        checkboxTheme: theme.checkboxTheme.copyWith(
          mouseCursor: const WidgetStatePropertyAll(clickCursor),
        ),
        radioTheme: theme.radioTheme.copyWith(
          mouseCursor: const WidgetStatePropertyAll(clickCursor),
        ),
        switchTheme: theme.switchTheme.copyWith(
          mouseCursor: const WidgetStatePropertyAll(clickCursor),
        ),
      ),
      child: child,
    );
  }
}

/// A clear ring around [child] while the keyboard is inside of it. On glass, the
/// usual focus tint of Material is too faint to find. It lies just outside of
/// [shape], on the page, where it has the same contrast on every kind of fill.
class GlassFocusRing extends StatefulWidget {
  const GlassFocusRing({super.key, required this.shape, required this.child});

  final ShapeBorder shape;
  final Widget child;

  @override
  State<GlassFocusRing> createState() => _GlassFocusRingState();
}

class _GlassFocusRingState extends State<GlassFocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CustomPaint(
        foregroundPainter: _focused && keyboard
            ? GlassFocusRingPainter(
                shape: widget.shape,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

class GlassFocusRingPainter extends CustomPainter {
  const GlassFocusRingPainter({required this.shape, required this.color});

  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      shape.getOuterPath((Offset.zero & size).inflate(1.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(GlassFocusRingPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

/// The ring of [GlassFocusRing] for buttons, which report their own focus.
WidgetStateProperty<BorderSide?> glassFocusSide(ColorScheme scheme) =>
    WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: scheme.primary, width: 2)
          : null,
    );

/// The look of a small control on a list: tonal glass without blur. As a theme
/// for filled buttons or merged into the style of an icon button.
ButtonStyle glassControlStyle(
  ColorScheme scheme, {
  OutlinedBorder shape = const StadiumBorder(),
}) =>
    ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.08)
            : scheme.secondaryContainer
                .withValues(alpha: DesignTokens.controlOpacity),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : scheme.onSecondaryContainer,
      ),
      side: glassFocusSide(scheme),
      mouseCursor: const WidgetStatePropertyAll(NewDesignTheme.clickCursor),
      backgroundBuilder: (context, states, child) => GlassEdge(
        shape: shape,
        child: child ?? const SizedBox.shrink(),
      ),
    );

/// A frosted surface: a translucent [tint] over a blurred backdrop.
///
/// With [blur] off, in high contrast mode or once [GlassPerformance] has turned
/// blur off, it falls back to the same tint as a solid colour. Text on it
/// therefore has to meet its contrast on both. The [rim] stays in that case,
/// because it costs next to nothing, except in high contrast mode.
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.tint,
    required this.child,
    this.opacity = DesignTokens.headerOpacity,
    this.blur = true,
    this.borderRadius = BorderRadius.zero,
    this.border,
    this.rim = GlassRim.none,
  });

  final Color tint;
  final double opacity;
  final bool blur;
  final BorderRadius borderRadius;
  final BoxBorder? border;
  final GlassRim rim;
  final Widget child;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  @override
  void initState() {
    super.initState();
    if (widget.blur) GlassPerformance.instance.watch();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = MediaQuery.highContrastOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: GlassPerformance.instance.blurAllowed,
      builder: (context, blurAllowed, child) {
        final blur = widget.blur && blurAllowed && !highContrast;
        final surface = DecoratedBox(
          decoration: BoxDecoration(
            color: widget.tint.withValues(
              alpha:
                  blur || (!highContrast && !widget.blur) ? widget.opacity : 1,
            ),
            borderRadius: widget.borderRadius,
            border: widget.border,
          ),
          child: widget.rim == GlassRim.none
              ? child
              : GlassEdge(
                  shape: RoundedRectangleBorder(
                    borderRadius: widget.borderRadius,
                  ),
                  rim: widget.rim,
                  child: child!,
                ),
        );
        if (!blur) return surface;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: BackdropFilter.grouped(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: surface,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A bar of glass that floats above the page, like the navigation.
class FloatingGlass extends StatelessWidget {
  const FloatingGlass({
    super.key,
    required this.surfaceKey,
    required this.tint,
    required this.opacity,
    required this.child,
  });

  static const double thickness = 56;
  static const _radius = BorderRadius.all(Radius.circular(thickness / 2));

  final Key surfaceKey;
  final Color tint;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: GlassSurface(
        key: surfaceKey,
        tint: tint,
        opacity: opacity,
        borderRadius: _radius,
        rim: GlassRim.around,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
        child: child,
      ),
    );
  }
}

/// A modal sheet of glass, which becomes a centred panel of the same glass in
/// wide windows. With [glass] off, which keeps the Legacy design as it is, this
/// is a plain [showModalBottomSheet].
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool glass = true,
  bool useRootNavigator = true,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) {
  if (!glass) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      builder: builder,
    );
  }
  if (MediaQuery.sizeOf(context).width >= tabletLayoutBreakpoint) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape:
            const RoundedRectangleBorder(borderRadius: GlassSheet.panelRadius),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: GlassSheet.panelMaxWidth),
          child: GlassSheet.panel(child: builder(context)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => GlassSheet(
      showDragHandle: showDragHandle,
      child: builder(context),
    ),
  );
}

/// The body of [showGlassSheet]. It covers what is below it and does not scroll
/// over it, so its blur stays affordable.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.showDragHandle,
    required this.child,
  }) : _panel = false;

  /// As a centred panel, which has no use for a handle.
  const GlassSheet.panel({super.key, required this.child})
      : showDragHandle = false,
        _panel = true;

  static const panelMaxWidth = 520.0;
  static const panelRadius = BorderRadius.all(Radius.circular(28));
  static const _sheetRadius = BorderRadius.vertical(top: Radius.circular(28));

  final bool showDragHandle, _panel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final glass = GlassSurface(
      key: const Key('glass-sheet'),
      tint: scheme.surfaceContainer,
      opacity: DesignTokens.sheetOpacity,
      borderRadius: _panel ? panelRadius : _sheetRadius,
      rim: GlassRim.around,
      // Below a light sheet lies the dark scrim, on which the primary colour
      // would no longer reach the contrast of text.
      child: Theme(
        data: theme.copyWith(
          colorScheme: scheme.copyWith(primary: scheme.onPrimaryContainer),
        ),
        // Ink has to be painted on top of the tint.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDragHandle) const _SheetHandle(),
              if (_panel) const SizedBox(height: 20),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
    if (!_panel) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: panelRadius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: glass,
    );
  }
}

/// The handle of a Material sheet, which only that sheet's own surface can show.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      onTap: () => Navigator.of(context).maybePop(),
      child: SizedBox(
        height: 40,
        child: Center(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              shape: const StadiumBorder(),
            ),
            child: const SizedBox(width: 32, height: 4),
          ),
        ),
      ),
    );
  }
}
