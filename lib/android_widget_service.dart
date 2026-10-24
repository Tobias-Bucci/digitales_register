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
import 'dart:convert';
import 'dart:io';

import 'package:dr/actions/app_actions.dart';
import 'package:dr/android_widget_snapshot.dart';
import 'package:dr/app_state.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String androidWidgetSnapshotStorageKey = 'androidWidgetSnapshotV1';

enum AndroidWidgetLaunchDestination {
  homework,
  grades,
  calendar,
}

AndroidWidgetLaunchDestination? parseAndroidWidgetLaunchDestination(
  String? value,
) {
  for (final destination in AndroidWidgetLaunchDestination.values) {
    if (destination.name == value) {
      return destination;
    }
  }
  return null;
}

class AndroidWidgetPlatformBridge {
  AndroidWidgetPlatformBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'dr/android_widgets';

  final MethodChannel _channel;

  // The historical Android service also feeds the WidgetKit app group.
  Future<void> writePlanningSnapshot(String? payload) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('writePlanningSnapshot', payload);
    } catch (_) {
      // Keep the app usable if the optional widget extension is unavailable.
    }
  }

  Future<void> refreshWidgets() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('refreshWidgets');
    } catch (_) {
      // Widgets are optional. Ignore host-side errors and keep the app usable.
    }
  }

  Future<AndroidWidgetLaunchDestination?> consumeLaunchDestination() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<String>(
        'consumeLaunchDestination',
      );
      return parseAndroidWidgetLaunchDestination(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> registerLaunchHandler(
    Future<void> Function(AndroidWidgetLaunchDestination destination) handler,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onLaunchDestination') {
        return;
      }
      final arguments = call.arguments;
      String? destinationValue;
      if (arguments is Map) {
        destinationValue = arguments['destination']?.toString();
      } else {
        destinationValue = arguments?.toString();
      }
      final destination = parseAndroidWidgetLaunchDestination(destinationValue);
      if (destination != null) {
        await handler(destination);
      }
    });
  }
}

class AndroidWidgetSnapshotService {
  AndroidWidgetSnapshotService({
    AndroidWidgetPlatformBridge? bridge,
    Future<SharedPreferences> Function()? preferences,
    this.debounce = const Duration(seconds: 2),
  })  : _bridge = bridge ?? AndroidWidgetPlatformBridge(),
        _preferences = preferences ?? SharedPreferences.getInstance;

  final AndroidWidgetPlatformBridge _bridge;
  final Duration debounce;
  final Future<SharedPreferences> Function() _preferences;
  Future<void> _tail = Future.value();

  // Each operation includes its native refresh. A clear is a barrier after all
  // older writes and before all newer writes, even if an older write failed.
  Future<void> _enqueue(Future<void> Function() work) {
    final operation = _tail.then((_) => work());
    _tail = operation.catchError((Object error, StackTrace stack) {
      _trace('operation-failed', 'queue', 'type=${error.runtimeType}');
      diagnostics.report(error, stack, DiagnosticError.storage);
    });
    return operation;
  }

  Timer? _pendingSave;
  AppState? _pendingState;
  String? _lastContent;
  String? _pendingReason;
  final Stopwatch _traceClock = Stopwatch()..start();
  int _traceSequence = 0;

  void _trace(String event, String reason, [String details = '']) {
    if (!kDebugMode) return;
    debugPrint('[WidgetSync] ${DateTime.now().toUtc().toIso8601String()} '
        '+${_traceClock.elapsedMilliseconds}ms #${++_traceSequence} '
        '$event reason=$reason $details');
  }

  void scheduleSync(AppState state, {String reason = 'state-change'}) {
    if (!state.loginState.loggedIn ||
        state.settingsState.noDataSaving ||
        state.settingsState.biometricAppLockEnabled) {
      unawaited(flush(state: state, reason: reason)
          .catchError((Object error, StackTrace stack) {
        diagnostics.report(error, stack, DiagnosticError.storage);
      }));
      return;
    }
    _pendingState = state;
    _pendingReason = reason;
    _trace('scheduled', reason, 'debounceMs=${debounce.inMilliseconds}');
    _pendingSave?.cancel();
    _pendingSave = Timer(debounce, () {
      unawaited(flush().catchError((Object error, StackTrace stack) {
        diagnostics.report(error, stack, DiagnosticError.storage);
      }));
    });
  }

  Future<void> flush({AppState? state, String? reason}) async {
    final resolvedState = state ?? _pendingState;
    final resolvedReason = reason ?? _pendingReason ?? 'explicit-flush';
    if (resolvedState == null) {
      return;
    }
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingState = null;
    _pendingReason = null;

    final snapshot = buildAndroidWidgetSnapshot(resolvedState);
    final snapshotJson = snapshot.toJson();
    final payload = json.encode(snapshotJson);
    // Generation time is metadata, not a change to widget content. Keep the
    // date, privacy status and every displayed field in the comparison.
    final contentJson = Map<String, Object?>.from(snapshotJson)
      ..['meta'] = (Map<String, Object?>.from(snapshot.meta.toJson())
        ..remove('generatedAt'));
    final content = json.encode(contentJson);
    _trace('queued', resolvedReason, 'status=${snapshot.meta.status.name}');
    await _enqueue(() async {
      if (_lastContent == content) {
        _trace('skipped', resolvedReason, 'unchanged');
        return;
      }
      final timer = Stopwatch()..start();
      _trace('refresh-start', resolvedReason,
          'status=${snapshot.meta.status.name}');
      final prefs = await _preferences();
      if (!await prefs.setString(androidWidgetSnapshotStorageKey, payload)) {
        throw StateError('Widget snapshot could not be saved');
      }
      await _bridge.writePlanningSnapshot(payload);
      await _bridge.refreshWidgets();
      _lastContent = content;
      _trace('refresh-end', resolvedReason,
          'durationMs=${timer.elapsedMilliseconds}');
    });
  }

  Future<void> clear({String reason = 'clear'}) async {
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingState = null;
    _pendingReason = null;
    _trace('clear-queued', reason);
    await _enqueue(() async {
      final timer = Stopwatch()..start();
      _trace('clear-start', reason);
      _lastContent = null;
      try {
        final prefs = await _preferences();
        if (!await prefs.remove(androidWidgetSnapshotStorageKey)) {
          throw StateError('Widget snapshot could not be cleared');
        }
      } finally {
        // The independent iOS app-group file must also be cleared if deleting
        // the app's own preferences fails during logout/account switching.
        await _bridge.writePlanningSnapshot(null);
        await _bridge.refreshWidgets();
        _trace('clear-end', reason, 'durationMs=${timer.elapsedMilliseconds}');
      }
    });
  }
}

Future<void> handleAndroidWidgetLaunchDestination(
  AppActions actions,
  AndroidWidgetLaunchDestination destination, {
  bool deferUntilLogin = false,
}) async {
  if (deferUntilLogin) {
    switch (destination) {
      case AndroidWidgetLaunchDestination.homework:
        await actions.loginActions
            .addAfterLoginCallback(_showHomeworkFromWidget);
        return;
      case AndroidWidgetLaunchDestination.grades:
        await actions.loginActions
            .addAfterLoginCallback(actions.routingActions.showGrades.call);
        return;
      case AndroidWidgetLaunchDestination.calendar:
        await actions.loginActions
            .addAfterLoginCallback(actions.routingActions.showCalendar.call);
        return;
    }
  }

  switch (destination) {
    case AndroidWidgetLaunchDestination.homework:
      _showHomeworkFromWidget();
      return;
    case AndroidWidgetLaunchDestination.grades:
      await actions.routingActions.showGrades();
      return;
    case AndroidWidgetLaunchDestination.calendar:
      await actions.routingActions.showCalendar();
      return;
  }
}

void _showHomeworkFromWidget() {
  navigatorKey?.currentState?.popUntil((route) => route.isFirst);
  nestedNavKey.currentState?.popUntil((route) => route.isFirst);
  scaffoldKey?.currentState?.goHome();
}
