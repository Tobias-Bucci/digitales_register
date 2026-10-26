import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/school_api_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const schoolNotificationTask = 'it.bucci.digitalesregister.schoolRefresh';
const schoolNotificationInterval = Duration(minutes: 15);
const schoolNotificationAccountBudget = Duration(seconds: 20);

/// A WorkManager engine has its own Dart plugin singletons. In particular,
/// flutter_local_notifications 22 no longer selects Android/iOS in its factory.
/// Register explicitly, as the reference's background_check.dart does through
/// DartPluginRegistrant, without calling that API on an engine's root isolate.
void initializeSchoolNotificationBackground() {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    IOSFlutterLocalNotificationsPlugin.registerWith();
  }
}

/// Same persistent, network-constrained periodic mechanism as the reference.
/// UPDATE keeps the original enqueue time and upgrades old job constraints.
class SchoolNotificationScheduler {
  SchoolNotificationScheduler({Workmanager? workmanager, bool? android})
      : _workmanager = workmanager ?? Workmanager(),
        _android = android ?? Platform.isAndroid;
  final Workmanager _workmanager;
  final bool _android;

  Future<void> initialize(Function dispatcher) =>
      _workmanager.initialize(dispatcher);

  Future<void> cancel() =>
      _workmanager.cancelByUniqueName(schoolNotificationTask);

  Future<void> schedule() => _workmanager.registerPeriodicTask(
        schoolNotificationTask,
        schoolNotificationTask,
        frequency: schoolNotificationInterval,
        // The reference permits the first Android run immediately. A UI run
        // still skips authentication; baselines suppress the old unread inbox.
        initialDelay: _android ? Duration.zero : schoolNotificationInterval,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: _android
            ? ExistingPeriodicWorkPolicy.update
            : ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
}

String schoolNotificationForegroundMark(DateTime now, int processId) =>
    jsonEncode({
      'pid': processId,
      'until': now.toUtc().add(const Duration(minutes: 6)).toIso8601String(),
    });

bool schoolNotificationHasForegroundMark(
    String? raw, DateTime now, int processId) {
  if (raw == null) return false;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['pid'] != processId) return false;
    final until = DateTime.tryParse('${decoded['until']}');
    return until != null &&
        until.isAfter(now.toUtc()) &&
        until.difference(now.toUtc()) <= const Duration(minutes: 6);
  } on FormatException {
    return false;
  }
}

class SchoolNotificationAuthenticationRequired implements Exception {
  const SchoolNotificationAuthenticationRequired();
}

/// One isolated school session per account and round, matching the reference.
/// This client intentionally has no UI/session-refresh/diagnostic interceptors.
class SchoolNotificationFeedClient {
  SchoolNotificationFeedClient(this.createClient);
  final Dio Function(BaseOptions) createClient;

  Future<List> fetch({
    required String server,
    required String user,
    required String password,
    required Duration budget,
  }) async {
    final dio = createClient(BaseOptions(
        baseUrl: schoolApiBase(server),
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        followRedirects: false));
    final cookies = CookieJar();
    dio.interceptors.add(CookieManager(cookies));
    final cancellation = CancelToken();
    final deadline =
        Timer(budget, () => cancellation.cancel('Background refresh deadline'));
    try {
      final response = (await dio.post<dynamic>(schoolLoginEndpoint,
              data: {'username': user, 'password': password},
              cancelToken: cancellation))
          .data;
      final auth = response is String ? jsonDecode(response) : response;
      if (auth is! Map) {
        throw const FormatException('Invalid school authentication response');
      }
      if (auth['loggedIn'] != true && auth['loggedIn'] != 1) {
        throw const SchoolNotificationAuthenticationRequired();
      }
      final unread = (await dio.post<dynamic>(schoolUnreadNotificationsEndpoint,
              data: <String, Object?>{}, cancelToken: cancellation))
          .data;
      final data = unread is String ? jsonDecode(unread) : unread;
      if (data is! List) {
        throw const FormatException('Invalid school notification feed');
      }
      return data;
    } finally {
      deadline.cancel();
      dio.close(force: true);
      await cookies.deleteAll();
    }
  }
}
