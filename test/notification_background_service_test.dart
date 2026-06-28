import 'dart:async';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/notification_background_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

Map<String, dynamic> _unreadNotification({
  required int id,
  required String title,
  String? body,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'subTitle': body,
    'type': 'message',
    'objectId': id * 10,
    'timeSent': '2026-04-01T08:00:00.000Z',
  };
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    NotificationBackgroundService.initializeLocalNotificationsOverride =
        () async {};
    NotificationBackgroundService.syncBackgroundTaskOverride =
        ({required enabled}) async {};
    NotificationBackgroundService.requestNotificationPermissionOverride =
        () async => true;
  });

  tearDown(resetTestState);

  test('evaluateNotificationReminders keeps recent alerts quiet', () {
    final currentTime = UtcDateTime(2026, 4, 1, 8, 10);
    final previousEntries = <NotificationReminderEntry>[
      NotificationReminderEntry(
        key: 'id:1',
        title: 'Deutsch',
        body: 'Hausaufgabe',
        firstSeenAt: UtcDateTime(2026, 4, 1, 8),
        lastSeenAt: UtcDateTime(2026, 4, 1, 8, 1),
        lastAlertedAt: UtcDateTime(2026, 4, 1, 8, 2),
      ),
    ];

    final evaluation = evaluateNotificationReminders(
      previousEntries: previousEntries,
      unreadCandidates: const <NotificationReminderCandidate>[
        NotificationReminderCandidate(
          key: 'id:1',
          title: 'Deutsch',
          body: 'Hausaufgabe',
        ),
      ],
      currentTime: currentTime,
    );

    expect(evaluation.trackedEntries, hasLength(1));
    expect(evaluation.dueEntries, isEmpty);
    expect(
      evaluation.trackedEntries.single.lastSeenAt,
      currentTime,
    );
  });

  test('evaluateNotificationReminders marks overdue unread items as due', () {
    final currentTime = UtcDateTime(2026, 4, 1, 8, 13);
    final previousEntries = <NotificationReminderEntry>[
      NotificationReminderEntry(
        key: 'id:1',
        title: 'Deutsch',
        body: 'Hausaufgabe',
        firstSeenAt: UtcDateTime(2026, 4, 1, 8),
        lastSeenAt: UtcDateTime(2026, 4, 1, 8, 1),
        lastAlertedAt: UtcDateTime(2026, 4, 1, 8, 2),
      ),
    ];

    final evaluation = evaluateNotificationReminders(
      previousEntries: previousEntries,
      unreadCandidates: const <NotificationReminderCandidate>[
        NotificationReminderCandidate(
          key: 'id:1',
          title: 'Deutsch',
          body: 'Hausaufgabe',
        ),
      ],
      currentTime: currentTime,
    );

    expect(evaluation.dueEntries.map((entry) => entry.key), <String>['id:1']);
  });

  test('existing unread items alert on the first poll', () async {
    mockNow = UtcDateTime(2026, 4, 1, 8);
    final shown = <NotificationDisplayRequest>[];
    final unread = <Map<String, dynamic>>[
      _unreadNotification(id: 1, title: 'Mathe', body: 'Neue Nachricht'),
    ];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => unread;
    NotificationBackgroundService.showNotificationOverride =
        (request) async => shown.add(request);
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    await NotificationBackgroundService.pollAndNotify(trigger: 'initial');

    expect(shown, hasLength(1));
    expect(shown.single.title, 'Neue Mitteilung erhalten');
    expect(shown.single.body, isNull);
    final stored =
        await NotificationBackgroundService.getStoredReminderEntries();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'message');
    expect(stored.single.body, isEmpty);
    expect(stored.single.lastAlertedAt, mockNow);
  });

  test('new unread notifications alert immediately while older ones wait',
      () async {
    final shown = <NotificationDisplayRequest>[];
    var unread = <Map<String, dynamic>>[
      _unreadNotification(id: 1, title: 'Alt', body: 'Schon bekannt'),
    ];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => unread;
    NotificationBackgroundService.showNotificationOverride =
        (request) async => shown.add(request);
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    await NotificationBackgroundService.pollAndNotify(trigger: 'first');

    shown.clear();
    unread = <Map<String, dynamic>>[
      _unreadNotification(id: 1, title: 'Alt', body: 'Schon bekannt'),
      _unreadNotification(id: 2, title: 'Neu', body: 'Sofort melden'),
    ];
    mockNow = UtcDateTime(2026, 4, 1, 8, 1);
    await NotificationBackgroundService.pollAndNotify(trigger: 'second');

    expect(shown, hasLength(1));
    expect(shown.single.title, 'Neue Mitteilung erhalten');
    expect(shown.single.body, isNull);
  });

  test('unread notifications do not re-alert before 10 minutes', () async {
    final shown = <NotificationDisplayRequest>[];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => <Map<String, dynamic>>[
              _unreadNotification(id: 1, title: 'Deutsch', body: 'Aufgabe'),
            ];
    NotificationBackgroundService.showNotificationOverride =
        (request) async => shown.add(request);
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    await NotificationBackgroundService.pollAndNotify(trigger: 'first');

    shown.clear();
    mockNow = UtcDateTime(2026, 4, 1, 8, 9);
    await NotificationBackgroundService.pollAndNotify(trigger: 'second');

    expect(shown, isEmpty);
  });

  test('unread notifications re-alert after 10 minutes', () async {
    final shown = <NotificationDisplayRequest>[];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => <Map<String, dynamic>>[
              _unreadNotification(id: 1, title: 'Deutsch', body: 'Aufgabe'),
            ];
    NotificationBackgroundService.showNotificationOverride =
        (request) async => shown.add(request);
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    await NotificationBackgroundService.pollAndNotify(trigger: 'first');

    shown.clear();
    mockNow = UtcDateTime(2026, 4, 1, 8, 10);
    await NotificationBackgroundService.pollAndNotify(trigger: 'second');

    expect(shown, hasLength(1));
    expect(shown.single.title, 'Neue Mitteilung erhalten');
    expect(shown.single.body, isNull);
  });

  test('disappeared unread notifications are removed from tracking', () async {
    var unread = <Map<String, dynamic>>[
      _unreadNotification(id: 1, title: 'Deutsch', body: 'Aufgabe'),
      _unreadNotification(id: 2, title: 'Mathe', body: 'Test'),
    ];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => unread;
    NotificationBackgroundService.showNotificationOverride = (_) async {};
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    await NotificationBackgroundService.pollAndNotify(trigger: 'first');

    unread = <Map<String, dynamic>>[
      _unreadNotification(id: 2, title: 'Mathe', body: 'Test'),
    ];
    mockNow = UtcDateTime(2026, 4, 1, 8, 1);
    await NotificationBackgroundService.pollAndNotify(trigger: 'second');

    final stored =
        await NotificationBackgroundService.getStoredReminderEntries();
    expect(stored.map((entry) => entry.key), <String>['id:2']);
  });

  test('multiple due unread notifications collapse into one summary reminder',
      () async {
    final shown = <NotificationDisplayRequest>[];
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => <Map<String, dynamic>>[
              _unreadNotification(id: 1, title: 'Deutsch', body: 'Aufgabe'),
              _unreadNotification(id: 2, title: 'Mathe', body: 'Test'),
            ];
    NotificationBackgroundService.showNotificationOverride =
        (request) async => shown.add(request);
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    await NotificationBackgroundService.pollAndNotify(trigger: 'summary');

    expect(shown, hasLength(1));
    expect(shown.single.payload, 'summary');
    expect(shown.single.title, 'Neue Benachrichtigungen erhalten');
    expect(shown.single.body, isNull);
    expect(shown.single.lines, isEmpty);
  });

  test('duplicate message notifications collapse before counting', () {
    final deduped = NotificationBackgroundService.dedupeCandidates(
      <NotificationReminderCandidate>[
        const NotificationReminderCandidate(
          key: 'notif:5100',
          title: 'Neue Mitteilung Mathematik',
          body: 'Nachricht von Lehrperson',
          dedupeId: 'msg:100',
        ),
        const NotificationReminderCandidate(
          key: 'msg:100',
          title: 'Nachricht von Lehrperson',
          body: 'Neue Mitteilung Mathematik',
          dedupeId: 'msg:100',
        ),
      ],
    );

    expect(deduped, hasLength(1));
    expect(deduped.single.dedupeId, 'msg:100');
  });

  test('parses current user id from config page', () {
    expect(
      NotificationBackgroundService.parseCurrentUserIdForTest(
        'var currentUserId=3539;var currentUserName="st-test";',
      ),
      3539,
    );
    expect(
      NotificationBackgroundService.parseCurrentUserIdForTest(
        'var currentUserName="st-test";',
      ),
      isNull,
    );
  });

  test('detects self-sent messages by fromUserId', () {
    expect(
      NotificationBackgroundService.isSentByCurrentUserForTest(
        <String, dynamic>{
          'id': 12,
          'fromUserId': 3539,
          'timeRead': null,
        },
        currentUserId: 3539,
      ),
      isTrue,
    );
    expect(
      NotificationBackgroundService.isSentByCurrentUserForTest(
        <String, dynamic>{
          'id': 13,
          'fromUserId': 5547,
          'timeRead': null,
        },
        currentUserId: 3539,
      ),
      isFalse,
    );
  });

  test('filters notifications that refer to self-sent messages', () {
    expect(
      NotificationBackgroundService.isMessageNotificationForIdsForTest(
        <String, dynamic>{
          'type': 'message',
          'objectId': 2684,
        },
        <int>{2684},
      ),
      isTrue,
    );
    expect(
      NotificationBackgroundService.isMessageNotificationForIdsForTest(
        <String, dynamic>{
          'type': 'grade',
          'objectId': 2684,
        },
        <int>{2684},
      ),
      isFalse,
    );
  });

  test('overlapping poll invocations do not double-alert', () async {
    final shown = <NotificationDisplayRequest>[];
    final releaseNotification = Completer<void>();
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => <Map<String, dynamic>>[
              _unreadNotification(id: 1, title: 'Deutsch', body: 'Aufgabe'),
            ];
    NotificationBackgroundService.showNotificationOverride = (request) async {
      shown.add(request);
      await releaseNotification.future;
    };
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    mockNow = UtcDateTime(2026, 4, 1, 8);
    final first =
        NotificationBackgroundService.pollAndNotify(trigger: 'overlap_first');
    await Future<void>.delayed(Duration.zero);
    final second =
        NotificationBackgroundService.pollAndNotify(trigger: 'overlap_second');
    await Future<void>.delayed(Duration.zero);
    releaseNotification.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(shown, hasLength(1));
  });

  test('permission denial leaves notifications disabled', () async {
    NotificationBackgroundService.requestNotificationPermissionOverride =
        () async => false;

    final enabled = await NotificationBackgroundService.setEnabled(
      enabled: true,
      triggerImmediatePoll: false,
    );

    expect(enabled, isFalse);
    expect(await NotificationBackgroundService.isEnabled(), isFalse);
    expect(NotificationBackgroundService.isForegroundPollingActive, isFalse);
  });

  test('foreground polling resumes without an immediate poll', () async {
    var fetchCount = 0;
    NotificationBackgroundService.fetchUnreadNotificationsOverride = () async {
      fetchCount++;
      return const <Map<String, dynamic>>[];
    };
    NotificationBackgroundService.showNotificationOverride = (_) async {};
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    await NotificationBackgroundService.setEnabled(
      enabled: true,
      triggerImmediatePoll: false,
    );
    expect(NotificationBackgroundService.isForegroundPollingActive, isTrue);

    await NotificationBackgroundService.handleAppPaused();
    expect(NotificationBackgroundService.isForegroundPollingActive, isFalse);

    await NotificationBackgroundService.handleAppResumed();
    await Future<void>.delayed(Duration.zero);
    expect(NotificationBackgroundService.isForegroundPollingActive, isTrue);
    expect(fetchCount, 0);
  });

  test(
      'logged-in bootstrap enables polling without an immediate background login',
      () async {
    var fetchCount = 0;
    NotificationBackgroundService.fetchUnreadNotificationsOverride = () async {
      fetchCount++;
      return const <Map<String, dynamic>>[];
    };
    NotificationBackgroundService.showNotificationOverride = (_) async {};
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    final store = createStore(
      initialState: AppState(
        (b) => b..settingsState.pushNotificationsEnabled = true,
      ),
      withMiddleware: true,
    );

    await store.actions.loginActions.loggedIn(
      LoggedInPayload(
        (b) => b
          ..username = 'anna'
          ..fromStorage = true
          ..offlineOnly = true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(NotificationBackgroundService.isForegroundPollingActive, isTrue);
    expect(fetchCount, 0);
  });

  test('disabling notifications stops foreground polling', () async {
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => const <Map<String, dynamic>>[];
    NotificationBackgroundService.showNotificationOverride = (_) async {};
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    await NotificationBackgroundService.setEnabled(
      enabled: true,
      triggerImmediatePoll: false,
    );
    expect(NotificationBackgroundService.isForegroundPollingActive, isTrue);

    await NotificationBackgroundService.setEnabled(
      enabled: false,
      triggerImmediatePoll: false,
    );

    expect(NotificationBackgroundService.isForegroundPollingActive, isFalse);
  });

  test('disabling notifications on Android uses the safe cancel path',
      () async {
    final cancelled = <int>[];
    NotificationBackgroundService.isAndroidOverride = () => true;
    NotificationBackgroundService.cancelNotificationOverride =
        (id) async => cancelled.add(id);

    await NotificationBackgroundService.setEnabled(
      enabled: false,
      triggerImmediatePoll: false,
    );

    expect(cancelled, hasLength(1));
  });

  test('logout stops foreground polling', () async {
    NotificationBackgroundService.fetchUnreadNotificationsOverride =
        () async => const <Map<String, dynamic>>[];
    NotificationBackgroundService.showNotificationOverride = (_) async {};
    NotificationBackgroundService.cancelNotificationOverride = (_) async {};

    await NotificationBackgroundService.setEnabled(
      enabled: true,
      triggerImmediatePoll: false,
    );
    expect(NotificationBackgroundService.isForegroundPollingActive, isTrue);

    final store = createStore(
      initialState: AppState(
        (b) => b
          ..loginState.loggedIn = true
          ..settingsState.pushNotificationsEnabled = true,
      ),
      withMiddleware: true,
    );

    await store.actions.loginActions.logout(
      LogoutPayload(
        (b) => b
          ..hard = false
          ..forced = true,
      ),
    );

    expect(NotificationBackgroundService.isForegroundPollingActive, isFalse);
  });
}
