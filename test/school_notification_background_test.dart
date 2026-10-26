import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dr/school_notification_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workmanager/workmanager.dart';

class _Workmanager extends Mock implements Workmanager {}

class _SessionApi implements HttpClientAdapter {
  _SessionApi(this.id, {this.invalidFeed = false});
  final int id;
  final bool invalidFeed;
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final login = options.path == 'api/auth/login';
    return ResponseBody.fromString(
        jsonEncode(login
            ? {'loggedIn': true}
            : invalidFeed
                ? {'error': 'fixture'}
                : <Object>[]),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          if (login) 'set-cookie': ['session=$id; Path=/; Secure']
        });
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('headless bootstrap repairs an unregistered Android notification plugin',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // Reproduce a headless isolate whose Android Dart plugin is not selected.
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final plugin = FlutterLocalNotificationsPlugin();
    expect(
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>(),
        isNull);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    initializeSchoolNotificationBackground();
    expect(
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>(),
        isNotNull);
    expect(
        await plugin.initialize(
            settings: const InitializationSettings(
                android:
                    AndroidInitializationSettings('ic_school_notification'))),
        isTrue);
    expect(
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()!
            .areNotificationsEnabled(),
        isTrue);
    await plugin.show(
        id: 1,
        title: 'Register',
        notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('school_grade', 'Grades')));
    expect(calls.map((c) => c.method),
        ['initialize', 'areNotificationsEnabled', 'show']);
  });

  test('headless bootstrap also registers the existing iOS notification plugin',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    initializeSchoolNotificationBackground();
    expect(
        FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>(),
        isNotNull);
  });

  for (final android in [true, false]) {
    test('persistent schedule has the correct policy for android=$android',
        () async {
      final work = _Workmanager();
      final constraints = Constraints(networkType: NetworkType.connected);
      registerFallbackValue(constraints);
      when(() => work.registerPeriodicTask(
              schoolNotificationTask, schoolNotificationTask,
              frequency: any(named: 'frequency'),
              initialDelay: any(named: 'initialDelay'),
              constraints: any(named: 'constraints'),
              existingWorkPolicy: any(named: 'existingWorkPolicy'),
              backoffPolicy: any(named: 'backoffPolicy'),
              backoffPolicyDelay: any(named: 'backoffPolicyDelay')))
          .thenAnswer((_) async {});
      when(() => work.cancelByUniqueName(schoolNotificationTask))
          .thenAnswer((_) async {});
      final scheduler =
          SchoolNotificationScheduler(workmanager: work, android: android);
      await scheduler.schedule();
      await scheduler.schedule();
      final captured = verify(() => work.registerPeriodicTask(
          schoolNotificationTask, schoolNotificationTask,
          frequency: const Duration(minutes: 15),
          initialDelay: android ? Duration.zero : const Duration(minutes: 15),
          constraints: captureAny(named: 'constraints'),
          existingWorkPolicy: android
              ? ExistingPeriodicWorkPolicy.update
              : ExistingPeriodicWorkPolicy.keep,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(minutes: 1))).captured;
      expect(captured, hasLength(2));
      expect(
          captured
              .cast<Constraints>()
              .every((c) => c.networkType == NetworkType.connected),
          isTrue);
      await scheduler.cancel();
      verify(() => work.cancelByUniqueName(schoolNotificationTask)).called(1);
      verifyNever(() => work.cancelAll());
    });
  }

  test('foreground mark from a killed process or reboot never blocks a worker',
      () {
    final now = DateTime.utc(2026, 10, 25, 10);
    final mark = schoolNotificationForegroundMark(now, 123);
    expect(schoolNotificationHasForegroundMark(mark, now, 123), isTrue);
    expect(schoolNotificationHasForegroundMark(mark, now, 456), isFalse);
    expect(
        schoolNotificationHasForegroundMark(
            mark, now.add(const Duration(minutes: 6)), 123),
        isFalse);
    expect(
        schoolNotificationHasForegroundMark(
            mark, now.subtract(const Duration(days: 1)), 123),
        isFalse);
    expect(schoolNotificationHasForegroundMark('invalid', now, 123), isFalse);
  });

  test('each account round has its own cookies and closes its HTTP client',
      () async {
    final adapters = <_SessionApi>[];
    final client = SchoolNotificationFeedClient((options) {
      final api = _SessionApi(adapters.length + 1);
      adapters.add(api);
      return Dio(options)..httpClientAdapter = api;
    });
    for (final user in ['one', 'two', 'one']) {
      await client.fetch(
          server: 'https://school.example',
          user: user,
          password: 'fixture-password',
          budget: const Duration(seconds: 1));
    }
    for (final api in adapters) {
      expect(api.requests.map((r) => r.path),
          ['api/auth/login', 'api/notification/unread']);
      expect(api.requests.first.headers['cookie'], isNull);
      expect(api.requests.last.headers['cookie'], 'session=${api.id}');
      expect(api.requests.every((r) => !r.followRedirects), isTrue);
      expect(api.closed, isTrue);
    }
  });

  test('an invalid server feed fails without leaking the session', () async {
    final api = _SessionApi(1, invalidFeed: true);
    final client = SchoolNotificationFeedClient(
        (options) => Dio(options)..httpClientAdapter = api);
    await expectLater(
        client.fetch(
            server: 'https://school.example',
            user: 'one',
            password: 'fixture-password',
            budget: const Duration(seconds: 1)),
        throwsFormatException);
    expect(api.closed, isTrue);
  });
}
