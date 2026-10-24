import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'support/test_harness.dart';

class _Notifications extends Mock implements FlutterLocalNotificationsPlugin {}

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
      super.httpClient});
  @override
  bool get mobileBackgroundSupported => true;
}

class _SchoolApi implements HttpClientAdapter {
  _SchoolApi(this.events,
      {this.authenticated = true,
      this.responseGate,
      this.blockedPath = 'api/notification/unread'});
  final List<Map<String, Object?>> events;
  final bool authenticated;
  final Completer<void>? responseGate;
  final String blockedPath;
  final blocked = Completer<void>();
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
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
    await service.ingest(server, user, []);
  }

  test('denied permission never submits native alerts', () async {
    await service.activate(server, user, backgroundAllowed: true);
    await service.ingest(server, user, []);
    await service.ingest(server, user, [event(1)]);
    expect(service.granted, isFalse);
    expect(shown, isEmpty);
  });

  test('encrypted history survives restarting the real service', () async {
    await enable();
    await service.ingest(server, user, [event(1)]);
    service.dispose();
    service = SchoolNotificationService(
        native: native,
        storage: storage,
        permission: () async =>
            storage.storage['school-notification-desktop-consent'] == 'true',
        historyDirectory: () async => directory);
    await service.initialize(background: true);
    await service.ingest(server, user, [event(1)]);
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
    await service.ingest(server, user, [event(42, type: 'message')]);
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
    expect(call, [
      'New school message',
      'You have received a new message from your school.'
    ]);
  });

  test('deactivation cancels alerts and stops further delivery', () async {
    await enable();
    await service.deactivate();
    await service.ingest(server, user, [event(1)]);
    expect(shown, isEmpty);
    expect(storage.storage['school-notification-active'], isNull);
    verify(() => native.cancelAll()).called(greaterThanOrEqualTo(1));
  });

  test('stale feed from outgoing account is ignored', () async {
    await enable();
    await service.activate('https://other.example', user,
        backgroundAllowed: true);
    await service.ingest(server, user, [event(1)]);
    expect(shown, isEmpty);
  });

  test('read action suppresses later feed and clears native item', () async {
    await enable();
    await service.markViewed(server, user, [event(1)]);
    await service.ingest(server, user, [event(1)]);
    expect(shown, isEmpty);
    verify(() => native.cancel(id: any(named: 'id'))).called(2);
  });

  test('category preferences persist and re-enabling cannot replay old feed',
      () async {
    await enable();
    await service.setCategory(SchoolNotificationCategory.grade, false);
    await service.ingest(server, user, [event(1)]);
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
    await service.ingest(server, user, [event(1), event(2)]);
    await service.ingest(server, user, [event(1), event(2), event(3)]);
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
    await service.ingest(server, user, [event(1)]);
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
      await service.ingest(server, user, []);
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
    await service.ingest(server, user, []);
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
    await service.ingest(server, user, []);
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
    await service.ingest(server, user, []);
    await service.ingest(server, user, [event(1)]);
    await service.ingest(server, user, [event(1)]);
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
        await service.ingest(server, user, []);
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
          await service.ingest(server, user, [event(1)]);
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
    await service.ingest(server, user, [event(1)]);
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
