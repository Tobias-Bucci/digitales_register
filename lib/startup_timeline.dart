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
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// One recorded step or point of the cold start.
@immutable
class StartupMark {
  const StartupMark(this.name, this.startMicros, this.endMicros);

  /// A fixed label from [StartupTimeline]; never user data.
  final String name;

  /// Microseconds since `main()` started the clock.
  final int startMicros;
  final int endMicros;

  int get durationMicros => endMicros - startMicros;
}

/// Records how long each phase of the cold start takes (see
/// `docs/performance/startup-loading.md`).
///
/// Debug and profile builds keep the marks, emit them as timeline events for
/// DevTools and print one line per mark. Release builds compile every call
/// down to running the step itself. Labels are fixed names; callers must never
/// pass account names, URLs, grades or other school data.
class StartupTimeline {
  StartupTimeline({bool? enabled, this.output})
      : _enabled = enabled ?? !kReleaseMode;

  final bool _enabled;

  /// Receives one line per mark; null prints with [debugPrint].
  final void Function(String line)? output;

  final Stopwatch _clock = Stopwatch();
  final List<StartupMark> _marks = [];
  final Set<String> _seen = {};

  /// Only the cold start is of interest; later sign-ins are not recorded.
  static const Duration window = Duration(minutes: 2);

  bool get _active =>
      !kReleaseMode && _enabled && _clock.isRunning && _clock.elapsed < window;

  List<StartupMark> get marks => List.unmodifiable(_marks);

  /// Starts the clock; called first thing in `main()`.
  void start() {
    if (kReleaseMode || !_enabled || _clock.isRunning) return;
    _clock.start();
  }

  /// Runs [body] as the step [name] and records its duration once.
  ///
  /// When nothing is recorded this returns the future of [body] itself, so the
  /// step adds no asynchronous gap.
  Future<T> step<T>(String name, Future<T> Function() body) {
    if (kReleaseMode || !_active || _seen.contains(name)) return body();
    return _timed(name, body);
  }

  Future<T> _timed<T>(String name, Future<T> Function() body) async {
    final task = developer.TimelineTask()..start('startup:$name');
    final begin = _clock.elapsedMicroseconds;
    try {
      return await body();
    } finally {
      task.finish();
      _record(name, begin, _clock.elapsedMicroseconds);
    }
  }

  /// Records that the start reached the point [name], once.
  void mark(String name) {
    if (kReleaseMode || !_active || _seen.contains(name)) return;
    final now = _clock.elapsedMicroseconds;
    developer.Timeline.instantSync('startup:$name');
    _record(name, now, now);
  }

  final List<FrameTiming> _frames = [];
  TimingsCallback? _timings;

  /// Collects frame timings of the launch animation until [stopFrames].
  void watchFrames() {
    if (kReleaseMode || !_active || _timings != null) return;
    final callback = _timings = _frames.addAll;
    SchedulerBinding.instance.addTimingsCallback(callback);
  }

  /// Prints how many collected frames missed a 60 Hz budget, [after] the
  /// call, so the engine can deliver the frames of the last batch.
  void stopFrames({Duration after = const Duration(seconds: 1)}) {
    final callback = _timings;
    if (kReleaseMode || callback == null) return;
    Timer(after, () {
      SchedulerBinding.instance.removeTimingsCallback(callback);
      const budget = 16667;
      int worst(int Function(FrameTiming) of) =>
          _frames.fold(0, (max, frame) => of(frame) > max ? of(frame) : max);
      int build(FrameTiming f) => f.buildDuration.inMicroseconds;
      int raster(FrameTiming f) => f.rasterDuration.inMicroseconds;
      (output ?? debugPrint)('[startup] launch_frames frames=${_frames.length}'
          ' slow_build=${_frames.where((f) => build(f) > budget).length}'
          ' slow_raster=${_frames.where((f) => raster(f) > budget).length}'
          ' worst_build=${_ms(worst(build))}ms'
          ' worst_raster=${_ms(worst(raster))}ms');
    });
  }

  void _record(String name, int begin, int end) {
    if (!_seen.add(name)) return;
    final mark = StartupMark(name, begin, end);
    _marks.add(mark);
    final line = '[startup] $name at=${_ms(end)}ms'
        '${begin == end ? '' : ' took=${_ms(end - begin)}ms'}';
    (output ?? debugPrint)(line);
  }

  static String _ms(int micros) => (micros / 1000).toStringAsFixed(1);
}

/// The timeline of this process's cold start.
final StartupTimeline startupTimeline = StartupTimeline();
