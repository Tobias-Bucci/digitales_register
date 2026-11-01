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

// ignore_for_file: avoid_classes_with_only_static_members

/// Timings, curves, colours and logo geometry of the launch animation.
///
/// Every tunable value of the opening animation lives here. The native splash
/// assets (Android vector drawables, iOS launch images) are generated from the
/// same geometry and colours by `tool/launch_assets/generate_test.dart`, so the
/// first Flutter frame and the native splash are identical.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:dr/theme/app_palette.dart';
import 'package:flutter/animation.dart';

/// Phase boundaries of the choreography.
abstract final class LaunchTimings {
  /// Still frame, identical to the native splash.
  static const Duration rest = Duration(milliseconds: 300);

  /// The check retracts while the text lines stretch.
  static const Duration breatheEnd = Duration(milliseconds: 800);

  /// The check redraws with a spring overshoot; the light sweep runs late in
  /// this phase.
  static const Duration redrawEnd = Duration(milliseconds: 1300);

  /// Circular reveal from the check tip into the app.
  static const Duration reveal = Duration(milliseconds: 500);

  /// Reveal after a tap or key press.
  static const Duration skippedReveal = Duration(milliseconds: 320);

  /// How long a skip takes to fast-forward the remaining intro.
  static const Duration skipFastForward = Duration(milliseconds: 220);

  /// Each binding ring starts this much later than the one above it.
  static const Duration ringStagger = Duration(milliseconds: 40);

  /// Length of a single ring nudge.
  static const Duration ringNudge = Duration(milliseconds: 360);

  /// Light sweep across the check while it settles.
  static const Duration sweepStart = Duration(milliseconds: 1040);
  static const Duration sweepEnd = Duration(milliseconds: 1300);

  /// One full breath of the waiting loop while sign-in is still running.
  static const Duration holdPulse = Duration(milliseconds: 1600);

  /// Cross-fade used instead of the choreography with reduced motion.
  static const Duration reducedFade = Duration(milliseconds: 300);

  /// Total intro before the reveal can start.
  static Duration get intro => redrawEnd;

  /// Fraction of the intro at [time].
  static double at(Duration time) => time.inMicroseconds / intro.inMicroseconds;
}

/// Curves of the choreography. None of the movements is linear.
abstract final class LaunchCurves {
  static const Curve retract = Curves.easeInOutCubic;
  static const Curve stretch = Curves.easeInOutSine;
  static const Curve ringNudge = Curves.easeInOutSine;
  static const Curve redraw = LaunchSpringCurve();
  static const Curve sweep = Cubic(0.45, 0, 0.25, 1);
  static const Curve reveal = Curves.easeInOutCubicEmphasized;
  static const Curve logoFade = Interval(0, 0.7, curve: Curves.easeOutCubic);
  static const Curve logoScale = Curves.easeOutCubic;
  static const Curve fastForward = Curves.easeOutCubic;
  static const Curve hold = Curves.easeInOutSine;
  static const Curve reducedFade = Curves.easeOutCubic;
}

/// Magnitudes of the individual movements.
abstract final class LaunchMotion {
  /// The text lines grow by this fraction of their length.
  static const double lineStretch = 0.08;

  /// Horizontal nudge of each binding ring, in logo units.
  static const double ringNudge = 10;

  /// Peak opacity of the light sweep.
  static const double sweepOpacity = 0.15;

  /// Width of the light band, in logo units.
  static const double sweepWidth = 220;

  /// The logo shrinks to this scale while the reveal uncovers the app.
  static const double revealScale = 0.92;

  /// Lowest opacity of the check in the waiting loop.
  static const double holdOpacity = 0.62;

  /// Damping ratio of the redraw spring; below 1 it overshoots once.
  static const double springDamping = 0.72;

  /// Undamped angular frequency of the redraw spring, per curve unit.
  static const double springFrequency = 11.0;
}

/// Size of the logo square on screen.
abstract final class LaunchLayout {
  /// Mobile size; must match the native splash (`launch_logo` drawables and
  /// iOS `LaunchImage`).
  static const double mobileExtent = 160;

  /// Android 12+ draws the splash icon at this size and masks it to a
  /// circle of [androidSplashMask]; the logo keeps [mobileExtent] inside it.
  static const double androidSplashIcon = 288;
  static const double androidSplashMask = 192;

  /// Desktop size relative to the shorter window side, clamped.
  static const double desktopFraction = 0.28;
  static const double desktopMinExtent = 160;
  static const double desktopMaxExtent = 320;
}

/// Colours of one appearance of the launch screen.
class LaunchPalette {
  const LaunchPalette({
    required this.background,
    required this.outline,
    required this.fill,
    required this.lines,
    required this.green,
    required this.highlight,
  });

  final Color background;
  final Color outline;
  final Color fill;
  final Color lines;
  final Color green;
  final Color highlight;

  /// Exact colours of `assets/index.png`. The background is the light app
  /// surface so the reveal does not change the tone behind the logo.
  static final LaunchPalette light = LaunchPalette(
    background: AppPalette.light.surface,
    outline: const Color(0xFF1E2D3D),
    fill: const Color(0xFFFFFFFF),
    lines: const Color(0xFFB0BBC6),
    green: const Color(0xFF2E6B4F),
    highlight: const Color(0xFFFFFFFF),
  );

  /// Night variant: the notebook keeps its shape but turns into a dark page
  /// with a light outline, so it does not glare on the dark surface.
  static final LaunchPalette dark = LaunchPalette(
    background: AppPalette.dark.surface,
    outline: const Color(0xFFD3DCE6),
    fill: const Color(0xFF1B2431),
    lines: const Color(0xFF5A6878),
    green: const Color(0xFF4C9A6E),
    highlight: const Color(0xFFFFFFFF),
  );

  static LaunchPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Geometry of the logo in the 1024 × 1024 coordinate space of
/// `assets/index.png`, measured from that file.
abstract final class LaunchLogoGeometry {
  static const double canvas = 1024;

  /// Centre line of the notebook outline.
  static const Rect outline = Rect.fromLTRB(112, 112, 912, 912);
  static const double outlineRadius = 128;
  static const double outlineWidth = 40;

  /// Binding rings on the left edge.
  static const double ringLeft = 48;
  static const double ringWidth = 96;
  static const double ringHeight = 56;
  static const double ringRadius = 12;
  static const List<double> ringTops = [296, 420, 544];

  /// Text lines: left end, right end and centre of the round-capped strokes.
  static const double lineStart = 262;
  static const double lineWidth = 44;
  static const List<double> lineEnds = [590, 498];
  static const List<double> lineYs = [326, 406];

  /// Polyline of the check, stroked with round caps and joins.
  static const Offset checkStart = Offset(268, 612);
  static const Offset checkCorner = Offset(400, 744);
  static const Offset checkTip = Offset(780, 364);
  static const double checkWidth = 88;

  static double get checkFirstLength => (checkCorner - checkStart).distance;
  static double get checkLength =>
      checkFirstLength + (checkTip - checkCorner).distance;

  /// Furthest point of the logo from the canvas centre; the Android 12 icon
  /// mask must contain it.
  static double get maxRadius {
    const corner = Offset(112 + 128, 112 + 128);
    return (corner - const Offset(canvas / 2, canvas / 2)).distance +
        outlineRadius +
        outlineWidth / 2;
  }
}

/// A critically under-damped spring from 0 to 1 that overshoots slightly.
///
/// Unlike [Curves.elasticOut] it overshoots only once, which keeps the
/// motion calm.
class LaunchSpringCurve extends Curve {
  const LaunchSpringCurve({
    this.damping = LaunchMotion.springDamping,
    this.frequency = LaunchMotion.springFrequency,
  });

  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) {
    final damped = frequency * math.sqrt(1 - damping * damping);
    final decay = math.exp(-damping * frequency * t);
    final value = 1 -
        decay *
            (math.cos(damped * t) +
                damping * frequency / damped * math.sin(damped * t));
    // Lands exactly on 1 so the last frame matches the static logo.
    return t >= 1 ? 1 : value;
  }
}
