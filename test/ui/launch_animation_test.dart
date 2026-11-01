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
import 'dart:io';

import 'package:dr/ui/launch/app_launch_animation.dart';
import 'package:dr/ui/launch/launch_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _overlay = find.byKey(const ValueKey('app-launch-overlay'));

/// Full intro plus reveal.
final _fullRun = LaunchTimings.intro + LaunchTimings.reveal;

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 16);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
    await tester.pump(step);
  }
}

class _App {
  final navigator = GlobalKey<NavigatorState>();
  final List<String> taps = [];

  Widget build() => MaterialApp(
        navigatorKey: navigator,
        routes: {
          '/': (_) => Scaffold(
                body: TextButton(
                  onPressed: () => taps.add('dashboard'),
                  child: const Text('Dashboard'),
                ),
              ),
          '/login': (_) => Scaffold(
                body: TextButton(
                  onPressed: () => taps.add('login'),
                  child: const Text('Login'),
                ),
              ),
        },
      );

  /// Mirrors the start-up routing: an auth check, then login or dashboard.
  Future<void> resolveTarget({
    required bool loggedIn,
    Duration authCheck = const Duration(milliseconds: 400),
  }) async {
    await Future<void>.delayed(authCheck);
    if (!loggedIn) unawaited(navigator.currentState!.pushNamed('/login'));
    await waitForRouteTransition(() => navigator.currentState);
  }
}

void main() {
  testWidgets('plays the choreography and removes itself', (tester) async {
    var finished = 0;
    final app = _App();
    await tester.pumpWidget(AppLaunchAnimation(
      mode: LaunchAnimationMode.full,
      targetReady: Future.value(),
      onFinished: () => finished++,
      child: app.build(),
    ));

    expect(_overlay, findsOneWidget);
    expect(appLaunchInProgress.value, isTrue);
    await _pumpFor(tester, LaunchTimings.intro);
    expect(_overlay, findsOneWidget, reason: 'the reveal is still running');
    expect(finished, 0);

    await _pumpFor(
        tester, LaunchTimings.reveal + const Duration(milliseconds: 50));
    expect(_overlay, findsNothing);
    expect(finished, 1);
    expect(appLaunchInProgress.value, isFalse);
    await tester.tap(find.text('Dashboard'));
    expect(app.taps, ['dashboard']);
  });

  testWidgets('the reveal uncovers the app from the check tip', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const appColor = Color(0xFF2F5DA8);
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: AppLaunchAnimation(
        mode: LaunchAnimationMode.full,
        targetReady: Future.value(),
        child: const ColoredBox(color: appColor),
      ),
    ));
    await _pumpFor(tester, LaunchTimings.intro + LaunchTimings.reveal * 0.6);

    final pixels = await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      return (await image.toByteData())!;
    });
    Color pixelAt(Offset point) {
      final offset = (point.dy.round() * 400 + point.dx.round()) * 4;
      return Color.fromARGB(
          pixels!.getUint8(offset + 3),
          pixels.getUint8(offset),
          pixels.getUint8(offset + 1),
          pixels.getUint8(offset + 2));
    }

    final tip = const Offset(200, 200) +
        (LaunchLogoGeometry.checkTip - const Offset(512, 512)) *
            (LaunchLayout.mobileExtent / LaunchLogoGeometry.canvas);
    expect(pixelAt(tip), appColor, reason: 'no logo inside the hole');
    expect(pixelAt(const Offset(1, 399)), LaunchPalette.light.background,
        reason: 'the far corner is not uncovered yet');
    await _pumpFor(tester, LaunchTimings.reveal);
  });

  testWidgets('holds in a breathing loop until the target is ready',
      (tester) async {
    final ready = Completer<void>();
    await tester.pumpWidget(AppLaunchAnimation(
      mode: LaunchAnimationMode.full,
      targetReady: ready.future,
      child: _App().build(),
    ));

    await _pumpFor(tester, _fullRun * 2);
    expect(_overlay, findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'the check keeps breathing');

    ready.complete();
    await _pumpFor(tester, LaunchTimings.holdPulse + LaunchTimings.reveal);
    expect(_overlay, findsNothing);
  });

  testWidgets('never reveals before the minimum duration', (tester) async {
    await tester.pumpWidget(AppLaunchAnimation(
      mode: LaunchAnimationMode.full,
      targetReady: Future.value(),
      child: _App().build(),
    ));
    await _pumpFor(tester, _fullRun - const Duration(milliseconds: 100));
    expect(_overlay, findsOneWidget);
  });

  for (final (name, skip) in [
    ('tap', (WidgetTester tester) => tester.tapAt(const Offset(20, 20))),
    (
      'key press',
      (WidgetTester tester) => tester.sendKeyEvent(LogicalKeyboardKey.space)
    ),
  ]) {
    testWidgets('a $name fast-forwards instead of cutting off', (tester) async {
      final app = _App();
      await tester.pumpWidget(AppLaunchAnimation(
        mode: LaunchAnimationMode.full,
        targetReady: Future.value(),
        child: app.build(),
      ));
      await _pumpFor(tester, const Duration(milliseconds: 200));
      await skip(tester);
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(_overlay, findsOneWidget, reason: 'the reveal still plays');

      await _pumpFor(
          tester, LaunchTimings.skipFastForward + LaunchTimings.skippedReveal);
      expect(_overlay, findsNothing);
      expect(app.taps, isEmpty, reason: 'the skip tap does not reach the app');
    });
  }

  testWidgets('reduced motion only fades', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(AppLaunchAnimation(
      targetReady: Future.value(),
      child: _App().build(),
    ));
    final fade =
        find.descendant(of: _overlay, matching: find.byType(FadeTransition));
    expect(fade, findsOneWidget);

    await tester.pump();
    await tester.pump(LaunchTimings.reducedFade ~/ 2);
    final opacity = tester.widget<FadeTransition>(fade).opacity.value;
    expect(opacity, inExclusiveRange(0, 1));

    await _pumpFor(tester, LaunchTimings.reducedFade);
    expect(_overlay, findsNothing);
  });

  testWidgets('can be switched off', (tester) async {
    var finished = false;
    await tester.pumpWidget(AppLaunchAnimation(
      mode: LaunchAnimationMode.off,
      targetReady: Completer<void>().future,
      onFinished: () => finished = true,
      child: _App().build(),
    ));
    await tester.pump();
    expect(_overlay, findsNothing);
    expect(finished, isTrue);
  });

  for (final loggedIn in [true, false]) {
    final target = loggedIn ? 'Dashboard' : 'Login';
    testWidgets('reveals the $target when ${loggedIn ? '' : 'not '}signed in',
        (tester) async {
      final app = _App();
      await tester.pumpWidget(AppLaunchAnimation(
        mode: LaunchAnimationMode.full,
        targetReady: app.resolveTarget(
          loggedIn: loggedIn,
          // Longer than the intro, so the reveal waits for the push.
          authCheck: const Duration(milliseconds: 1250),
        ),
        child: app.build(),
      ));

      await _pumpFor(tester, _fullRun * 2);
      expect(_overlay, findsNothing);
      expect(find.text(target), findsOneWidget);
      expect(find.text(loggedIn ? 'Login' : 'Dashboard'), findsNothing);
      await tester.tap(find.text(target));
      expect(app.taps, [target.toLowerCase()]);
    });
  }

  test('the redraw spring overshoots once and lands on the logo', () {
    const curve = LaunchCurves.redraw;
    final samples = [for (var i = 0; i <= 100; i++) curve.transform(i / 100)];
    final peak = samples.reduce((a, b) => a > b ? a : b);
    expect(samples.first, 0);
    expect(samples.last, 1);
    expect(peak, inExclusiveRange(1.01, 1.06));
  });

  test('the logo stays inside the Android 12 splash icon mask', () {
    // The 160dp logo sits in a 288dp icon that is masked to a 192dp circle.
    final radius = LaunchLogoGeometry.maxRadius /
        LaunchLogoGeometry.canvas *
        LaunchLayout.mobileExtent;
    expect(radius, lessThan(LaunchLayout.androidSplashMask / 2));
  });

  test('native launch screens use the launch animation colours', () {
    String hex(Color color) => color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final light = hex(LaunchPalette.light.background);
    final dark = hex(LaunchPalette.dark.background);
    String read(String path) => File(path).readAsStringSync().toUpperCase();

    expect(read('android/app/src/main/res/values/colors.xml'),
        contains('"SPLASH_COLOR">#$light<'));
    expect(read('android/app/src/main/res/values-night/colors.xml'),
        contains('"SPLASH_COLOR">#$dark<'));
    expect(read('android/app/src/main/res/values/launch_dimens.xml'),
        contains('>${LaunchLayout.mobileExtent.toInt()}DP<'));
    for (final runner in ['linux/my_application.cc']) {
      expect(read(runner), allOf(contains('#$light'), contains('#$dark')));
    }
    String rgb(String color) => 'RGB(0X${color.substring(0, 2)}, '
        '0X${color.substring(2, 4)}, 0X${color.substring(4)})';
    expect(read('windows/runner/win32_window.cpp'),
        allOf(contains(rgb(light)), contains(rgb(dark))));
  });
}
