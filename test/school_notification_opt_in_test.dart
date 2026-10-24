import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

class _Native extends Mock implements FlutterLocalNotificationsPlugin {}

class _Disk extends MapBase<String, String> {
  final _data = <String, String>{};
  bool failDecisions = false;
  @override
  String? operator [](Object? key) => _data[key];
  @override
  void operator []=(String key, String value) {
    if (failDecisions &&
        key.startsWith('school-notification-preferences-v1-') &&
        (jsonDecode(value) as Map)['decision'] != 'unknown')
      throw StateError('write failed');
    _data[key] = value;
  }

  @override
  Iterable<String> get keys => _data.keys;
  @override
  void clear() => _data.clear();
  @override
  String? remove(Object? key) => _data.remove(key);
}

class _Storage extends TestSecureStorage {
  _Storage(this.storage);
  @override
  final _Disk storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestSecureStorage storage;
  late _Disk disk;
  late _Native native;
  late SchoolNotificationService service;
  var allowed = false;
  var canAsk = true;
  var grantOnRequest = true;
  var requests = 0;
  var shows = 0;
  const server = 'https://school.example';
  const user = 'student';
  const secondServer = 'https://other-school.example';

  SchoolNotificationService create() => SchoolNotificationService(
        native: native,
        storage: storage,
        historyDirectory: () async => directory,
        permission: () async => allowed,
        canRequestPermission: () async => canAsk,
        permissionRequest: () async {
          // App consent and the permanent ask marker must exist before native UI.
          expect(
              service.preferences.consent, SchoolNotificationConsent.accepted);
          expect(storage.storage['school-notification-permission-requested-v1'],
              'true');
          requests++;
          allowed = grantOnRequest;
        },
      );

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'en'});
    directory = await Directory.systemTemp.createTemp('dr_notification_optin_');
    disk = _Disk();
    storage = _Storage(disk);
    native = _Native();
    allowed = false;
    canAsk = true;
    grantOnRequest = true;
    requests = 0;
    shows = 0;
    when(() => native.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse')))
        .thenAnswer((_) async => true);
    when(() => native.getActiveNotifications()).thenAnswer((_) async => []);
    when(() => native.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    when(() => native.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
        payload: any(named: 'payload'))).thenAnswer((_) async {
      shows++;
    });
    service = create();
    await service.initialize(background: true);
  });
  tearDown(() async {
    service.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> login([String url = server]) =>
      service.activate(url, user, backgroundAllowed: true);
  Map<String, Object> event(int id) => {
        'type': 'grade',
        'id': id,
        'objectId': id,
        'timeSent':
            DateTime.now().add(const Duration(minutes: 1)).toIso8601String()
      };
  String getKey(String url) =>
      'school-notification-preferences-v1-${service.accountKey(url, user)}';
  Future<void> restart() async {
    service.dispose();
    service = create();
    await service.initialize(background: true);
    await login();
  }

  test(
      'fresh installation stays disabled even with OS permission and preselected categories',
      () async {
    allowed = true;
    await login();
    expect(service.preferences.enabled, isFalse);
    expect(service.preferences.grades, isTrue);
    expect(service.preferences.messages, isTrue);
    expect(service.preferences.consent, SchoolNotificationConsent.unknown);
    expect(await service.pendingOptIn(), isNotNull);
    await service.ingest(server, user, [], background: true);
    await service.ingest(server, user, [event(1)], background: true);
    expect(shows, 0);
    expect(requests, 0);
  });

  test(
      'an update with only observed permission and old history still asks once',
      () async {
    storage.storage['school-notification-active'] =
        service.accountKey(server, user);
    storage.storage['school-notification-permission'] = 'true';
    allowed = true;
    await login();
    final offer = (await service.pendingOptIn())!;
    expect(service.preferences.enabled, isFalse);
    await service.decideOptIn(offer, accept: false);
    await restart();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.enabled, isFalse);
    expect(requests, 0);
  });

  test(
      'acceptance saves selected categories before permission and baselines old events quietly',
      () async {
    await login();
    var refreshes = 0;
    service.refresh = () async {
      refreshes++;
      await service.ingest(server, user, [event(1)]);
    };
    await service.decideOptIn((await service.pendingOptIn())!,
        accept: true, grades: true, messages: false);
    expect(requests, 1);
    expect(refreshes, 1);
    expect(service.preferences.enabled, isTrue);
    expect(service.preferences.messages, isFalse);
    expect(shows, 0);
    await service.ingest(server, user, [event(1)], background: true);
    expect(shows, 0);
    await service.ingest(server, user, [event(2)], background: true);
    expect(shows, 1);
    await restart();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.messages, isFalse);
    expect(requests, 1);
  });

  test(
      'decline is durable, keeps both category selections and never asks the OS',
      () async {
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: false);
    await restart();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.consent, SchoolNotificationConsent.declined);
    expect(service.preferences.enabled, isFalse);
    expect(service.preferences.grades, isTrue);
    expect(service.preferences.messages, isTrue);
    expect(requests, 0);
  });

  for (final settings in [
    {'enabled': false, 'grades': true, 'messages': true},
    {'grades': false, 'messages': false},
    {'enabled': true, 'grades': false, 'messages': true},
  ]) {
    test('existing explicit account settings are preserved: $settings',
        () async {
      storage.storage[getKey(server)] = jsonEncode(settings);
      await login();
      expect(await service.pendingOptIn(), isNull);
      expect(service.preferences.grades, settings['grades']);
      expect(service.preferences.messages, settings['messages']);
      expect(service.preferences.enabled,
          settings['enabled'] != false && settings['messages'] == true);
      expect(requests, 0);
    });
  }

  test(
      'legacy global choices migrate for old accounts without consenting a new account',
      () async {
    storage.storage['school-notification-active'] =
        service.accountKey(server, user);
    storage.storage['school-notification-preferences-v1'] =
        jsonEncode({'grades': false, 'messages': true});
    await login();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.enabled, isTrue);
    expect(service.preferences.grades, isFalse);
    await login(secondServer);
    expect(service.preferences.enabled, isFalse);
    expect((await service.pendingOptIn())!.account,
        service.accountKey(secondServer, user));
    expect(service.preferences.grades, isTrue);
    await service.decideOptIn((await service.pendingOptIn())!, accept: false);
    await login();
    expect(service.preferences.enabled, isTrue);
    expect(service.preferences.grades, isFalse);
  });

  test('legacy global disabling is never automatically re-enabled', () async {
    storage.storage['school-notification-preferences-v1'] =
        jsonEncode({'enabled': false});
    await login();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.enabled, isFalse);
    expect(requests, 0);
  });

  test(
      'multiple accounts keep separate decisions and share a single native permission request',
      () async {
    grantOnRequest = false;
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: true);
    expect(requests, 1);
    await login(secondServer);
    expect(service.preferences.enabled, isFalse);
    await service.decideOptIn((await service.pendingOptIn())!, accept: true);
    expect(requests, 1,
        reason: 'OS denial must not be asked again for another account');
    await service.requestPermission();
    await service.setEnabled(false);
    await service.setEnabled(true);
    expect(requests, 1);
    expect(service.granted, isFalse);
    expect(await service.pendingOptIn(), isNull);
  });

  test('a known pre-update system denial opens no further permission prompt',
      () async {
    canAsk = false;
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: true);
    expect(requests, 0);
    expect(service.permissionRequested, isTrue);
    expect(service.granted, isFalse);
    expect(service.preferences.consent, SchoolNotificationConsent.accepted);
  });

  test('already authorized OS permission causes no native request', () async {
    allowed = true;
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: true);
    expect(requests, 0);
    expect(service.preferences.enabled, isTrue);
  });

  test(
      'a delayed decision cannot apply to another account or a new session of the same account',
      () async {
    await login();
    final old = (await service.pendingOptIn())!;
    await login(secondServer);
    expect(await service.decideOptIn(old, accept: true), isFalse);
    expect(service.preferences.enabled, isFalse);
    await login();
    expect(await service.decideOptIn(old, accept: true), isFalse);
    expect(service.preferences.consent, SchoolNotificationConsent.unknown);
    expect(requests, 0);
  });

  test(
      'settings can change a declined decision without replaying the initial offer',
      () async {
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: false);
    await service.setEnabled(true);
    expect(service.preferences.consent, SchoolNotificationConsent.accepted);
    expect(requests, 1);
    await service.setEnabled(false);
    await restart();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.enabled, isFalse);
  });

  test('two users at one school keep independent opt-in decisions', () async {
    await login();
    await service.decideOptIn((await service.pendingOptIn())!, accept: true);
    final first = service.activeAccount;
    await service.activate(server, 'second-student', backgroundAllowed: true);
    expect(service.activeAccount, isNot(first));
    expect(service.preferences.enabled, isFalse);
    await service.decideOptIn((await service.pendingOptIn())!, accept: false);
    await login();
    expect(service.preferences.enabled, isTrue);
    expect(await service.pendingOptIn(), isNull);
    expect(requests, 1);
  });

  test(
      'saved accounts migrate legacy choices after logout; later new accounts still ask',
      () async {
    storage.storage['school-notification-preferences-v1'] =
        jsonEncode({'grades': false, 'messages': true});
    await service.migrateLegacyDecisions([(server, user)]);
    await login();
    expect(await service.pendingOptIn(), isNull);
    expect(service.preferences.enabled, isTrue);
    expect(service.preferences.grades, isFalse);
    await service.migrateLegacyDecisions([(secondServer, user)]);
    await login(secondServer);
    expect(service.preferences.enabled, isFalse);
    expect(await service.pendingOptIn(), isNotNull);
  });

  test('an unknown or corrupt consent value cannot enable notifications',
      () async {
    storage.storage[getKey(server)] = jsonEncode({
      'decision': 'unrecognized',
      'enabled': true,
      'grades': true,
      'messages': true
    });
    await login();
    expect(service.preferences.enabled, isFalse);
    expect(await service.pendingOptIn(), isNotNull);
  });

  test(
      'a failed decision write leaves consent unknown and requests no native permission',
      () async {
    await login();
    final offer = (await service.pendingOptIn())!;
    disk.failDecisions = true;
    await expectLater(
        service.decideOptIn(offer, accept: true), throwsStateError);
    expect(requests, 0);
    expect(await service.pendingOptIn(), isNotNull);
    expect((jsonDecode(disk[getKey(server)]!) as Map)['decision'], 'unknown');
    disk.failDecisions = false;
    await service.decideOptIn(offer, accept: true);
    expect(requests, 1);
    expect(await service.pendingOptIn(), isNull);
  });
}
