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

import 'dart:async';
import 'dart:math' as math;

import 'package:dr/ui/launch/launch_logo_painter.dart';
import 'package:dr/ui/launch/launch_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How the launch animation is played.
enum LaunchAnimationMode {
  /// The full choreography.
  full,

  /// A short fade, used when the platform asks for reduced motion.
  reduced,

  /// No overlay at all.
  off;

  /// `--dart-define=DR_LAUNCH_ANIMATION=full|reduced|off` forces a mode;
  /// without it the platform's reduced-motion setting decides.
  static LaunchAnimationMode resolve() {
    switch (const String.fromEnvironment('DR_LAUNCH_ANIMATION')) {
      case 'full':
        return full;
      case 'reduced':
        return reduced;
      case 'off':
        return off;
    }
    return WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.disableAnimations
        ? reduced
        : full;
  }
}

/// Opens once the start-up routing has decided between login and dashboard.
class AppLaunchGate {
  final Completer<void> _opened = Completer<void>();

  Future<void> get opened => _opened.future;
  bool get isOpen => _opened.isCompleted;

  void open() {
    if (!_opened.isCompleted) _opened.complete();
  }
}

/// Gate of the cold start; opened by the start-up middleware.
final AppLaunchGate appLaunchGate = AppLaunchGate();

/// True while the launch overlay covers the app.
final ValueNotifier<bool> appLaunchInProgress = ValueNotifier(false);

/// Edge length of the logo canvas on a screen of [size].
double launchLogoExtent(Size size) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return LaunchLayout.mobileExtent;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return (size.shortestSide * LaunchLayout.desktopFraction)
          .clamp(LaunchLayout.desktopMinExtent, LaunchLayout.desktopMaxExtent);
  }
}

/// Waits until the top route of [navigator] has finished its transition, at
/// most [maxFrames] frames.
Future<void> waitForRouteTransition(NavigatorState? Function() navigator,
    {int maxFrames = 120}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    await WidgetsBinding.instance.endOfFrame;
    Route<dynamic>? top;
    // The current route is not exposed otherwise; nothing is popped.
    navigator()?.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    if (route is! ModalRoute || route.animation?.isCompleted != false) return;
  }
}

/// Plays the opening animation over [child] and removes itself afterwards.
///
/// The overlay starts exactly like the native splash, animates the logo and
/// then uncovers [child] with a circular reveal from the check tip. The reveal
/// waits for [targetReady]; until then the check breathes gently. A tap or a
/// key press fast-forwards the animation.
class AppLaunchAnimation extends StatefulWidget {
  const AppLaunchAnimation({
    super.key,
    required this.child,
    required this.targetReady,
    this.onFinished,
    this.mode,
  });

  final Widget child;

  /// Completes when the target screen (login or dashboard) is in place.
  final Future<void> targetReady;

  /// Called once the overlay has been removed.
  final VoidCallback? onFinished;

  /// Overrides [LaunchAnimationMode.resolve].
  final LaunchAnimationMode? mode;

  @override
  State<AppLaunchAnimation> createState() => _AppLaunchAnimationState();
}

class _AppLaunchAnimationState extends State<AppLaunchAnimation>
    with TickerProviderStateMixin
    implements LaunchFrame {
  late final LaunchAnimationMode _mode =
      widget.mode ?? LaunchAnimationMode.resolve();
  late final AnimationController _intro =
      _controller(duration: LaunchTimings.intro);
  late final AnimationController _hold =
      _controller(duration: LaunchTimings.holdPulse ~/ 2);
  late final AnimationController _reveal =
      _controller(duration: LaunchTimings.reveal);
  late final Listenable _frames = Listenable.merge([_intro, _hold, _reveal]);
  late final Animation<double> _reducedOpacity = ReverseAnimation(
      CurvedAnimation(parent: _reveal, curve: LaunchCurves.reducedFade));
  late final LaunchPalette _palette = LaunchPalette.of(
      WidgetsBinding.instance.platformDispatcher.platformBrightness);

  // Reduced motion is handled by [LaunchAnimationMode]; the controllers must
  // not additionally shrink the fade to 5 % of its length.
  AnimationController _controller({required Duration duration}) =>
      AnimationController(
        vsync: this,
        duration: duration,
        animationBehavior: AnimationBehavior.preserve,
      );

  bool _ready = false;
  bool _skipped = false;
  bool _revealing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (_mode == LaunchAnimationMode.off) {
      _finished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyFinished());
      return;
    }
    appLaunchInProgress.value = true;
    HardwareKeyboard.instance.addHandler(_handleKey);
    if (_mode == LaunchAnimationMode.full) {
      _intro.forward().whenComplete(_advance);
    }
    widget.targetReady.then<void>((_) => _onReady(), onError: (Object _) {
      _onReady();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _intro.dispose();
    _hold.dispose();
    _reveal.dispose();
    if (!_finished) appLaunchInProgress.value = false;
    super.dispose();
  }

  void _onReady() {
    if (!mounted) return;
    _ready = true;
    _advance();
  }

  /// Moves on to the next phase once the current one allows it.
  void _advance() {
    if (!mounted || _revealing || _finished) return;
    final introDone = _mode != LaunchAnimationMode.full || _intro.isCompleted;
    if (!introDone) return;
    if (!_ready) {
      if (_mode == LaunchAnimationMode.full && !_hold.isAnimating) {
        _hold.repeat(reverse: true);
      }
      return;
    }
    if (_hold.value > 0) {
      // Let the breathing check settle back to full colour first.
      final duration = _hold.duration! * _hold.value;
      _hold
          .animateBack(0, duration: duration, curve: LaunchCurves.hold)
          .whenComplete(_startReveal);
    } else {
      _hold.stop();
      _startReveal();
    }
  }

  void _startReveal() {
    if (!mounted || _revealing) return;
    setState(() => _revealing = true);
    _reveal.duration = switch (_mode) {
      LaunchAnimationMode.reduced => LaunchTimings.reducedFade,
      _ when _skipped => LaunchTimings.skippedReveal,
      _ => LaunchTimings.reveal,
    };
    _reveal.forward().whenComplete(_finish);
  }

  void _finish() {
    if (!mounted || _finished) return;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    setState(() => _finished = true);
    _notifyFinished();
  }

  void _notifyFinished() {
    appLaunchInProgress.value = false;
    widget.onFinished?.call();
  }

  void _skip() {
    if (_finished || _revealing || _skipped) return;
    _skipped = true;
    if (_mode == LaunchAnimationMode.full && _intro.isAnimating) {
      final remaining = 1 - _intro.value;
      _intro
          .animateTo(1,
              duration: LaunchTimings.skipFastForward * remaining,
              curve: LaunchCurves.fastForward)
          .whenComplete(_advance);
    } else {
      _advance();
    }
  }

  bool _handleKey(KeyEvent event) {
    if (_finished) return false;
    if (event is KeyDownEvent) _skip();
    return event is KeyDownEvent;
  }

  // LaunchFrame: the values the painter reads on every frame.

  double get _time => _intro.value * LaunchTimings.intro.inMicroseconds / 1000;

  static double _ms(Duration duration) => duration.inMicroseconds / 1000;

  static double _phase(double time, Duration start, Duration end) =>
      ((time - _ms(start)) / (_ms(end) - _ms(start))).clamp(0, 1).toDouble();

  @override
  double get checkProgress {
    final time = _time;
    if (time <= _ms(LaunchTimings.breatheEnd)) {
      return 1 -
          LaunchCurves.retract.transform(
              _phase(time, LaunchTimings.rest, LaunchTimings.breatheEnd));
    }
    return LaunchCurves.redraw.transform(
        _phase(time, LaunchTimings.breatheEnd, LaunchTimings.redrawEnd));
  }

  @override
  double get lineStretch {
    final time = _time;
    if (time <= _ms(LaunchTimings.breatheEnd)) {
      return LaunchCurves.stretch.transform(
          _phase(time, LaunchTimings.rest, LaunchTimings.breatheEnd));
    }
    return 1 -
        LaunchCurves.stretch.transform(
            _phase(time, LaunchTimings.breatheEnd, LaunchTimings.redrawEnd));
  }

  @override
  double ringOffset(int index) {
    final start = LaunchTimings.rest + LaunchTimings.ringStagger * index;
    final local = _phase(_time, start, start + LaunchTimings.ringNudge);
    return -LaunchMotion.ringNudge *
        math.sin(math.pi * LaunchCurves.ringNudge.transform(local));
  }

  double get _sweepPhase =>
      _phase(_time, LaunchTimings.sweepStart, LaunchTimings.sweepEnd);

  @override
  double? get sweepPosition {
    final phase = _sweepPhase;
    if (phase <= 0 || phase >= 1) return null;
    return LaunchCurves.sweep.transform(phase);
  }

  @override
  double get sweepOpacity =>
      LaunchMotion.sweepOpacity * math.sin(math.pi * _sweepPhase);

  @override
  double get checkEmphasis =>
      1 -
      (1 - LaunchMotion.holdOpacity) * LaunchCurves.hold.transform(_hold.value);

  @override
  double get reveal => _mode == LaunchAnimationMode.full
      ? LaunchCurves.reveal.transform(_reveal.value)
      : 0;

  @override
  double get logoOpacity => _mode == LaunchAnimationMode.full
      ? 1 - LaunchCurves.logoFade.transform(_reveal.value)
      : 1;

  @override
  double get logoScale => _mode == LaunchAnimationMode.full
      ? 1 -
          (1 - LaunchMotion.revealScale) *
              LaunchCurves.logoScale.transform(_reveal.value)
      : 1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (!_finished) _buildOverlay(),
      ],
    );
  }

  Widget _buildOverlay() {
    Widget overlay = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: constraints.biggest,
          painter: LaunchLogoPainter(
            frame: this,
            palette: _palette,
            logoExtent: launchLogoExtent(constraints.biggest),
            repaint: _frames,
          ),
        ),
      ),
    );
    if (_mode == LaunchAnimationMode.reduced) {
      overlay = FadeTransition(opacity: _reducedOpacity, child: overlay);
    }
    return IgnorePointer(
      // During the reveal the app underneath is already usable.
      ignoring: _revealing,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _skip(),
        child: Semantics(
          key: const ValueKey('app-launch-overlay'),
          label: 'Digitales Register',
          textDirection: TextDirection.ltr,
          image: true,
          child: overlay,
        ),
      ),
    );
  }
}
