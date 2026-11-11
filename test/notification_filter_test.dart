import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/data.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

Notification _school(int id) => Notification((b) => b
  ..id = id
  ..title = 'school $id'
  ..timeSent = UtcDateTime(2026, 3, id));

ServerNotificationType _type(String key) => ServerNotificationType(
      key: key,
      label: switch (key) {
        'update' => 'Update',
        'event' => 'Veranstaltung',
        _ => 'Info',
      },
      colorValue: null,
      icon: 'info',
      critical: false,
    );

ServerNotification _app(String id, String type) => ServerNotification(
      id: id,
      revision: 1,
      attentionRevision: 1,
      title: 'app $id',
      body: 'Text',
      type: _type(type),
      publishedAt: DateTime.utc(2026, 3, 10),
      expiresAt: null,
      link: null,
    );

/// A repository whose list and read state the test sets directly.
class _FakeRepository extends ServerNotificationRepository {
  _FakeRepository(this.items, {this.read = const {}});

  final List<ServerNotification> items;
  final Set<String> read;

  @override
  List<ServerNotification> get notifications => items;

  @override
  bool isUnread(ServerNotification item) => !read.contains(item.id);

  @override
  bool get lastSyncFailed => false;
}

class _MemoryFilterStore implements NotificationFilterStore {
  NotificationFilter stored = const NotificationFilter();

  @override
  Future<NotificationFilter> load() async => stored;

  @override
  Future<void> save(NotificationFilter filter) async => stored = filter;
}

final _entries = [
  SchoolFeedEntry(_school(1)),
  AppFeedEntry(_app('a', 'info')),
  AppFeedEntry(_app('b', 'update')),
];

List<String> _shown(NotificationFilter filter, {Set<String> read = const {}}) =>
    [
      for (final entry in _entries)
        if (filter.matches(entry,
            isUnread: (item) => !read.contains(item.id),
            availableTypes: const {'info', 'update'}))
          switch (entry) {
            SchoolFeedEntry(:final notification) => 'school ${notification.id}',
            AppFeedEntry(:final notification) => notification.id,
          },
    ];

void main() {
  group('NotificationFilter', () {
    test('shows everything by default', () {
      expect(const NotificationFilter().isActive, isFalse);
      expect(_shown(const NotificationFilter()), ['school 1', 'a', 'b']);
    });

    test('narrows by source', () {
      expect(
        _shown(
            const NotificationFilter(source: NotificationSourceFilter.school)),
        ['school 1'],
      );
      expect(
        _shown(const NotificationFilter(source: NotificationSourceFilter.app)),
        ['a', 'b'],
      );
    });

    test('narrows announcements by type', () {
      expect(
        _shown(const NotificationFilter(
            source: NotificationSourceFilter.app, appType: 'update')),
        ['b'],
      );
    });

    test('combines source, type and unread', () {
      expect(_shown(const NotificationFilter(unreadOnly: true), read: {'a'}),
          ['school 1', 'b']);
      expect(
        _shown(
          const NotificationFilter(
              source: NotificationSourceFilter.app,
              appType: 'info',
              unreadOnly: true),
          read: {'a'},
        ),
        isEmpty,
      );
    });

    test('a type that no longer exists hides nothing', () {
      const filter = NotificationFilter(appType: 'gone');
      expect(
        _entries.where((entry) => filter.matches(entry,
            isUnread: (_) => true, availableTypes: const {'info'})),
        hasLength(3),
      );
    });

    test('survives a round trip, and garbage gives the default', () {
      const filter = NotificationFilter(
          source: NotificationSourceFilter.app,
          appType: 'update',
          unreadOnly: true);
      expect(NotificationFilter.fromJson(filter.toJson()), filter);
      for (final garbage in [
        null,
        'x',
        42,
        {'source': 'nonsense', 'appType': 3, 'unreadOnly': 'yes'},
      ]) {
        expect(
            NotificationFilter.fromJson(garbage), const NotificationFilter());
      }
    });
  });

  group('NotificationFilterStore', () {
    test('remembers the filter on the device', () async {
      SharedPreferences.setMockInitialValues({});
      const store = NotificationFilterStore();
      expect(await store.load(), const NotificationFilter());

      const filter = NotificationFilter(
          source: NotificationSourceFilter.school, unreadOnly: true);
      await store.save(filter);
      expect(await const NotificationFilterStore().load(), filter);

      await store.save(const NotificationFilter());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(notificationFilterPreferenceKey), isFalse);
    });

    test('an unreadable value gives the default', () async {
      SharedPreferences.setMockInitialValues(
          {notificationFilterPreferenceKey: '{not json'});
      expect(await const NotificationFilterStore().load(),
          const NotificationFilter());
    });
  });

  group('center', () {
    setUp(bootstrapTestEnvironment);
    tearDown(resetTestState);

    Future<_MemoryFilterStore> pump(
      WidgetTester tester, {
      NotificationFilter stored = const NotificationFilter(),
      Set<String> read = const {},
      List<Notification>? school,
      List<ServerNotification>? apps,
      String language = 'de',
    }) async {
      final store = _MemoryFilterStore()..stored = stored;
      final schoolItems = school ?? [_school(1)];
      await pumpApp(
        tester,
        store: createStore(
          initialState: AppState((b) => b
            ..notificationState.notifications =
                ListBuilder<Notification>(schoolItems)
            ..settingsState.languageCode = language),
        ),
        home: ServerNotificationCenterPage(
          repository: _FakeRepository(
            apps ?? [_app('a', 'info'), _app('b', 'update')],
            read: read,
          ),
          onRefresh: () {},
          filterStore: store,
          school: SchoolNotificationFeed(
            notifications: schoolItems,
            noInternet: false,
            onMarkRead: (_) {},
            onMarkAllRead: () {},
            onOpenMessage: (_) {},
          ),
        ),
      );
      await settleFor(tester);
      return store;
    }

    testWidgets('filters by source and remembers it', (tester) async {
      final store = await pump(tester);
      expect(find.text('school 1'), findsOneWidget);
      expect(find.text('app a'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byKey(const Key('notification-filter-source')),
        matching: find.text('Schule'),
      ));
      await settleFor(tester);

      expect(find.text('school 1'), findsOneWidget);
      expect(find.text('app a'), findsNothing);
      expect(store.stored.source, NotificationSourceFilter.school);
    });

    testWidgets('restores a remembered filter and narrows by type',
        (tester) async {
      await pump(tester,
          stored:
              const NotificationFilter(source: NotificationSourceFilter.app));
      expect(find.text('school 1'), findsNothing);
      expect(find.text('app a'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Update'));
      await settleFor(tester);
      expect(find.text('app a'), findsNothing);
      expect(find.text('app b'), findsOneWidget);
    });

    testWidgets('names well-known types in the app language (#120)',
        (tester) async {
      await pump(
        tester,
        language: 'it',
        apps: [_app('a', 'info'), _app('b', 'update'), _app('c', 'event')],
        // Type chips appear with the app source only.
        stored: const NotificationFilter(source: NotificationSourceFilter.app),
      );
      // Filter chips: the app's names for known keys, the server's otherwise.
      for (final label in ['Informazione', 'Aggiornamento', 'Veranstaltung']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget,
            reason: label);
      }
      expect(find.widgetWithText(ChoiceChip, 'Info'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Update'), findsNothing);
      // The rows say the same.
      expect(find.text('App · Informazione'), findsOneWidget);
      expect(find.text('App · Aggiornamento'), findsOneWidget);
      expect(find.text('App · Veranstaltung'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Aggiornamento'));
      await settleFor(tester);
      expect(find.text('app a'), findsNothing);
      expect(find.text('app b'), findsOneWidget);
    });

    testWidgets('shows an empty state that clears the filter', (tester) async {
      final store = await pump(
        tester,
        read: {'a', 'b'},
        school: const [],
        stored: const NotificationFilter(unreadOnly: true),
      );
      expect(find.text('Nichts gefunden'), findsOneWidget);

      await tester
          .tap(find.widgetWithText(OutlinedButton, 'Filter zurücksetzen'));
      await settleFor(tester);

      expect(find.text('app a'), findsOneWidget);
      expect(store.stored, const NotificationFilter());
    });

    testWidgets('the badge ignores the filter', (tester) async {
      SharedPreferences.setMockInitialValues({
        notificationFilterPreferenceKey:
            '{"source":"app","appType":null,"unreadOnly":true}',
      });
      await pumpApp(
        tester,
        store: createStore(
          initialState: AppState((b) => b.notificationState.notifications =
              ListBuilder<Notification>([_school(1), _school(2)])),
        ),
        home: const Material(child: NotificationIconContainer()),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 200));
      expect(
        find.descendant(
          of: find.byKey(const Key('server-notification-bell')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });
  });
}
