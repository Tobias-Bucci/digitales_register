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
import 'dart:ui' as ui;

import 'package:dr/ui/launch/launch_tokens.dart';
import 'package:flutter/rendering.dart';

/// The animated values of one frame of the launch animation.
///
/// The defaults describe the static logo, i.e. the native splash.
abstract class LaunchFrame {
  /// Drawn fraction of the check; above 1 the tip overshoots its end.
  double get checkProgress => 1;

  /// 0 = text lines at rest, 1 = fully stretched.
  double get lineStretch => 0;

  /// Horizontal offset of binding ring [index], in logo units.
  double ringOffset(int index) => 0;

  /// Position of the light sweep along the check (0–1), or null when off.
  double? get sweepPosition => null;

  /// Opacity of the light sweep.
  double get sweepOpacity => 0;

  /// 1 = full check colour; lower values fade it towards the page colour.
  double get checkEmphasis => 1;

  /// Progress of the circular reveal (0–1).
  double get reveal => 0;

  /// Opacity and scale of the logo while it gives way to the app.
  double get logoOpacity => 1;
  double get logoScale => 1;
}

/// The static logo, as shown by the native splash.
class StaticLaunchFrame extends LaunchFrame {}

/// Paints the launch screen: background, logo and circular reveal.
///
/// The check is a two-segment polyline, so trimming and overshooting it is
/// done analytically with round-capped lines instead of
/// `PathMetric.extractPath`: this allocates no path per frame and can extend
/// the tip beyond the end of the path, which `extractPath` cannot.
class LaunchLogoPainter extends CustomPainter {
  LaunchLogoPainter({
    required this.frame,
    required this.palette,
    required this.logoExtent,
    this.paintBackground = true,
    super.repaint,
  }) {
    _background.color = palette.background;
    _revealRing.color = palette.background;
    _outline.color = palette.outline;
    _fill.color = palette.fill;
    _lines.color = palette.lines;
    _rings.color = palette.green;
  }

  final LaunchFrame frame;
  final LaunchPalette palette;

  /// Edge length of the 1024-unit logo canvas on screen.
  final double logoExtent;

  /// False renders only the logo on transparency (native asset export).
  final bool paintBackground;

  static final Path _fullCheck = Path()
    ..moveTo(LaunchLogoGeometry.checkStart.dx, LaunchLogoGeometry.checkStart.dy)
    ..lineTo(
        LaunchLogoGeometry.checkCorner.dx, LaunchLogoGeometry.checkCorner.dy)
    ..lineTo(LaunchLogoGeometry.checkTip.dx, LaunchLogoGeometry.checkTip.dy);

  static final RRect _outlineShape = RRect.fromRectAndRadius(
      LaunchLogoGeometry.outline,
      const Radius.circular(LaunchLogoGeometry.outlineRadius));

  static final Offset _firstDirection =
      (LaunchLogoGeometry.checkCorner - LaunchLogoGeometry.checkStart) /
          LaunchLogoGeometry.checkFirstLength;
  static final Offset _secondDirection = (LaunchLogoGeometry.checkTip -
          LaunchLogoGeometry.checkCorner) /
      (LaunchLogoGeometry.checkLength - LaunchLogoGeometry.checkFirstLength);

  /// Light band in logo units, slightly tilted against the check.
  static final ui.Shader _sweepShader = ui.Gradient.linear(
    const Offset(-LaunchMotion.sweepWidth / 2, LaunchMotion.sweepWidth * 0.2),
    const Offset(LaunchMotion.sweepWidth / 2, -LaunchMotion.sweepWidth * 0.2),
    const [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    const [0, 0.5, 1],
    TileMode.decal,
  );

  final Paint _background = Paint();
  final Paint _revealRing = Paint()..style = PaintingStyle.stroke;
  final Paint _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = LaunchLogoGeometry.outlineWidth;
  final Paint _fill = Paint();
  final Paint _rings = Paint();
  final Paint _lines = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = LaunchLogoGeometry.lineWidth
    ..strokeCap = StrokeCap.round;
  final Paint _check = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = LaunchLogoGeometry.checkWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _checkDot = Paint();
  final Paint _sweep = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = LaunchLogoGeometry.checkWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..shader = _sweepShader;
  final Paint _layer = Paint();
  final Path _hole = Path();

  /// Logo square centred in [size].
  Rect logoRect(Size size) => Rect.fromCenter(
      center: size.center(Offset.zero), width: logoExtent, height: logoExtent);

  /// Screen position of the check tip, the origin of the reveal.
  Offset revealOrigin(Size size) {
    final rect = logoRect(size);
    final unit = logoExtent / LaunchLogoGeometry.canvas * frame.logoScale;
    return rect.center +
        (LaunchLogoGeometry.checkTip -
                const Offset(LaunchLogoGeometry.canvas / 2,
                    LaunchLogoGeometry.canvas / 2)) *
            unit;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final reveal = frame.reveal;
    final origin = revealOrigin(size);
    final reach = _farthestCorner(origin, size);
    final radius = reach * reveal;

    if (paintBackground) {
      if (reveal <= 0) {
        canvas.drawRect(bounds, _background);
      } else if (radius < reach) {
        // A stroked circle whose inner edge is the hole covers everything
        // outside of it without building a path.
        final width = reach - radius + 2;
        _revealRing.strokeWidth = width;
        canvas.drawCircle(origin, radius + width / 2, _revealRing);
      }
    }

    final opacity = frame.logoOpacity;
    if (opacity <= 0) return;
    canvas.save();
    if (reveal > 0) {
      // reset() also restores the default fill type.
      _hole
        ..reset()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addOval(Rect.fromCircle(center: origin, radius: radius));
      canvas.clipPath(_hole);
    }
    final rect = logoRect(size);
    if (opacity < 1) {
      _layer.color = Color.fromRGBO(0, 0, 0, opacity);
      canvas.saveLayer(rect.inflate(logoExtent * 0.1), _layer);
    }
    canvas
      ..translate(rect.center.dx, rect.center.dy)
      ..scale(logoExtent / LaunchLogoGeometry.canvas * frame.logoScale)
      ..translate(
          -LaunchLogoGeometry.canvas / 2, -LaunchLogoGeometry.canvas / 2);
    _paintLogo(canvas);
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  void _paintLogo(Canvas canvas) {
    canvas
      ..drawRRect(_outlineShape, _fill)
      ..drawRRect(_outlineShape, _outline);

    for (var i = 0; i < LaunchLogoGeometry.ringTops.length; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          LaunchLogoGeometry.ringLeft + frame.ringOffset(i),
          LaunchLogoGeometry.ringTops[i],
          LaunchLogoGeometry.ringLeft +
              LaunchLogoGeometry.ringWidth +
              frame.ringOffset(i),
          LaunchLogoGeometry.ringTops[i] + LaunchLogoGeometry.ringHeight,
          const Radius.circular(LaunchLogoGeometry.ringRadius),
        ),
        _rings,
      );
    }

    final stretch = 1 + LaunchMotion.lineStretch * frame.lineStretch;
    for (var i = 0; i < LaunchLogoGeometry.lineYs.length; i++) {
      final end = LaunchLogoGeometry.lineStart +
          (LaunchLogoGeometry.lineEnds[i] - LaunchLogoGeometry.lineStart) *
              stretch;
      canvas.drawLine(
          Offset(LaunchLogoGeometry.lineStart, LaunchLogoGeometry.lineYs[i]),
          Offset(end, LaunchLogoGeometry.lineYs[i]),
          _lines);
    }

    _paintCheck(canvas);
  }

  void _paintCheck(Canvas canvas) {
    final color = Color.lerp(palette.fill, palette.green,
        frame.checkEmphasis.clamp(0, 1).toDouble())!;
    _check.color = color;
    _checkDot.color = color;

    final length =
        LaunchLogoGeometry.checkLength * math.max(0, frame.checkProgress);
    if (length < 0.5) {
      // Zero-length round-capped lines are not drawn by every backend.
      canvas.drawCircle(LaunchLogoGeometry.checkStart,
          LaunchLogoGeometry.checkWidth / 2, _checkDot);
    } else if (length <= LaunchLogoGeometry.checkFirstLength) {
      canvas.drawLine(LaunchLogoGeometry.checkStart,
          LaunchLogoGeometry.checkStart + _firstDirection * length, _check);
    } else {
      // Two round-capped lines meet in a round join, like the stroked path.
      canvas
        ..drawLine(LaunchLogoGeometry.checkStart,
            LaunchLogoGeometry.checkCorner, _check)
        ..drawLine(
            LaunchLogoGeometry.checkCorner,
            LaunchLogoGeometry.checkCorner +
                _secondDirection *
                    (length - LaunchLogoGeometry.checkFirstLength),
            _check);
    }

    final sweep = frame.sweepPosition;
    if (sweep == null || frame.sweepOpacity <= 0) return;
    // The shader is fixed in local space; moving the canvas against the check
    // keeps a single shader for the whole animation. The shifted path is the
    // only per-frame allocation and exists only for the ~260 ms of the sweep;
    // one path (not two lines) avoids a brighter overlap at the corner.
    final band = Offset(
      ui.lerpDouble(LaunchLogoGeometry.checkStart.dx - LaunchMotion.sweepWidth,
          LaunchLogoGeometry.checkTip.dx + LaunchMotion.sweepWidth, sweep)!,
      ui.lerpDouble(LaunchLogoGeometry.checkCorner.dy,
          LaunchLogoGeometry.checkTip.dy, sweep)!,
    );
    _sweep.color = palette.highlight.withValues(alpha: frame.sweepOpacity);
    canvas
      ..save()
      ..translate(band.dx, band.dy)
      ..drawPath(_fullCheck.shift(-band), _sweep)
      ..restore();
  }

  static double _farthestCorner(Offset origin, Size size) {
    final dx = math.max(origin.dx, size.width - origin.dx);
    final dy = math.max(origin.dy, size.height - origin.dy);
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool shouldRepaint(LaunchLogoPainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.palette != palette ||
      oldDelegate.logoExtent != logoExtent ||
      oldDelegate.paintBackground != paintBackground;
}
