import 'dart:async';
import 'dart:math' as math;

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:flutter/foundation.dart';

/// When to ask the server. Every value is a bound the server cannot exceed.
@immutable
class ServerNotificationPollPolicy {
  const ServerNotificationPollPolicy({
    this.defaultInterval = const Duration(seconds: 300),
    this.minInterval = const Duration(seconds: 60),
    this.maxInterval = const Duration(hours: 1),
    this.freshness = const Duration(seconds: 60),
    this.manualGap = const Duration(seconds: 15),
    this.backoffBase = const Duration(seconds: 30),
    this.backoffMax = const Duration(minutes: 30),
    this.retryAfterMax = const Duration(hours: 24),
    this.permanentFailureDelay = const Duration(hours: 1),
  });

  /// Used until the server has suggested an interval.
  final Duration defaultInterval;

  /// Bounds for `poll_after_seconds`.
  final Duration minInterval;
  final Duration maxInterval;

  /// Returning to the app within this time of the last request fetches nothing.
  final Duration freshness;

  /// Minimum distance of a refresh the user asked for.
  final Duration manualGap;
  final Duration backoffBase;
  final Duration backoffMax;

  /// An absurd `Retry-After` must not silence the client for good.
  final Duration retryAfterMax;

  /// Wait after a failure that an immediate retry would only repeat.
  final Duration permanentFailureDelay;

  Duration clampInterval(int seconds) {
    final value = Duration(seconds: seconds);
    return value < minInterval
        ? minInterval
        : value > maxInterval
            ? maxInterval
            : value;
  }

  /// Exponential backoff with equal jitter: between half and all of the step.
  Duration backoff(int failures, double random) {
    final exponent = math.min(failures - 1, 20);
    final step = math.min(
      backoffBase.inMilliseconds * math.pow(2, exponent),
      backoffMax.inMilliseconds,
    );
    return Duration(milliseconds: (step * (0.5 + random / 2)).round());
  }
}

/// Runs [fetch] while the app is in the foreground.
///
/// There is one timer and at most one fetch in flight. In the background
/// nothing is scheduled; [setActive] picks up again. No path, including a
/// manual refresh, can run before a backoff or `Retry-After` has passed.
class ServerNotificationPoller {
  ServerNotificationPoller({
    required this.fetch,
    this.policy = const ServerNotificationPollPolicy(),
    DateTime Function()? now,
    math.Random? random,
    this.onUnexpectedError,
  })  : _now = now ?? DateTime.now,
        _random = random ?? math.Random();

  /// Returns the suggested interval in seconds, or null to keep the current
  /// one. Failures are reported with [ServerNotificationFailure].
  final Future<int?> Function() fetch;
  final ServerNotificationPollPolicy policy;

  /// Told about errors that are not a [ServerNotificationFailure], which
  /// means a bug rather than the network. Expected failures never reach it.
  final void Function(Object error, StackTrace stack)? onUnexpectedError;
  final DateTime Function() _now;
  final math.Random _random;

  Timer? _timer;
  Future<void>? _inFlight;
  bool _running = false;
  bool _active = true;
  bool _rerun = false;
  int _failures = 0;
  DateTime? _lastAttempt;
  DateTime? _notBefore;
  late Duration _interval = policy.defaultInterval;

  @visibleForTesting
  bool get hasTimer => _timer?.isActive ?? false;

  @visibleForTesting
  int get failures => _failures;

  @visibleForTesting
  Duration get interval => _interval;

  /// Begins polling. Calling it again does nothing: one poller per process.
  void start() {
    if (_running) return;
    _running = true;
    if (_active) _fetchUnlessBlocked(Duration.zero);
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// The app moved to the foreground or the background.
  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (!_running) return;
    if (active) {
      _fetchUnlessBlocked(policy.freshness);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// The user asked for an update.
  void refresh() {
    if (_running && _active) _fetchUnlessBlocked(policy.manualGap);
  }

  /// What is asked for changed, so the current data no longer fits. Still
  /// waits for any backoff, and a fetch in flight is followed by a new one.
  void selectionChanged() {
    if (!_running) return;
    if (_inFlight != null) {
      _rerun = true;
    } else if (_active) {
      _fetchUnlessBlocked(Duration.zero);
    }
  }

  /// Fetches now, unless a backoff is running or the last request is more
  /// recent than [gap]. Then the regular timer stays in charge.
  void _fetchUnlessBlocked(Duration gap) {
    if (_inFlight != null) return;
    final now = _now();
    final notBefore = _notBefore;
    final last = _lastAttempt;
    final blocked = (notBefore != null && notBefore.isAfter(now)) ||
        (last != null && last.add(gap).isAfter(now));
    if (!blocked) {
      unawaited(_run());
    } else if (!hasTimer) {
      final due = notBefore ?? last!.add(_interval);
      final wait = due.difference(now);
      _schedule(wait.isNegative ? Duration.zero : wait);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (_running && _active) unawaited(_run());
    });
  }

  Future<void> _run() {
    return _inFlight ??= _attempt().whenComplete(() {
      _inFlight = null;
      if (_rerun) {
        _rerun = false;
        if (_running && _active) _fetchUnlessBlocked(Duration.zero);
      }
    });
  }

  Future<void> _attempt() async {
    _timer?.cancel();
    _timer = null;
    _lastAttempt = _now();
    Duration next;
    try {
      final suggested = await fetch();
      if (suggested != null) _interval = policy.clampInterval(suggested);
      _failures = 0;
      _notBefore = null;
      next = _interval;
    } on ServerNotificationFailure catch (failure) {
      next = _delayAfter(failure);
      _notBefore = _now().add(next);
    } catch (error, stack) {
      // Notifications never take the app down, whatever went wrong.
      onUnexpectedError?.call(error, stack);
      next = _delayAfter(const ServerNotificationFailure(
          ServerNotificationFailureKind.transient));
      _notBefore = _now().add(next);
    }
    if (_running && _active) _schedule(next);
  }

  Duration _delayAfter(ServerNotificationFailure failure) {
    _failures++;
    final backoff = policy.backoff(_failures, _random.nextDouble());
    var delay = failure.kind == ServerNotificationFailureKind.permanent
        ? policy.permanentFailureDelay
        : backoff;
    final retryAfter = failure.retryAfter;
    if (retryAfter != null) {
      final bounded =
          retryAfter > policy.retryAfterMax ? policy.retryAfterMax : retryAfter;
      // Up to 10 % more, so that limited clients do not all return at once.
      final spread = Duration(
          milliseconds:
              (bounded.inMilliseconds * 0.1 * _random.nextDouble()).round());
      if (bounded + spread > delay) delay = bounded + spread;
    }
    return delay;
  }
}
