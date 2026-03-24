import 'dart:convert';
import 'dart:developer';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/desktop.dart';
import 'package:dr/util.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _backgroundTaskUniqueName = "dr_notification_polling_unique";
const _backgroundTaskName = "dr_notification_polling_task";
const _pushEnabledKey = "pushNotificationsEnabled";
const _knownNotificationIdsKey = "knownBackgroundNotificationIds";
const _backgroundLogsKey = "backgroundNotificationLogs";
const _backgroundLogLimit = 200;

const _channelId = "dr_background_notifications";
const _channelName = "Digitales Register Benachrichtigungen";
const _channelDescription =
    "Lokale Benachrichtigungen fuer neue Mitteilungen";

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

// ignore: avoid_classes_with_only_static_members
class NotificationBackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;
  static bool _workmanagerInitialized = false;

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
    await appendLog(
      "Service initialisiert, pushEnabled=$enabled",
    );
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pushEnabledKey) ?? false;
  }

  static Future<void> setEnabled({required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushEnabledKey, enabled);

    await ensureLocalNotificationsInitialized();
    if (enabled) {
      await _requestNotificationPermission();
    }

    await _syncBackgroundTask(enabled: enabled);
    await appendLog("Push Notifications gesetzt auf: $enabled");
  }

  static Future<void> _syncBackgroundTask({required bool enabled}) async {
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
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    await appendLog(
      "Background-Task aktiviert (Intervall OS-abhaengig, min. ~15 Min auf Android)",
    );
  }

  static Future<void> ensureLocalNotificationsInitialized() async {
    if (_notificationsInitialized) return;

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

  static Future<void> _requestNotificationPermission() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestPermission();

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  static Future<void> pollAndNotify({required String trigger}) async {
    final unread = await _fetchUnreadNotifications();
    final prefs = await SharedPreferences.getInstance();

    final knownIds = prefs.getStringList(_knownNotificationIdsKey) ?? <String>[];
    final knownSet = knownIds.toSet();

    final normalized = unread.map(_toNotificationCandidate).toList();
    final allCurrentIds = normalized.map((n) => n.key).toSet();

    if (knownSet.isEmpty && allCurrentIds.isNotEmpty) {
      await prefs.setStringList(
        _knownNotificationIdsKey,
        allCurrentIds.toList(),
      );
      await appendLog(
        "[$trigger] Initialer Seed: ${allCurrentIds.length} IDs gespeichert, keine Pushes gesendet",
      );
      return;
    }

    final newNotifications = normalized
        .where((notification) => !knownSet.contains(notification.key))
        .toList();

    if (newNotifications.isEmpty) {
      await prefs.setStringList(
        _knownNotificationIdsKey,
        allCurrentIds.toList(),
      );
      await appendLog("[$trigger] Keine neuen Notifications gefunden");
      return;
    }

    for (final notification in newNotifications) {
      await _showLocalNotification(notification);
    }

    await prefs.setStringList(
      _knownNotificationIdsKey,
      allCurrentIds.toList(),
    );

    await appendLog(
      "[$trigger] ${newNotifications.length} neue Notifications: ${newNotifications.map((e) => e.key).join(",")}",
    );
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
        connectTimeout: 15000,
        receiveTimeout: 15000,
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

  static _NotificationCandidate _toNotificationCandidate(Map<String, dynamic> n) {
    final id = getInt(n["id"]);
    final title = getString(n["title"]) ?? "";
    final subTitle = getString(n["subTitle"]);
    final type = getString(n["type"]) ?? "";
    final objectId = getInt(n["objectId"]);
    final timeSent = getString(n["timeSent"]) ?? "";

    final key = id != null
        ? "id:$id"
        : "hash:${_stableHash("$title|$subTitle|$type|$objectId|$timeSent")}";

    return _NotificationCandidate(
      key: key,
      title: title,
      body: subTitle,
    );
  }

  static Future<void> _showLocalNotification(
      _NotificationCandidate notification) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      icon: "@mipmap/launcher_icon",
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      _stableHash(notification.key) & 0x7fffffff,
      notification.title,
      notification.body,
      details,
      payload: notification.key,
    );
  }

  static int _stableHash(String input) {
    var hash = 0x811C9DC5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static Future<void> appendLog(String entry) async {
    final now = DateTime.now().toIso8601String();
    final msg = "$now $entry";
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
}

class _NotificationCandidate {
  final String key;
  final String title;
  final String? body;

  const _NotificationCandidate({
    required this.key,
    required this.title,
    required this.body,
  });
}
