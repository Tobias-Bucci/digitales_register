import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_background.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/test_harness.dart';

class _Notifications extends Mock implements FlutterLocalNotificationsPlugin {}

class _Scheduler extends Mock implements SchoolNotificationScheduler {}

class _Database extends Fake implements Database {
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action,
          {bool? exclusive}) =>
      action(_Transaction());
}

class _Transaction extends Fake implements Transaction {
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 1;
}

class _Busy extends Fake implements DatabaseException {
  @override
  int? getResultCode() => 5;
}

class _BusyDatabase extends _Database {
  int attempts = 0;
  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action,
      {bool? exclusive}) {
    if (attempts++ == 0) throw _Busy();
    return super.transaction(action, exclusive: exclusive);
  }
}

class _MobileService extends SchoolNotificationService {
  _MobileService(
      {super.native,
      super.storage,
      super.database,
      super.historyDirectory,
      super.permission,
      super.httpClient,
      super.backgroundBudget,
      super.backgroundAccountBudget,
      super.scheduler,
      this.android = false});
  final bool android;
  @override
  bool get mobileBackgroundSupported => true;
  @override
  bool get androidBackgroundSupported => android;
}

class _SchoolApi implements HttpClientAdapter {
  _SchoolApi(this.events,
      {this.authenticated = true,
      this.failureType,
      this.responseGate,
      this.blockedPath = 'api/notification/unread'});
  final List<Map<String, Object?>> events;
  final bool authenticated;
  final DioExceptionType? failureType;
  final Completer<void>? responseGate;
  final String blockedPath;
  final blocked = Completer<void>();
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (failureType != null)
      throw DioException(requestOptions: options, type: failureType!);
    if (responseGate != null && options.path == blockedPath) {
      if (!blocked.isCompleted) blocked.complete();
      await responseGate!.future;
    }
    return ResponseBody.fromString(
        jsonEncode(options.path == 'api/auth/login'
            ? {'loggedIn': authenticated}
            : events),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

class _StalledLoginApi extends _SchoolApi {
  _StalledLoginApi() : super([]);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await cancelFuture;
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }
}

extension _BackgroundHarness on SchoolNotificationService {
  Future<void> ingestAsBackground(String server, String user, List events) =>
      ingest(server, user, events, background: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Notifications native;
  late TestSecureStorage storage;
  late Directory directory;
  late SchoolNotificationService service;
  final shown = <String>[];
  DidReceiveNotificationResponseCallback? tapHandler;
  const server = 'https://school.example';
  const user = 'student';

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'en'});
    directory =
        await Directory.systemTemp.createTemp('dr_school_notifications_');
    storage = TestSecureStorage();
    native = _Notifications();
    when(() => native.getNotificationAppLaunchDetails())
        .thenAnswer((_) async => null);
    shown.clear();
    when(() => native.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse')))
        .thenAnswer((call) async {
      tapHandler = call.namedArguments[#onDidReceiveNotificationResponse]
          as DidReceiveNotificationResponseCallback?;
      return true;
    });
    when(() => native.getActiveNotifications()).thenAnswer((_) async => []);
    when(() => native.cancelAll()).thenAnswer((_) async {});
    when(() => native.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    when(() => native.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).thenAnswer((invocation) async {
      shown.add(invocation.namedArguments[#payload] as String);
    });
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async =>
            storage.storage['school-notification-desktop-consent'] == 'true',
        historyDirectory: () async => directory);
    // These pre-existing delivery tests exercise already opted-in accounts.
    for (final url in [
      server,
      'https://other.example',
      'https://other-school.example'
    ]) {
      storage.storage[
              'school-notification-preferences-v1-${service.accountKey(url, user)}'] =
          jsonEncode({
        'decision': 'accepted',
        'enabled': true,
        'grades': true,
        'messages': true
      });
    }
    await service.initialize(background: true);
  });
  tearDown(() async {
    service.dispose();
    await directory.delete(recursive: true);
  });

  Map<String, Object?> event(int id, {String type = 'grade'}) => {
        'id': id,
        'objectId': id,
        'type': type,
        'timeSent':
            DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
        'title': 'Sensitive mathematics grade 8',
        'subTitle': 'Private school message',
      };
  Future<void> enable() async {
    storage.storage['school-notification-desktop-consent'] = 'true';
    await service.reload();
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, []);
  }

  Future<_SchoolApi> mobile(
      {List<Map<String, Object?>>? events,
      bool authenticated = true,
      Completer<void>? gate,
      DioExceptionType? failureType,
      bool android = false,
      SchoolNotificationScheduler? scheduler,
      Duration budget = const Duration(seconds: 20)}) async {
    service.dispose();
    final api = _SchoolApi(events ?? [event(1)],
        authenticated: authenticated,
        responseGate: gate,
        failureType: failureType);
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        android: android,
        scheduler: scheduler,
        backgroundBudget: budget,
        historyDirectory: () async => directory,
        httpClient: (options) => Dio(options)..httpClientAdapter = api);
    await service.initialize(background: true);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingest(server, user, []);
    storage.storage['login'] =
        jsonEncode({'url': server, 'user': user, 'pass': 'fixture-password'});
    storage.storage.remove(
        'school-notification-last-sync-${service.accountKey(server, user)}');
    return api;
  }

  test(
      'normal opening consumes new events silently and does not mark them read',
      () async {
    await enable();
    await service.ingest(server, user, [event(1), event(2, type: 'message')]);
    expect(shown, isEmpty);
    await service.ingestAsBackground(
        server, user, [event(1), event(2, type: 'message')]);
    expect(shown, isEmpty,
        reason: 'opening must not leave a delayed delivery queue');
    expect(service.diagnostics['lastDetectedAt'], isNotNull);
    expect(service.diagnostics['lastNotificationRequestedAt'], isNull);
  });

  test('resume clears only personal alerts without a mark-as-read request',
      () async {
    await enable();
    await service.ingestAsBackground(server, user, [event(1)]);
    final submittedId = verify(() => native.show(
        id: captureAny(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).captured.single as int;
    when(() => native.getActiveNotifications()).thenAnswer((_) async => [
          const ActiveNotification(id: 100, channelId: 'school_grade'),
          const ActiveNotification(id: 200, channelId: 'announcements'),
        ]);
    await service.enterForeground();
    verify(() => native.cancel(id: submittedId)).called(1);
    expect(storage.storage['school-notification-alert-ids-v1'], isNull);
    verify(() => native.cancel(id: 100)).called(1);
    verifyNever(() => native.cancel(id: 200));
    verifyNever(() => native.cancelAll());
  });

  test('large batches produce one generic alert per category', () async {
    await enable();
    await service.ingestAsBackground(server, user, [
      for (var i = 0; i < 10; i++) event(i),
      for (var i = 10; i < 20; i++) event(i, type: 'message'),
    ]);
    expect(shown, hasLength(2));
    expect(
        shown
            .map(SchoolNotificationDestination.decode)
            .every((e) => e!.objectId == null),
        isTrue);
    final titles = verify(() => native.show(
        id: any(named: 'id'),
        title: captureAny(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).captured;
    expect(titles, ['New grades', 'New school messages']);
    await service.setShowEventCount(true);
    await service.ingestAsBackground(server, user, [event(30), event(31)]);
    verify(() => native.show(
        id: any(named: 'id'),
        title: '2 new grades',
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).called(1);
  });

  test(
      'master switch preserves categories and re-enables with a quiet baseline',
      () async {
    await enable();
    await service.setEnabled(false);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, isEmpty);
    expect(service.preferences.grades, isTrue);
    await service.setEnabled(true);
    await service.ingestAsBackground(server, user, [event(1), event(2)]);
    expect(shown, isEmpty);
    await service.ingestAsBackground(server, user, [event(3)]);
    expect(shown, hasLength(1));
  });

  test('malformed personal data cannot establish a false empty baseline',
      () async {
    await enable();
    await expectLater(
        service.ingestAsBackground(server, user, [
          {'type': 'grade', 'id': 123, 'timeSent': 'invalid'}
        ]),
        throwsFormatException);
    expect(shown, isEmpty);
    await service.ingestAsBackground(server, user, [event(123)]);
    expect(shown, hasLength(1));
  });

  test(
      'background success is separate from foreground success and notification request',
      () async {
    await mobile();
    await service.ingest(server, user, []);
    expect(service.diagnostics['lastBackgroundSuccessAt'], isNull);
    storage.storage.remove(
        'school-notification-last-sync-${service.accountKey(server, user)}');
    await service.backgroundSync();
    expect(service.diagnostics['lastBackgroundStartedAt'], isNotNull);
    expect(service.diagnostics['lastBackgroundSuccessAt'], isNotNull);
    expect(service.diagnostics['lastNotificationRequestedAt'], isNotNull);
    expect(service.diagnostics['lastNotificationAcceptedAt'], isNotNull);
    expect(service.diagnostics.containsKey('deliveredAt'), isFalse);
  });

  test('rejected authentication pauses retries until a new app session',
      () async {
    final api = await mobile(authenticated: false);
    await service.backgroundSync();
    await service.backgroundSync();
    expect(api.requests, hasLength(1));
    expect(service.diagnostics['backgroundResult'], 'authenticationRequired');
    expect(service.diagnostics['lastBackgroundSuccessAt'], isNull);
    await service.activate(server, user, backgroundAllowed: true);
    await service.backgroundSync();
    expect(api.requests, hasLength(2));
  });

  test('two headless engines cannot authenticate the same account concurrently',
      () async {
    final gate = Completer<void>();
    final api = await mobile(gate: gate);
    final work = service.backgroundSync();
    await api.blocked.future;
    final second = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        historyDirectory: () async => directory,
        httpClient: (options) => Dio(options)..httpClientAdapter = api);
    try {
      await second.initialize(background: true);
      await second.backgroundSync();
      expect(api.requests, hasLength(2));
    } finally {
      gate.complete();
      await work;
      second.dispose();
    }
    expect(shown, hasLength(1));
  });

  test('expired worker lease recovers after an interrupted run', () async {
    final api = await mobile();
    final account = service.accountKey(server, user);
    storage.storage['school-notification-lease-$account'] = DateTime.now()
        .add(const Duration(minutes: 1))
        .toUtc()
        .toIso8601String();
    await service.backgroundSync();
    expect(api.requests, isEmpty);
    storage.storage['school-notification-lease-$account'] = DateTime.now()
        .subtract(const Duration(seconds: 1))
        .toUtc()
        .toIso8601String();
    await service.backgroundSync();
    expect(api.requests, hasLength(2));
    expect(storage.storage['school-notification-lease-$account'], isNull);
  });

  test('multiple schools use isolated credentials, preferences and payloads',
      () async {
    final api = await mobile();
    const other = 'https://other-school.example';
    await service.activate(other, user, backgroundAllowed: true);
    await service.ingest(other, user, []);
    await service.setCategory(SchoolNotificationCategory.message, false);
    await service.activate(server, user, backgroundAllowed: true);
    expect(service.preferences.messages, isTrue);
    storage.storage['login'] = jsonEncode({
      'url': server,
      'user': user,
      'pass': 'fixture-a',
      'otherAccounts': [
        {'url': other, 'user': user, 'pass': 'fixture-b'}
      ]
    });
    for (final url in [server, other]) {
      storage.storage.remove(
          'school-notification-last-sync-${service.accountKey(url, user)}');
    }
    await service.backgroundSync();
    expect(api.requests, hasLength(4));
    expect(
        api.requests
            .where((r) => r.path == 'api/auth/login')
            .map((r) => r.baseUrl)
            .toSet(),
        {'https://school.example/v2/', 'https://other-school.example/v2/'});
    expect(
        shown
            .map((p) => SchoolNotificationDestination.decode(p)!.account)
            .toSet(),
        {service.accountKey(server, user), service.accountKey(other, user)});
    await service.forgetAccount(other, user);
    shown.clear();
    storage.storage.remove(
        'school-notification-last-sync-${service.accountKey(server, user)}');
    await service.backgroundSync();
    expect(api.requests, hasLength(6));
    expect(shown, isEmpty,
        reason: 'known active-account event must not replay');
  });

  test('removing an account during a request cannot resurrect its history',
      () async {
    final gate = Completer<void>();
    final api = await mobile(gate: gate);
    final work = service.backgroundSync();
    await api.blocked.future;
    await service.forgetAccount(server, user);
    gate.complete();
    await work;
    expect(shown, isEmpty);
    expect(service.diagnostics['lastBackgroundSuccessAt'], isNull);
  });

  test('payload resolves only a saved account and rejects deleted accounts',
      () async {
    await mobile();
    storage.storage['login'] = jsonEncode({
      'url': server,
      'user': user,
      'pass': 'fixture',
      'otherAccounts': [
        {'url': 'https://other.example', 'user': user, 'pass': 'fixture'}
      ]
    });
    final other = service.accountKey('https://other.example', user);
    expect(
        await service.savedAccountIndex(other,
            loggedIn: true, noPasswordSaving: false),
        0);
    expect(
        await service.savedAccountIndex(other,
            loggedIn: false, noPasswordSaving: true),
        1);
    expect(
        await service.savedAccountIndex(notificationDigest(['missing']),
            loggedIn: true, noPasswordSaving: false),
        isNull);
  });

  test('only one notification-driven account switch preserves the queued tap',
      () async {
    await enable();
    final destination = SchoolNotificationDestination(
        service.accountKey(server, user), SchoolNotificationCategory.grade, 1);
    service.pendingDestination = destination;
    service.preserveDestinationForNextAccountSwitch();
    await service.deactivate(switchingAccount: true);
    expect(service.pendingDestination, same(destination));
    await service.deactivate(switchingAccount: true);
    expect(service.pendingDestination, isNull);
  });

  test('offline failures release the lease and permit a later retry', () async {
    final api = await mobile(failureType: DioExceptionType.connectionError);
    await expectLater(service.backgroundSync(), throwsA(isA<DioException>()));
    expect(service.diagnostics['backgroundResult'], 'networkError');
    expect(service.diagnostics['lastBackgroundSuccessAt'], isNull);
    await expectLater(service.backgroundSync(), throwsA(isA<DioException>()));
    expect(api.requests, hasLength(2));
  });

  test(
      'the shared deadline cancels a stalled request without advancing success',
      () async {
    final gate = Completer<void>();
    await mobile(gate: gate, budget: const Duration(milliseconds: 100));
    try {
      await expectLater(service.backgroundSync(), throwsA(isA<DioException>()));
      expect(service.diagnostics['backgroundResult'], 'timeout');
      expect(service.diagnostics['lastBackgroundSuccessAt'], isNull);
      expect(service.diagnostics['lastNotificationRequestedAt'], isNull);
    } finally {
      gate.complete();
    }
  });

  test('a native failure retains claims and never reports known presentation',
      () async {
    await mobile();
    when(() => native.show(
            id: any(named: 'id'),
            title: any(named: 'title'),
            body: any(named: 'body'),
            notificationDetails: any(named: 'notificationDetails'),
            payload: any(named: 'payload')))
        .thenThrow(StateError('native unavailable'));
    await expectLater(service.backgroundSync(), throwsStateError);
    expect(
        service.diagnostics['backgroundResult'], 'storageOrNotificationError');
    expect(service.diagnostics['lastNotificationRequestedAt'], isNotNull);
    expect(service.diagnostics['lastNotificationAcceptedAt'], isNull);
    await service.backgroundSync();
    verify(() => native.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).called(1);
  });

  test('legacy category choices migrate without being reset', () async {
    storage.storage.remove(
        'school-notification-preferences-v1-${service.accountKey(server, user)}');
    storage.storage['school-notification-active'] =
        service.accountKey(server, user);
    storage.storage['school-notification-preferences-v1'] =
        jsonEncode({'grades': false, 'messages': true});
    await service.activate(server, user, backgroundAllowed: true);
    expect(service.preferences.grades, isFalse);
    expect(service.preferences.messages, isTrue);
    expect(service.preferences.showEventCount, isFalse);
    await service.setEnabled(false);
    await service.reload();
    expect(service.preferences.enabled, isFalse);
    expect(service.preferences.grades, isFalse);
  });

  test(
      'an existing single-account worker upgrades without losing its enrollment',
      () async {
    await mobile();
    storage.storage.remove('school-notification-accounts-v1');
    await service.backgroundSync();
    expect(shown, hasLength(1));
    service.dispose();
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        historyDirectory: () async => directory);
    when(() => native.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse')))
        .thenThrow(StateError('native initialization unavailable'));
    await service.forgetAccount(server, user);
    expect(storage.storage['school-notification-active'], isNull);
    await service.markViewed(server, user, [event(1)]);
    await service.backgroundSync();
    expect(shown, hasLength(1));
  });

  test(
      'granting permission again establishes fresh baselines for every enrolled account',
      () async {
    await enable();
    await service.activate('https://other.example', user,
        backgroundAllowed: true);
    await service.ingestAsBackground('https://other.example', user, []);
    storage.storage['school-notification-desktop-consent'] = 'false';
    await service.reload();
    storage.storage['school-notification-desktop-consent'] = 'true';
    await service.reload();
    await service.ingestAsBackground('https://other.example', user, [event(1)]);
    expect(shown, isEmpty);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, [event(2)]);
    expect(shown, isEmpty);
    await service.ingestAsBackground(server, user, [event(3)]);
    expect(shown, hasLength(1));
  });

  for (final language in ['de', 'en', 'it', 'lld']) {
    test('generic plural notifications are localized in $language', () async {
      SharedPreferences.setMockInitialValues({'appLanguage': language});
      await enable();
      await service.setShowEventCount(true);
      await service.ingestAsBackground(server, user, [event(1), event(2)]);
      final title = verify(() => native.show(
          id: any(named: 'id'),
          title: captureAny(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'))).captured.single;
      expect(
          title,
          {
            'de': '2 neue Noten',
            'en': '2 new grades',
            'it': '2 nuovi voti',
            'lld': '2 notes nueves'
          }[language]);
    });
  }

  test('denied permission never submits native alerts', () async {
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, []);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(service.granted, isFalse);
    expect(shown, isEmpty);
  });

  test('encrypted history survives restarting the real service', () async {
    await enable();
    await service.ingestAsBackground(server, user, [event(1)]);
    service.dispose();
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async =>
            storage.storage['school-notification-desktop-consent'] == 'true',
        historyDirectory: () async => directory);
    await service.initialize(background: true);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, hasLength(1));
    final file = File('${directory.path}/school_notification_history_v1.hive');
    expect(String.fromCharCodes(await file.readAsBytes()),
        isNot(contains('Sensitive')));
    expect(
        storage.storage.keys
            .where((k) => k.startsWith('school-notifications-v1')),
        isEmpty);
  });

  test('native content stays generic and payload routes to exact message',
      () async {
    await enable();
    await service
        .ingestAsBackground(server, user, [event(42, type: 'message')]);
    final destination = SchoolNotificationDestination.decode(shown.single)!;
    expect(destination.objectId, 42);
    expect(destination.category, SchoolNotificationCategory.message);
    expect(destination.account, service.accountKey(server, user));
    final call = verify(() => native.show(
        id: any(named: 'id'),
        title: captureAny(named: 'title'),
        body: captureAny(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).captured;
    expect(call,
        ['New school message', 'You have received a new school message.']);
  });

  test('deactivation cancels alerts and stops further delivery', () async {
    await enable();
    await service.deactivate();
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, isEmpty);
    expect(storage.storage['school-notification-active'], isNull);
    verifyNever(() => native.cancelAll());
  });

  test('stale feed from outgoing account is ignored', () async {
    await enable();
    await service.activate('https://other.example', user,
        backgroundAllowed: true);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, isEmpty);
  });

  test('read action suppresses later feed and clears native item', () async {
    await enable();
    await service.markViewed(server, user, [event(1)]);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, isEmpty);
    verify(() => native.cancel(id: any(named: 'id'))).called(3);
  });

  test('category preferences persist and re-enabling cannot replay old feed',
      () async {
    await enable();
    await service.setCategory(SchoolNotificationCategory.grade, false);
    await service.ingestAsBackground(server, user, [event(1)]);
    service.dispose();
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async =>
            storage.storage['school-notification-desktop-consent'] == 'true',
        historyDirectory: () async => directory);
    await service.initialize(background: true);
    expect(service.preferences.grades, isFalse);
    expect(service.preferences.messages, isTrue);
    await service.setCategory(SchoolNotificationCategory.grade, true);
    await service.ingestAsBackground(server, user, [event(1), event(2)]);
    await service
        .ingestAsBackground(server, user, [event(1), event(2), event(3)]);
    expect(shown, hasLength(1));
  });

  test('unavailable background scheduler leaves foreground sync functional',
      () async {
    service.dispose();
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async =>
            storage.storage['school-notification-desktop-consent'] == 'true',
        database: () async => _Database(),
        historyDirectory: () async => directory);
    await service.initialize(background: true);
    await enable();
    await service.schedule();
    expect(service.backgroundAvailable, isFalse);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, hasLength(1));
  });

  for (final authenticated in [true, false]) {
    test(
        'background HTTP flow handles ${authenticated ? 'new events' : 'expired or two-factor authentication'}',
        () async {
      service.dispose();
      final api = _SchoolApi([event(1), event(2, type: 'message')],
          authenticated: authenticated);
      service = _MobileService(
          native: native,
          storage: storage,
          permission: () async => true,
          database: () async => _Database(),
          historyDirectory: () async => directory,
          httpClient: (options) => Dio(options)..httpClientAdapter = api);
      await service.initialize(background: true);
      await service.activate(server, user, backgroundAllowed: true);
      await service.ingestAsBackground(server, user, []);
      storage.storage['login'] = jsonEncode(
          {'url': server, 'user': user, 'pass': 'test-only-password'});
      storage.storage.remove(
          'school-notification-last-sync-${service.accountKey(server, user)}');
      await service.backgroundSync();
      expect(
          api.requests.map((r) => r.path),
          authenticated
              ? ['api/auth/login', 'api/notification/unread']
              : ['api/auth/login']);
      expect(shown, hasLength(authenticated ? 2 : 0));
      expect(api.requests.first.followRedirects, isFalse);
      if (authenticated) {
        await service.backgroundSync();
        expect(api.requests, hasLength(2), reason: 'recent checks coalesce');
      }
    });
  }

  test('background worker skips an active foreground session', () async {
    service.dispose();
    final api = _SchoolApi([event(1)]);
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        historyDirectory: () async => directory,
        httpClient: (options) => Dio(options)..httpClientAdapter = api);
    await service.initialize(background: true);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, []);
    storage.storage.remove(
        'school-notification-last-sync-${service.accountKey(server, user)}');
    storage.storage['login'] =
        jsonEncode({'url': server, 'user': user, 'pass': 'test-only-password'});
    storage.storage['school-notification-foreground-until'] = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 6))
        .toIso8601String();
    await service.backgroundSync();
    expect(api.requests, isEmpty);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.reload();
    expect(storage.storage['school-notification-foreground-until'], isNull);
    await service.backgroundSync();
    expect(api.requests, hasLength(2));
    expect(shown, hasLength(1));
  });

  test('expired crash heartbeat allows background delivery', () async {
    service.dispose();
    final api = _SchoolApi([event(1)]);
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        historyDirectory: () async => directory,
        httpClient: (options) => Dio(options)..httpClientAdapter = api);
    await service.initialize(background: true);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, []);
    storage.storage.remove(
        'school-notification-last-sync-${service.accountKey(server, user)}');
    storage.storage['login'] =
        jsonEncode({'url': server, 'user': user, 'pass': 'test-only-password'});
    storage.storage['school-notification-foreground-until'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    await service.backgroundSync();
    expect(shown, hasLength(1));
  });

  test('account switching keeps periodic work, explicit logout cancels it',
      () async {
    final scheduler = _Scheduler();
    when(() => scheduler.schedule()).thenAnswer((_) async {});
    when(() => scheduler.cancel()).thenAnswer((_) async {});
    await mobile(scheduler: scheduler);
    clearInteractions(scheduler);
    await service.deactivate(switchingAccount: true);
    verifyNever(() => scheduler.cancel());
    await service.activate('https://other-school.example', user,
        backgroundAllowed: true);
    verify(() => scheduler.schedule()).called(1);
    verifyNever(() => scheduler.cancel());
    await service.deactivate();
    verify(() => scheduler.cancel()).called(1);
  });

  test('one slow school cannot consume the entire multi-account round',
      () async {
    service.dispose();
    final stalled = _StalledLoginApi();
    final healthy = _SchoolApi([event(1)]);
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => _Database(),
        historyDirectory: () async => directory,
        backgroundBudget: const Duration(seconds: 2),
        backgroundAccountBudget: const Duration(milliseconds: 80),
        httpClient: (options) => Dio(options)
          ..httpClientAdapter = options.baseUrl.contains('other-school.example')
              ? healthy
              : stalled);
    await service.initialize(background: true);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingest(server, user, []);
    await service.activate('https://other-school.example', user,
        backgroundAllowed: true);
    await service.ingest('https://other-school.example', user, []);
    for (final url in [server, 'https://other-school.example']) {
      storage.storage.remove(
          'school-notification-last-sync-${service.accountKey(url, user)}');
    }
    storage.storage['login'] = jsonEncode({
      'url': server,
      'user': user,
      'pass': 'fixture-password',
      'otherAccounts': [
        {
          'url': 'https://other-school.example',
          'user': user,
          'pass': 'fixture-password'
        }
      ]
    });
    await expectLater(service.backgroundSync(), throwsA(isA<DioException>()));
    expect(stalled.requests, hasLength(1));
    expect(healthy.requests, hasLength(2));
    expect(shown, hasLength(1));
    expect(SchoolNotificationDestination.decode(shown.single)!.account,
        service.accountKey('https://other-school.example', user));
  });

  test('malformed shared messages cannot silently establish a baseline',
      () async {
    await enable();
    await expectLater(
        service.ingestAsBackground(server, user, [
          {'type': 'messageShared', 'id': 1}
        ]),
        throwsFormatException);
    await expectLater(service.ingestAsBackground(server, user, ['invalid']),
        throwsFormatException);
  });

  test('Android ignores a stale heartbeat when no Activity is visible',
      () async {
    const channel = MethodChannel('dr/school_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final api = await mobile(android: true);
    storage.storage['school-notification-foreground-until'] =
        DateTime.now().add(const Duration(minutes: 6)).toIso8601String();
    storage.storage['school-notification-foreground-v2'] =
        schoolNotificationForegroundMark(DateTime.now(), pid + 1);
    await service.backgroundSync();
    expect(api.requests, hasLength(2));
    expect(shown, hasLength(1));
  });

  test('Android checks native visibility before authenticating', () async {
    const channel = MethodChannel('dr/school_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final api = await mobile(android: true);
    await service.backgroundSync();
    expect(api.requests, isEmpty);
    expect(shown, isEmpty);
  });

  test('a missing Android lifecycle channel fails before authenticating',
      () async {
    final api = await mobile(android: true);
    await expectLater(
        service.backgroundSync(), throwsA(isA<MissingPluginException>()));
    expect(api.requests, isEmpty);
    expect(shown, isEmpty);
  });

  test('Android discards a feed if an Activity opens during the request',
      () async {
    var visible = false;
    const channel = MethodChannel('dr/school_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => visible);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final gate = Completer<void>();
    final api = await mobile(android: true, gate: gate);
    final work = service.backgroundSync();
    await api.blocked.future;
    visible = true;
    gate.complete();
    await work;
    expect(shown, isEmpty);
    expect(service.diagnostics['backgroundResult'], 'superseded');
  });

  test(
      'an expired worker cannot commit after another engine acquired its lease',
      () async {
    final gate = Completer<void>();
    final api = await mobile(gate: gate);
    final work = service.backgroundSync();
    await api.blocked.future;
    storage.storage[
            'school-notification-lease-${service.accountKey(server, user)}'] =
        'replacement-lease';
    gate.complete();
    await work;
    expect(shown, isEmpty);
    expect(
        storage.storage[
            'school-notification-lease-${service.accountKey(server, user)}'],
        'replacement-lease');
  });

  test('transient SQLite contention yields and retries before touching history',
      () async {
    service.dispose();
    final database = _BusyDatabase();
    service = _MobileService(
        native: native,
        storage: storage,
        permission: () async => true,
        database: () async => database,
        historyDirectory: () async => directory);
    await service.initialize(background: true);
    expect(database.attempts, 2);
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingestAsBackground(server, user, []);
    await service.ingestAsBackground(server, user, [event(1)]);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, hasLength(1));
  });

  for (final blockedPath in ['api/auth/login', 'api/notification/unread']) {
    for (final change in [
      'none',
      'logout',
      'switch-back',
      'credentials',
      'foreground',
      'permission',
      'background-disabled',
      'category',
      'foreground-sync'
    ]) {
      test('slow $blockedPath releases storage lock and rechecks $change',
          () async {
        service.dispose();
        final gate = Completer<void>();
        final api = _SchoolApi([event(1)],
            responseGate: gate, blockedPath: blockedPath);
        var permitted = true;
        service = _MobileService(
            native: native,
            storage: storage,
            permission: () async => permitted,
            database: () async => _Database(),
            historyDirectory: () async => directory,
            httpClient: (options) => Dio(options)..httpClientAdapter = api);
        await service.initialize(background: true);
        await service.activate(server, user, backgroundAllowed: true);
        await service.ingestAsBackground(server, user, []);
        final account = service.accountKey(server, user);
        storage.storage['login'] = jsonEncode(
            {'url': server, 'user': user, 'pass': 'test-only-password'});
        storage.storage.remove('school-notification-last-sync-$account');
        final work = service.backgroundSync();
        try {
          await api.blocked.future.timeout(const Duration(seconds: 2));
          expect(identical(work, service.backgroundSync()), isTrue,
              reason: 'overlapping calls share the in-flight request');
          // This would time out with the old implementation, even though
          // permission/history work has no dependency on the server response.
          await service.reload().timeout(const Duration(seconds: 2));
          switch (change) {
            case 'logout':
              await service.deactivate();
            case 'switch-back':
              await service.activate('https://other.example', user,
                  backgroundAllowed: true);
              await service.activate(server, user, backgroundAllowed: true);
            case 'credentials':
              storage.storage['login'] = jsonEncode(
                  {'url': server, 'user': user, 'pass': 'new-test-password'});
            case 'foreground':
              service.didChangeAppLifecycleState(AppLifecycleState.resumed);
              await service.reload();
            case 'permission':
              permitted = false;
            case 'background-disabled':
              await service.activate(server, user, backgroundAllowed: false);
            case 'category':
              await service.setCategory(
                  SchoolNotificationCategory.grade, false);
            case 'foreground-sync':
              await service.ingest(server, user, []);
            case 'none':
              break;
          }
        } finally {
          gate.complete();
          await work;
        }
        expect(shown, hasLength(change == 'none' ? 1 : 0));
        if (change == 'none') {
          await service.ingestAsBackground(server, user, [event(1)]);
          expect(shown, hasLength(1), reason: 'commit claims remain durable');
        }
      });
    }
  }

  test('overlapping initialization runs native setup only once', () async {
    service.dispose();
    final gate = Completer<bool?>();
    when(() => native.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse')))
        .thenAnswer((_) => gate.future);
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async => true,
        historyDirectory: () async => directory);
    clearInteractions(native);
    final first = service.initialize(background: true);
    final second = service.initialize(background: true);
    expect(identical(first, second), isTrue);
    gate.complete(true);
    await Future.wait([first, second]);
    verify(() => native.initialize(
        settings: any(named: 'settings'),
        onDidReceiveNotificationResponse:
            any(named: 'onDidReceiveNotificationResponse'))).called(1);
  });

  test('logout invalidates activation still waiting for initialization',
      () async {
    service.dispose();
    final gate = Completer<bool?>();
    when(() => native.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse')))
        .thenAnswer((_) => gate.future);
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async => true,
        historyDirectory: () async => directory);
    final activation = service.activate(server, user, backgroundAllowed: true);
    await service.deactivate();
    gate.complete(true);
    await activation;
    expect(storage.storage['school-notification-active'], isNull);
    expect(storage.storage['school-notification-session'], isNull);
    await service.ingestAsBackground(server, user, [event(1)]);
    expect(shown, isEmpty);
  });

  test('cold launch queues destination and warm tap invokes routing handler',
      () async {
    service.dispose();
    final account = service.accountKey(server, user);
    final destination = SchoolNotificationDestination(
        account, SchoolNotificationCategory.message, 42);
    when(() => native.getNotificationAppLaunchDetails()).thenAnswer((_) async =>
        NotificationAppLaunchDetails(true,
            notificationResponse: NotificationResponse(
                notificationResponseType:
                    NotificationResponseType.selectedNotification,
                payload: destination.encode())));
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async => false,
        historyDirectory: () async => directory);
    await service.initialize();
    expect(service.pendingDestination!.objectId, 42);
    expect(service.pendingDestination!.account, account);
    int? opened;
    service.onTap = () async {
      opened = service.pendingDestination?.objectId;
    };
    tapHandler!(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: SchoolNotificationDestination(
                account, SchoolNotificationCategory.message, 99)
            .encode()));
    await Future<void>.delayed(Duration.zero);
    expect(opened, 99);
  });
}
