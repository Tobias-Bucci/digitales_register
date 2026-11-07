import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/notifications_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

Notification _school(int id, UtcDateTime time, {String? subTitle}) =>
    Notification((b) => b
      ..id = id
      ..title = 'school $id'
      ..subTitle = subTitle
      ..timeSent = time);

ServerNotification _app(String id, DateTime publishedAt) => ServerNotification(
      id: id,
      revision: 1,
      attentionRevision: 1,
      title: 'app $id',
      body: 'Text',
      type: const ServerNotificationType(
        key: 'info',
        label: 'Info',
        colorValue: null,
        icon: 'info',
        critical: false,
      ),
      publishedAt: publishedAt,
      expiresAt: null,
      link: null,
    );

const _bell = Key('server-notification-bell');

void main() {
  group('combinedNotificationFeed', () {
    test('merges both sources, newest first', () {
      final local = DateTime.utc(2026, 3, 2, 12).toLocal();
      final later = UtcDateTime.makeUtc(local.add(const Duration(hours: 1)));
      final earlier =
          UtcDateTime.makeUtc(local.subtract(const Duration(hours: 1)));

      final feed = combinedNotificationFeed(
        school: [_school(1, later), _school(2, earlier)],
        app: [
          _app('6a1f9c52-7c7e-4f39-9a55-111111111111',
              DateTime.utc(2026, 3, 2, 12))
        ],
      );

      expect(feed.map((entry) => entry.runtimeType),
          [SchoolFeedEntry, AppFeedEntry, SchoolFeedEntry]);
    });

    test('compares the school wall clock with the time of the device', () {
      final published = DateTime.utc(2026, 3, 2, 12);
      final entry = AppFeedEntry(
        _app('6a1f9c52-7c7e-4f39-9a55-222222222222', published),
      );
      expect(entry.time, UtcDateTime.makeUtc(published.toLocal()));
    });

    test('keeps the order of entries of the same moment', () {
      final time = UtcDateTime(2026, 3, 2);
      final feed = combinedNotificationFeed(
        school: [for (var i = 0; i < 20; i++) _school(i, time)],
        app: const [],
      );
      expect(
        feed.map((entry) => (entry as SchoolFeedEntry).notification.id),
        [for (var i = 0; i < 20; i++) i],
      );
    });
  });

  group('the one bell', () {
    setUp(bootstrapTestEnvironment);
    tearDown(resetTestState);

    AppState state(List<Notification> notifications) => AppState((b) => b
      ..notificationState.notifications =
          ListBuilder<Notification>(notifications));

    testWidgets('counts the notifications of the school', (tester) async {
      final store = createStore(
        initialState: state([
          _school(1, UtcDateTime(2026, 3, 2)),
          _school(2, UtcDateTime(2026, 3, 1)),
        ]),
      );
      await pumpApp(
        tester,
        store: store,
        home: const Material(child: NotificationIconContainer()),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 200));

      expect(find.byKey(_bell), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('the center shows school notifications in full',
        (tester) async {
      final long = 'Lang ' * 80;
      final store = createStore(
        initialState: state([
          _school(1, UtcDateTime(2026, 3, 2), subTitle: long.trim()),
        ]),
      );
      await pumpApp(tester, store: store, home: NotificationPageContainer());
      await settleFor(tester, duration: const Duration(milliseconds: 200));

      await tester.tap(find.text('school 1'));
      await settleFor(tester, duration: const Duration(milliseconds: 500));

      expect(find.byType(SelectableText), findsNWidgets(2));
      expect(find.text(long.trim()), findsOneWidget);
    });

    testWidgets('an entry about a message opens the message', (tester) async {
      final opened = <int>[];
      final store = createStore(initialState: state(const []));
      await pumpApp(
        tester,
        store: store,
        home: ServerNotificationCenterPage(
          onRefresh: () {},
          school: SchoolNotificationFeed(
            notifications: [
              Notification((b) => b
                ..id = 1
                ..title = 'school 1'
                ..type = 'message'
                ..objectId = 42
                ..timeSent = UtcDateTime(2026, 3, 2)),
            ],
            noInternet: false,
            onMarkRead: (_) => fail('a message is read where it is'),
            onMarkAllRead: () {},
            onOpenMessage: opened.add,
          ),
        ),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 200));

      await tester.tap(find.text('school 1'));
      await settleFor(tester, duration: const Duration(milliseconds: 200));

      expect(opened, [42]);
      expect(find.byType(SchoolNotificationDetailView), findsNothing);
    });

    testWidgets('offline, reading an entry leaves it unread', (tester) async {
      final read = <Notification>[];
      final store = createStore(initialState: state(const []));
      await pumpApp(
        tester,
        store: store,
        home: ServerNotificationCenterPage(
          onRefresh: () {},
          school: SchoolNotificationFeed(
            notifications: [_school(1, UtcDateTime(2026, 3, 2))],
            noInternet: true,
            onMarkRead: read.add,
            onMarkAllRead: () {},
            onOpenMessage: (_) {},
          ),
        ),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 200));

      await tester.tap(find.text('school 1'));
      await settleFor(tester, duration: const Duration(milliseconds: 500));

      expect(find.byType(SchoolNotificationDetailView), findsOneWidget);
      expect(read, isEmpty);
    });
  });
}
