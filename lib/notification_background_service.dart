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
import 'dart:developer';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/desktop.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _backgroundTaskUniqueName = "dr_notification_polling_unique";
const _backgroundTaskName = "dr_notification_polling_task";
const _pushEnabledKey = "pushNotificationsEnabled";
const _reminderEntriesKey = "backgroundNotificationReminderEntries";
const _backgroundLogsKey = "backgroundNotificationLogs";
const _pollLeaseKey = "backgroundNotificationPollLease";
const _pollLastCompletedKey = "backgroundNotificationPollLastCompleted";
const _backgroundLogLimit = 200;

const _channelId = "dr_background_notifications";
const _channelName = "Digitales Register Benachrichtigungen";
const _channelDescription =
    "Lokale Benachrichtigungen fuer ungelesene Mitteilungen";
const _summaryNotificationId = 0x4444524e;
const _foregroundPollingInterval = Duration(minutes: 10);
const _backgroundPollingInterval = Duration(minutes: 15);
const _pollLeaseDuration = Duration(minutes: 2);
const _pollDebounceWindow = Duration(minutes: 1);
const _androidNotificationMethodChannel =
    MethodChannel("dr/notification_background_service");

typedef NotificationFetchOverride = Future<List<Map<String, dynamic>>>
    Function();
typedef NotificationPermissionOverride = Future<bool> Function();
typedef NotificationShowOverride = Future<void> Function(
  NotificationDisplayRequest request,
);
typedef NotificationCancelOverride = Future<void> Function(int id);
typedef BackgroundTaskSyncOverride = Future<void> Function(
    {required bool enabled});
typedef LocalNotificationsInitOverride = Future<void> Function();

@pragma("vm:entry-point")
void notificationBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationBackgroundService.ensureLocalNotificationsInitialized();
    final enabled = await NotificationBackgroundService.isEnabled();

    await NotificationBackgroundService.appendLog(
      "Task ausgefuehrt: $task, pushEnabled=$enabled",
    );

    if (!enabled) {
      return true;
    }

    try {
      await NotificationBackgroundService.pollAndNotify(
        trigger: "workmanager:$task",
      );
    } catch (e, trace) {
      await NotificationBackgroundService.appendLog(
        "Task-Fehler: $e",
      );
      log(
        "Background notification task failed",
        error: e,
        stackTrace: trace,
      );
    }

    return true;
  });
}

class NotificationDisplayRequest {
  const NotificationDisplayRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    this.lines = const <String>[],
  });

  final int id;
  final String title;
  final String? body;
  final String payload;
  final List<String> lines;
}

class NotificationReminderCandidate {
  const NotificationReminderCandidate({
    required this.key,
    required this.title,
    required this.body,
  });

  final String key;
  final String title;
  final String? body;
}

class NotificationReminderEntry {
  const NotificationReminderEntry({
    required this.key,
    required this.title,
    required this.body,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.lastAlertedAt,
  });

  factory NotificationReminderEntry.fromJson(Map<String, dynamic> json) {
    return NotificationReminderEntry(
      key: getString(json["key"]) ?? "",
      title: getString(json["title"]) ?? "",
      body: getString(json["body"]),
      firstSeenAt:
          UtcDateTime.tryParse(getString(json["firstSeenAt"]) ?? "") ?? now,
      lastSeenAt:
          UtcDateTime.tryParse(getString(json["lastSeenAt"]) ?? "") ?? now,
      lastAlertedAt:
          UtcDateTime.tryParse(getString(json["lastAlertedAt"]) ?? ""),
    );
  }

  final String key;
  final String title;
  final String? body;
  final UtcDateTime firstSeenAt;
  final UtcDateTime lastSeenAt;
  final UtcDateTime? lastAlertedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "key": key,
      "title": title,
      "body": body,
      "firstSeenAt": firstSeenAt.toIso8601String(),
      "lastSeenAt": lastSeenAt.toIso8601String(),
      "lastAlertedAt": lastAlertedAt?.toIso8601String(),
    };
  }

  NotificationReminderEntry copyWith({
    String? key,
    String? title,
    String? body,
    UtcDateTime? firstSeenAt,
    UtcDateTime? lastSeenAt,
    UtcDateTime? lastAlertedAt,
    bool clearLastAlertedAt = false,
  }) {
    return NotificationReminderEntry(
      key: key ?? this.key,
      title: title ?? this.title,
      body: body ?? this.body,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastAlertedAt:
          clearLastAlertedAt ? null : (lastAlertedAt ?? this.lastAlertedAt),
    );
  }
}

class NotificationReminderEvaluation {
  const NotificationReminderEvaluation({
    required this.trackedEntries,
    required this.dueEntries,
  });

  final List<NotificationReminderEntry> trackedEntries;
  final List<NotificationReminderEntry> dueEntries;
}

@visibleForTesting
NotificationReminderEvaluation evaluateNotificationReminders({
  required Iterable<NotificationReminderEntry> previousEntries,
  required Iterable<NotificationReminderCandidate> unreadCandidates,
  required UtcDateTime currentTime,
  Duration reminderInterval = _foregroundPollingInterval,
}) {
  final previousByKey = <String, NotificationReminderEntry>{
    for (final entry in previousEntries) entry.key: entry,
  };
  final trackedEntries = <NotificationReminderEntry>[];
  final dueEntries = <NotificationReminderEntry>[];

  for (final candidate in unreadCandidates) {
    final existing = previousByKey[candidate.key];
    final updated = (existing ??
            NotificationReminderEntry(
              key: candidate.key,
              title: candidate.title,
              body: candidate.body,
              firstSeenAt: currentTime,
              lastSeenAt: currentTime,
            ))
        .copyWith(
      title: candidate.title,
      body: candidate.body,
      lastSeenAt: currentTime,
    );

    trackedEntries.add(updated);

    final lastAlertedAt = updated.lastAlertedAt;
    final due = lastAlertedAt == null ||
        !currentTime.isBefore(lastAlertedAt.add(reminderInterval));
    if (due) {
      dueEntries.add(updated);
    }
  }

  trackedEntries.sort((a, b) => a.key.compareTo(b.key));
  dueEntries.sort((a, b) => a.key.compareTo(b.key));

  return NotificationReminderEvaluation(
    trackedEntries: trackedEntries,
    dueEntries: dueEntries,
  );
}

class _PollLeaseResult {
  const _PollLeaseResult({
    required this.acquired,
    required this.token,
    required this.reason,
  });

  final bool acquired;
  final String token;
  final String? reason;
}

// ignore: avoid_classes_with_only_static_members
class NotificationBackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;
  static bool _workmanagerInitialized = false;
  static bool _appInForeground = true;
  static Timer? _foregroundPollTimer;

  @visibleForTesting
  static NotificationFetchOverride? fetchUnreadNotificationsOverride;
  @visibleForTesting
  static NotificationPermissionOverride? requestNotificationPermissionOverride;
  @visibleForTesting
  static NotificationShowOverride? showNotificationOverride;
  @visibleForTesting
  static NotificationCancelOverride? cancelNotificationOverride;
  @visibleForTesting
  static BackgroundTaskSyncOverride? syncBackgroundTaskOverride;
  @visibleForTesting
  static LocalNotificationsInitOverride? initializeLocalNotificationsOverride;
  @visibleForTesting
  static bool Function()? isAndroidOverride;

  static bool get _isAndroid => isAndroidOverride?.call() ?? Platform.isAndroid;

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await ensureLocalNotificationsInitialized();

    if (!_workmanagerInitialized) {
      await Workmanager().initialize(
        notificationBackgroundDispatcher,
      );
      _workmanagerInitialized = true;
    }

    final enabled = await isEnabled();
    await _syncBackgroundTask(enabled: enabled);
    await _syncForegroundPolling(enabled: enabled, triggerImmediate: false);
    await appendLog(
      "Service initialisiert, pushEnabled=$enabled",
    );
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pushEnabledKey) ?? false;
  }

  static Future<bool> setEnabled({
    required bool enabled,
    bool triggerImmediatePoll = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await ensureLocalNotificationsInitialized();

    if (enabled) {
      final permissionGranted = await _requestNotificationPermission();
      if (!permissionGranted) {
        await prefs.setBool(_pushEnabledKey, false);
        await _syncBackgroundTask(enabled: false);
        await _syncForegroundPolling(enabled: false, triggerImmediate: false);
        await appendLog(
            "Push Notifications deaktiviert: Berechtigung verweigert");
        return false;
      }
    }

    await prefs.setBool(_pushEnabledKey, enabled);
    await _syncBackgroundTask(enabled: enabled);
    await _syncForegroundPolling(
      enabled: enabled,
      triggerImmediate: false,
    );
    await appendLog("Push Notifications gesetzt auf: $enabled");

    if (enabled && triggerImmediatePoll) {
      unawaited(
        pollAndNotify(trigger: "manual_enable"),
      );
    } else if (!enabled) {
      await _cancelSummaryNotification();
    }

    return enabled;
  }

  static Future<void> handleAppResumed() async {
    _appInForeground = true;
    final enabled = await isEnabled();
    await _syncForegroundPolling(
      enabled: enabled,
      // The foreground app refreshes its own data on resume.
      // Avoid starting a competing authenticated poll at the same time.
      triggerImmediate: false,
    );
  }

  static Future<void> handleAppPaused() async {
    _appInForeground = false;
    _stopForegroundPolling();
  }

  static Future<void> ensureLocalNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    if (initializeLocalNotificationsOverride != null) {
      await initializeLocalNotificationsOverride!();
      _notificationsInitialized = true;
      return;
    }

    const androidSettings =
        AndroidInitializationSettings("@mipmap/launcher_icon");
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _notificationsInitialized = true;
  }

  static Future<void> pollAndNotify({required String trigger}) async {
    final lease = await _tryAcquirePollLease(trigger: trigger);
    if (!lease.acquired) {
      await appendLog("[$trigger] Polling uebersprungen: ${lease.reason}");
      return;
    }

    try {
      final unread = await (fetchUnreadNotificationsOverride != null
          ? fetchUnreadNotificationsOverride!()
          : _fetchUnreadNotifications());
      final prefs = await SharedPreferences.getInstance();
      final previousEntries = _readReminderEntries(prefs);
      final currentTime = now;
      final evaluation = evaluateNotificationReminders(
        previousEntries: previousEntries,
        unreadCandidates: unread.map(_toNotificationCandidate),
        currentTime: currentTime,
      );

      if (evaluation.dueEntries.isEmpty) {
        await _writeReminderEntries(
          prefs,
          evaluation.trackedEntries,
        );
        await _cancelSummaryNotification();
        await appendLog(
          "[$trigger] Keine faelligen ungelesenen Notifications (${evaluation.trackedEntries.length} verfolgt)",
        );
        return;
      }

      if (evaluation.dueEntries.length == 1) {
        await _cancelSummaryNotification();
        await _showReminderNotification(evaluation.dueEntries.single);
      } else {
        await _showSummaryNotification(evaluation.dueEntries);
      }

      final alertedKeys =
          evaluation.dueEntries.map((entry) => entry.key).toSet();
      final updatedEntries = evaluation.trackedEntries
          .map(
            (entry) => alertedKeys.contains(entry.key)
                ? entry.copyWith(lastAlertedAt: currentTime)
                : entry,
          )
          .toList(growable: false);
      await _writeReminderEntries(prefs, updatedEntries);
      await appendLog(
        "[$trigger] ${evaluation.dueEntries.length} Notification-Erinnerungen gesendet: ${evaluation.dueEntries.map((entry) => entry.key).join(",")}",
      );
    } finally {
      await _releasePollLease(token: lease.token);
    }
  }

  static Future<void> _syncForegroundPolling({
    required bool enabled,
    required bool triggerImmediate,
  }) async {
    if (!enabled || !_appInForeground) {
      _stopForegroundPolling();
      return;
    }

    if (_foregroundPollTimer == null) {
      _foregroundPollTimer = Timer.periodic(
        _foregroundPollingInterval,
        (_) => unawaited(
          pollAndNotify(trigger: "foreground_timer"),
        ),
      );
      await appendLog("Foreground-Polling aktiviert (alle 10 Minuten)");
    }

    if (triggerImmediate) {
      unawaited(
        pollAndNotify(trigger: "foreground_resume"),
      );
    }
  }

  static void _stopForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = null;
  }

  static Future<void> _syncBackgroundTask({required bool enabled}) async {
    if (syncBackgroundTaskOverride != null) {
      await syncBackgroundTaskOverride!(enabled: enabled);
      return;
    }

    if (!_workmanagerInitialized) {
      await Workmanager().initialize(
        notificationBackgroundDispatcher,
      );
      _workmanagerInitialized = true;
    }

    if (!enabled) {
      await Workmanager().cancelByUniqueName(_backgroundTaskUniqueName);
      await appendLog("Background-Task deaktiviert");
      return;
    }

    await Workmanager().registerPeriodicTask(
      _backgroundTaskUniqueName,
      _backgroundTaskName,
      frequency: _backgroundPollingInterval,
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    await appendLog(
      "Background-Task aktiviert (Android min. ca. 15 Min, OS-abhaengig)",
    );
  }

  static Future<bool> _requestNotificationPermission() async {
    if (requestNotificationPermissionOverride != null) {
      return requestNotificationPermissionOverride!();
    }

    if (Platform.isAndroid) {
      final granted = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? true;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final granted = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return granted ?? true;
    }

    return true;
  }

  static Future<List<Map<String, dynamic>>> _fetchUnreadNotifications() async {
    final secureStorage = getFlutterSecureStorage();
    final loginRaw = await secureStorage.read(key: "login");
    if (loginRaw == null) {
      await appendLog("Keine Login-Daten vorhanden, Polling uebersprungen");
      return const <Map<String, dynamic>>[];
    }

    dynamic loginJson;
    try {
      loginJson = json.decode(loginRaw);
    } catch (_) {
      await appendLog("Login-Daten konnten nicht gelesen werden");
      return const <Map<String, dynamic>>[];
    }

    final user = getString(loginJson["user"]);
    final pass = getString(loginJson["pass"]);
    final rawUrl = getString(loginJson["url"]);

    if (user == null || pass == null || rawUrl == null) {
      await appendLog("Login-Daten unvollstaendig, Polling uebersprungen");
      return const <Map<String, dynamic>>[];
    }

    final baseUrl = "${fixupUrl(rawUrl)}/v2";
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    dio.interceptors.add(CookieManager(DefaultCookieJar()));

    final loginResponse = await dio.post<dynamic>(
      "$baseUrl/api/auth/login",
      data: {
        "username": user,
        "password": pass,
      },
    );

    final loginMap = getMap(loginResponse.data);
    if ((getBool(loginMap?["loggedIn"]) ?? false) == false) {
      await appendLog("Login fuer Background-Polling fehlgeschlagen");
      return const <Map<String, dynamic>>[];
    }

    final unreadResponse =
        await dio.post<dynamic>("$baseUrl/api/notification/unread");

    if (unreadResponse.data is! List) {
      await appendLog("Unread-Endpoint lieferte keine Liste");
      return const <Map<String, dynamic>>[];
    }

    final unreadList = unreadResponse.data as List;
    return unreadList.map<Map<String, dynamic>>((dynamic entry) {
      final rawMap = getMap(entry);
      if (rawMap == null) return <String, dynamic>{};

      final normalized = <String, dynamic>{};
      rawMap.forEach((dynamic key, dynamic value) {
        normalized[key.toString()] = value;
      });
      return normalized;
    }).toList();
  }

  static NotificationReminderCandidate _toNotificationCandidate(
      Map<String, dynamic> n) {
    final id = getInt(n["id"]);
    final title = getString(n["title"]) ?? "";
    final subTitle = getString(n["subTitle"]);
    final type = getString(n["type"]) ?? "";
    final objectId = getInt(n["objectId"]);
    final timeSent = getString(n["timeSent"]) ?? "";

    final key = id != null
        ? "id:$id"
        : "hash:${_stableHash("$title|$subTitle|$type|$objectId|$timeSent")}";

    return NotificationReminderCandidate(
      key: key,
      title: title,
      body: subTitle,
    );
  }

  static Future<void> _showReminderNotification(
    NotificationReminderEntry entry,
  ) async {
    await _showNotification(
      NotificationDisplayRequest(
        id: _stableHash(entry.key) & 0x7fffffff,
        title: entry.title,
        body: entry.body,
        payload: entry.key,
      ),
    );
  }

  static Future<void> _showSummaryNotification(
    List<NotificationReminderEntry> dueEntries,
  ) async {
    final count = dueEntries.length;
    final previewTitles =
        dueEntries.take(3).map((entry) => entry.title).toList(growable: false);
    final body = previewTitles.join(", ");
    await _showNotification(
      NotificationDisplayRequest(
        id: _summaryNotificationId,
        title: "$count ungelesene Benachrichtigungen",
        body: body.isEmpty ? null : body,
        payload: "summary",
        lines: dueEntries.map((entry) => entry.title).toList(growable: false),
      ),
    );
  }

  static Future<void> _showNotification(
    NotificationDisplayRequest request,
  ) async {
    if (showNotificationOverride != null) {
      await showNotificationOverride!(request);
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      icon: "@mipmap/launcher_icon",
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      styleInformation: request.lines.isEmpty
          ? null
          : InboxStyleInformation(
              request.lines,
              contentTitle: request.title,
              summaryText: request.body,
            ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      request.id,
      request.title,
      request.body,
      details,
      payload: request.payload,
    );
  }

  static Future<void> _cancelSummaryNotification() async {
    await _cancelNotification(_summaryNotificationId);
  }

  static Future<void> _cancelNotification(int id) async {
    if (cancelNotificationOverride != null) {
      await cancelNotificationOverride!(id);
      return;
    }

    if (_isAndroid) {
      await _androidNotificationMethodChannel.invokeMethod<void>(
        "cancelNotificationSafely",
        <String, Object>{"id": id},
      );
      return;
    }

    await _notificationsPlugin.cancel(id);
  }

  static int _stableHash(String input) {
    var hash = 0x811C9DC5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static List<NotificationReminderEntry> _readReminderEntries(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_reminderEntriesKey);
    if (raw == null || raw.isEmpty) {
      return const <NotificationReminderEntry>[];
    }

    try {
      final decoded = json.decode(raw);
      final list = getList(decoded) ?? const <dynamic>[];
      return list
          .map((dynamic entry) => getMap(entry))
          .whereType<Map>()
          .map(
            (entry) => NotificationReminderEntry.fromJson(
              entry.map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .where((entry) => entry.key.isNotEmpty)
          .toList(growable: false);
    } catch (e, trace) {
      log(
        "Failed to parse stored notification reminders",
        error: e,
        stackTrace: trace,
      );
      return const <NotificationReminderEntry>[];
    }
  }

  static Future<void> _writeReminderEntries(
    SharedPreferences prefs,
    List<NotificationReminderEntry> entries,
  ) async {
    await prefs.setString(
      _reminderEntriesKey,
      json.encode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  static Future<_PollLeaseResult> _tryAcquirePollLease({
    required String trigger,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentTime = now;
    final lastCompleted =
        UtcDateTime.tryParse(prefs.getString(_pollLastCompletedKey) ?? "");
    if (lastCompleted != null &&
        currentTime.isBefore(lastCompleted.add(_pollDebounceWindow))) {
      return const _PollLeaseResult(
        acquired: false,
        token: "",
        reason: "kurz zuvor abgeschlossen",
      );
    }

    final leaseMap = getMap(
      prefs.getString(_pollLeaseKey) == null
          ? null
          : json.decode(prefs.getString(_pollLeaseKey)!),
    );
    final leaseExpiry =
        UtcDateTime.tryParse(getString(leaseMap?["expiresAt"]) ?? "");
    if (leaseExpiry != null && currentTime.isBefore(leaseExpiry)) {
      return const _PollLeaseResult(
        acquired: false,
        token: "",
        reason: "anderer Polling-Lauf aktiv",
      );
    }

    final token = "$trigger-${currentTime.microsecondsSinceEpoch}";
    await prefs.setString(
      _pollLeaseKey,
      json.encode(
        <String, Object?>{
          "token": token,
          "expiresAt": currentTime.add(_pollLeaseDuration).toIso8601String(),
        },
      ),
    );

    return _PollLeaseResult(
      acquired: true,
      token: token,
      reason: null,
    );
  }

  static Future<void> _releasePollLease({required String token}) async {
    final prefs = await SharedPreferences.getInstance();
    final leaseRaw = prefs.getString(_pollLeaseKey);
    if (leaseRaw != null) {
      final leaseMap = getMap(json.decode(leaseRaw));
      if (getString(leaseMap?["token"]) == token) {
        await prefs.remove(_pollLeaseKey);
      }
    }
    await prefs.setString(_pollLastCompletedKey, now.toIso8601String());
  }

  static Future<void> appendLog(String entry) async {
    final timestamp = now.toIso8601String();
    final msg = "$timestamp $entry";
    log(msg, name: "NotificationBackgroundService");

    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList(_backgroundLogsKey) ?? <String>[];
    logs.add(msg);
    if (logs.length > _backgroundLogLimit) {
      logs.removeRange(0, logs.length - _backgroundLogLimit);
    }
    await prefs.setStringList(_backgroundLogsKey, logs);
  }

  static Future<List<String>> getRecentLogs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_backgroundLogsKey) ?? const <String>[];
  }

  @visibleForTesting
  static bool get isForegroundPollingActive => _foregroundPollTimer != null;

  @visibleForTesting
  static Future<List<NotificationReminderEntry>>
      getStoredReminderEntries() async {
    final prefs = await SharedPreferences.getInstance();
    return _readReminderEntries(prefs);
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = null;
    _appInForeground = true;
    _notificationsInitialized = false;
    _workmanagerInitialized = false;
    fetchUnreadNotificationsOverride = null;
    requestNotificationPermissionOverride = null;
    showNotificationOverride = null;
    cancelNotificationOverride = null;
    syncBackgroundTaskOverride = null;
    initializeLocalNotificationsOverride = null;
    isAndroidOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reminderEntriesKey);
    await prefs.remove(_pollLeaseKey);
    await prefs.remove(_pollLastCompletedKey);
    await prefs.remove(_backgroundLogsKey);
    await prefs.remove(_pushEnabledKey);
  }
}
