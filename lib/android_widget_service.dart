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

  Future<void> refreshWidgets() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('refreshWidgets');
    } catch (_) {
      // Widgets are optional. Ignore host-side errors and keep the app usable.
    }
  }

  Future<AndroidWidgetLaunchDestination?> consumeLaunchDestination() async {
    if (!Platform.isAndroid) {
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
    if (!Platform.isAndroid) {
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
    this.debounce = const Duration(seconds: 2),
  }) : _bridge = bridge ?? AndroidWidgetPlatformBridge();

  final AndroidWidgetPlatformBridge _bridge;
  final Duration debounce;

  Timer? _pendingSave;
  AppState? _pendingState;
  String? _lastPayload;

  void scheduleSync(AppState state) {
    _pendingState = state;
    _pendingSave?.cancel();
    _pendingSave = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush({AppState? state}) async {
    final resolvedState = state ?? _pendingState;
    if (resolvedState == null) {
      return;
    }
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingState = null;

    final payload =
        json.encode(buildAndroidWidgetSnapshot(resolvedState).toJson());
    if (_lastPayload == payload) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(androidWidgetSnapshotStorageKey, payload);
    _lastPayload = payload;
    await _bridge.refreshWidgets();
  }

  Future<void> clear() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingState = null;
    _lastPayload = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(androidWidgetSnapshotStorageKey);
    await _bridge.refreshWidgets();
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
