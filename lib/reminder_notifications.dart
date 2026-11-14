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

import 'package:dr/host_platform.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:dr/runtime_trace.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mutex/mutex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const reminderStoragePreferenceKey = 'reminderNotificationsV1';

/// Used when the device does not report a usable zone. The app's schools are
/// all in South Tyrol.
const _fallbackTimeZone = 'Europe/Rome';

/// What a platform's notification system can do for a planned reminder.
enum ReminderBackend {
  /// The system shows reminders even if the app is closed and repeats them
  /// daily or weekly by itself (Android, iOS, macOS).
  systemRepeating,

  /// The system shows reminders even if the app is closed, but cannot repeat
  /// them (Windows). Repeating reminders are planned some days ahead.
  systemOneTime,

  /// The system has no scheduling at all (Linux), so the reminders are only
  /// shown while the app is running.
  whileRunning,
}

ReminderBackend reminderBackendForPlatform() {
  if (HostPlatform.isLinux) return ReminderBackend.whileRunning;
  if (HostPlatform.isWindows) return ReminderBackend.systemOneTime;
  return ReminderBackend.systemRepeating;
}

final reminderNotifications = ReminderNotificationService();

/// Keeps the system's scheduled notifications equal to the planned reminders.
///
/// Only ids, hashes and times are stored, no school data.
class ReminderNotificationService {
  ReminderNotificationService({
    FlutterLocalNotificationsPlugin? native,
    ReminderBackend? backend,
    DateTime Function()? clock,
    Future<String?> Function()? deviceTimeZone,
    Future<void> Function()? initializer,
    Future<bool> Function()? permission,
    Future<bool> Function()? permissionRequest,
  })  : _native = native ?? FlutterLocalNotificationsPlugin(),
        _backendOverride = backend,
        _clock = clock ?? DateTime.now,
        _deviceTimeZone = deviceTimeZone ?? _platformTimeZone,
        _initializer = initializer,
        _permission = permission ?? schoolNotifications.systemPermissionGranted,
        _permissionRequest =
            permissionRequest ?? schoolNotifications.ensureSystemPermission;

  final FlutterLocalNotificationsPlugin _native;
  final ReminderBackend? _backendOverride;
  final DateTime Function() _clock;
  final Future<String?> Function() _deviceTimeZone;
  final Future<void> Function()? _initializer;
  final Future<bool> Function() _permission;
  final Future<bool> Function() _permissionRequest;
  final _mutex = Mutex();
  Future<void>? _initialized;
  Timer? _timer;
  List<PlannedReminder> _whileRunning = const [];

  /// Called with the payload of a tapped reminder.
  Future<void> Function(String? payload)? onTap;

  ReminderBackend get backend => _backendOverride ?? reminderBackendForPlatform();

  /// Whether reminders are shown only while the app is open.
  bool get onlyWhileRunning => backend == ReminderBackend.whileRunning;

  /// Whether the user can be sent to a system page to allow notifications.
  bool get canOpenSystemSettings => HostPlatform.isAndroid || HostPlatform.isIOS;

  Future<void> openSystemSettings() => schoolNotifications.openSystemSettings();

  Future<bool> hasPermission() => _permission();

  /// Asks the system for permission if that is still possible. A denial is a
  /// normal outcome here, not an error.
  Future<bool> requestPermission() => _permissionRequest();

  static Future<String?> _platformTimeZone() =>
      const MethodChannel('dr/school_notifications')
          .invokeMethod<String>('timeZone');

  Future<void> _initialize() =>
      _initialized ??= _initializePlugin().catchError((Object error) {
        // Optional functionality: the next sync may try again.
        _initialized = null;
        throw error;
      });

  Future<void> _initializePlugin() async {
    if (_initializer != null) return _initializer();
    // The school notification service owns the plugin where it is active; a
    // second initialization would replace its tap handler.
    if (schoolNotifications.supported) return schoolNotifications.initialize();
    await _native.initialize(
      settings: schoolNotificationInitializationSettings,
      onDidReceiveNotificationResponse: (response) =>
          unawaited(_handleTap(response.payload)),
    );
  }

  Future<void> _handleTap(String? payload) async {
    try {
      await onTap?.call(payload);
    } catch (error) {
      runtimeTrace('Reminders', 'tap-failed',
          detail: 'type=${error.runtimeType}');
    }
  }

  /// Connects the taps of reminders before the app starts handling them.
  void prepare() {
    schoolNotifications.onReminderTap = _handleTap;
  }

  /// Replaces all scheduled reminders with [reminders]. Reminders that did not
  /// change are left alone, so that a repeating reminder is not disturbed by
  /// every reload of the dashboard.
  Future<void> sync(List<PlannedReminder> reminders) =>
      _mutex.protect(() async {
        // Nothing to do for everyone who does not use reminders: the plugin
        // stays untouched on the platforms that have no other use for it.
        if (reminders.isEmpty &&
            _whileRunning.isEmpty &&
            _readStored(await SharedPreferences.getInstance()).isEmpty) {
          return;
        }
        await _initialize();
        final now = _clock();
        final expanded = _expand(reminders, now);
        if (backend == ReminderBackend.whileRunning) {
          _whileRunning = expanded;
          _armTimer();
          return;
        }
        await _syncSystem(expanded, now);
      });

  /// The reminders the system should know about, soonest first. The system
  /// limit of [maxPendingReminders] drops the reminders that are furthest
  /// away, which later syncs pick up again.
  List<PlannedReminder> _expand(List<PlannedReminder> reminders, DateTime now) {
    final repeating = backend == ReminderBackend.systemRepeating;
    final expanded = reminders
        .expand((reminder) => reminder.repeats && !repeating
            ? reminder.occurrences(now, dailyReminderOccurrences)
            : [reminder])
        .where((reminder) => reminder.repeats || reminder.at.isAfter(now))
        .toList();
    expanded.sort((a, b) => a.nextAt(now).compareTo(b.nextAt(now)));
    return expanded.take(maxPendingReminders).toList();
  }

  Future<void> _syncSystem(List<PlannedReminder> wanted, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = _readStored(prefs);
    final location =
        wanted.any((reminder) => reminder.repeats) ? await _location() : null;
    final next = <int, _StoredReminder>{
      for (final reminder in wanted)
        reminder.id: _StoredReminder(
          reminder.fingerprint(location?.name),
          reminder.repeats ? null : reminder.at,
        ),
    };
    final pending = {
      for (final request in await _native.pendingNotificationRequests())
        request.id,
    };

    for (final MapEntry(key: id, value: old) in stored.entries) {
      final replacement = next[id];
      if (replacement?.fingerprint == old.fingerprint) continue;
      // Cancelling also removes a shown notification. One whose time has
      // passed is already on screen and has to stay there until it is read.
      if (replacement == null && old.at != null && !old.at!.isAfter(now)) {
        continue;
      }
      await _native.cancel(id: id);
    }
    // Remember everything first: after a crash, the next sync still knows
    // about the reminders that were already handed to the system.
    await _writeStored(prefs, {...stored, ...next});
    for (final reminder in wanted) {
      final unchanged =
          stored[reminder.id]?.fingerprint == next[reminder.id]!.fingerprint;
      if (unchanged && pending.contains(reminder.id)) continue;
      await _schedule(reminder, now, location);
    }
    await _writeStored(prefs, next);
  }

  Future<void> _schedule(
    PlannedReminder reminder,
    DateTime now,
    tz.Location? location,
  ) {
    // A one-time reminder is one moment in time, so UTC is exact and needs no
    // knowledge of the device's zone. Only a repeating one follows the clock.
    final date = reminder.repeats
        ? tz.TZDateTime.from(reminder.nextAt(now), location!)
        : tz.TZDateTime.from(reminder.at, tz.UTC);
    return _native.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: date,
      notificationDetails: _details(reminder),
      // Inexact alarms need no exact-alarm permission. A reminder may be a few
      // minutes late, which does not matter here.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: !reminder.repeats
          ? null
          : reminder.weekday == null
              ? DateTimeComponents.time
              : DateTimeComponents.dayOfWeekAndTime,
      payload: reminder.payload,
    );
  }

  NotificationDetails _details(PlannedReminder reminder) => NotificationDetails(
        android: AndroidNotificationDetails(
          reminder.channel.id,
          reminder.channelName,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );

  Future<tz.Location> _location() async {
    tz_data.initializeTimeZones();
    try {
      final name = await _deviceTimeZone();
      if (name != null) return tz.getLocation(name);
    } catch (error) {
      runtimeTrace('Reminders', 'time-zone-unavailable',
          detail: 'type=${error.runtimeType}');
    }
    return tz.getLocation(_fallbackTimeZone);
  }

  void _armTimer() {
    _timer?.cancel();
    if (_whileRunning.isEmpty) return;
    final now = _clock();
    final next = _whileRunning
        .map((reminder) => reminder.at)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _timer = Timer(next.difference(now), () => unawaited(_showDue()));
  }

  Future<void> _showDue() => _mutex.protect(() async {
        final now = _clock();
        final due = _whileRunning.where((r) => !r.at.isAfter(now)).toList();
        _whileRunning =
            _whileRunning.where((r) => r.at.isAfter(now)).toList();
        _armTimer();
        for (final reminder in due) {
          try {
            await _native.show(
              id: reminder.id,
              title: reminder.title,
              body: reminder.body,
              notificationDetails: _details(reminder),
              payload: reminder.payload,
            );
          } catch (error) {
            runtimeTrace('Reminders', 'show-failed',
                detail: 'type=${error.runtimeType}');
          }
        }
      });

  Map<int, _StoredReminder> _readStored(SharedPreferences prefs) {
    final raw = prefs.getString(reminderStoragePreferenceKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (id, value) => MapEntry(
          int.parse(id),
          _StoredReminder.fromJson(value as Map<String, dynamic>),
        ),
      );
    } on Object catch (error) {
      // Unreadable bookkeeping only costs a reschedule of the wanted reminders.
      runtimeTrace('Reminders', 'storage-unreadable',
          detail: 'type=${error.runtimeType}');
      return {};
    }
  }

  Future<void> _writeStored(
    SharedPreferences prefs,
    Map<int, _StoredReminder> reminders,
  ) =>
      prefs.setString(
        reminderStoragePreferenceKey,
        jsonEncode({
          for (final MapEntry(key: id, value: reminder) in reminders.entries)
            '$id': reminder.toJson(),
        }),
      );

  @visibleForTesting
  void dispose() => _timer?.cancel();
}

class _StoredReminder {
  const _StoredReminder(this.fingerprint, this.at);

  factory _StoredReminder.fromJson(Map<String, dynamic> json) =>
      _StoredReminder(
        json['f'] as String,
        json['at'] == null ? null : DateTime.parse(json['at'] as String),
      );

  final String fingerprint;

  /// Null for a repeating reminder, which never is in the past.
  final DateTime? at;

  Map<String, Object?> toJson() =>
      {'f': fingerprint, 'at': at?.toUtc().toIso8601String()};
}
