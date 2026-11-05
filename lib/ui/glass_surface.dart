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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared shape tokens of the new design: containers use the corner radius of
/// the dashboard cards, single-line controls are pills.
abstract final class DesignTokens {
  static const double cardRadius = 16;
  static const double gutter = 12;
  static const BorderRadius cardBorderRadius =
      BorderRadius.all(Radius.circular(cardRadius));

  /// How opaque the glass is. High enough that text keeps WCAG AA contrast even
  /// with content of the opposite brightness below and no blur at all.
  static const double headerOpacity = 0.85;
  static const double navigationBarOpacity = 0.9;

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

/// A frosted surface: a translucent [tint] over a blurred backdrop.
///
/// With [blur] off, in high contrast mode or once [GlassPerformance] has turned
/// blur off, it falls back to the same tint as a solid colour. Text on it
/// therefore has to meet its contrast on both.
class GlassSurface extends StatefulWidget {
  const GlassSurface({
    super.key,
    required this.tint,
    required this.child,
    this.opacity = DesignTokens.headerOpacity,
    this.blur = true,
    this.borderRadius = BorderRadius.zero,
    this.border,
  });

  final Color tint;
  final double opacity;
  final bool blur;
  final BorderRadius borderRadius;
  final BoxBorder? border;
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
          child: child,
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
