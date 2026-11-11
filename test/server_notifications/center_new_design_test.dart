import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show nestedNavKey;
import 'package:dr/notification_feed.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';
import 'support.dart';

const _a = '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731';
const _b = '5f0e2c1a-7f4d-4b52-9d43-2a6c0f3e1b10';

const _phone = Size(412, 900);
const _wide = Size(1280, 800);

final _header = find.byKey(const Key('notification-center-header'));
final _detailHeader = find.byKey(const Key('notification-detail-header'));
final _pane = find.byKey(const Key('notification-center-detail-pane'));

/// Finishes [future] inside the test's fake time. `sync` must not run inside
/// `runAsync`, where it never finishes.
Future<void> _drive(WidgetTester tester, Future<Object?> future) async {
  var done = false;
  unawaited(future.whenComplete(() => done = true).catchError((Object _) {
    return null;
  }));
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: 'future never finished');
}

Future<ServerNotificationRepository> _repository(
  WidgetTester tester,
  List<Map<String, dynamic>> items, {
  bool failAfterwards = false,
}) async {
  final server = FakeServer()..replyList(items);
  if (failAfterwards) server.reply(jsonResponse({}, status: 500));
  final repository = repositoryFor(server, FakeStorage.existingInstall());
  await _drive(tester, repository.sync(selection));
  if (failAfterwards) await _drive(tester, repository.sync(selection));
  return repository;
}

/// Two announcements, one of them read later in a test, and two entries of
/// the school.
List<Map<String, dynamic>> get _appItems => [
      // The default id is _a.
      item(
        title: 'Wartung am Samstag',
        body: 'Am Samstag ist die App von 8 bis 10 Uhr nicht erreichbar.',
        typeKey: 'critical',
        typeLabel: 'Critical',
        critical: true,
        icon: 'warning',
        color: '#B3261E',
        publishedAt: '2026-10-22T18:00:00Z',
      ),
      item(
        id: _b,
        title: 'Neue Version',
        body: 'Die neue Version bringt das Design der Startseite.',
        typeKey: 'update',
        typeLabel: 'Update',
        icon: 'update',
        publishedAt: '2026-10-20T08:00:00Z',
      ),
    ];

final List<Notification> _schoolItems = [
  // The default id is 1.
  buildNotification(
    title: 'Elternsprechtag',
    subTitle: 'Die Anmeldung ist im Sekretariat möglich.',
    timeSent: UtcDateTime(2026, 10, 21, 9),
  ),
  buildNotification(
    id: 2,
    title: 'Neue Mitteilung',
    type: 'message',
    objectId: 7,
    timeSent: UtcDateTime(2026, 10, 19, 9),
  ),
];

class _School {
  final List<int> read = <int>[];
  final List<int> messages = <int>[];
  int allRead = 0;

  SchoolNotificationFeed feed(
    List<Notification> notifications, {
    bool noInternet = false,
  }) =>
      SchoolNotificationFeed(
        notifications: notifications,
        noInternet: noInternet,
        onMarkRead: (item) => read.add(item.id),
        onMarkAllRead: () => allRead++,
        onOpenMessage: messages.add,
        lastFetched: UtcDateTime(2026, 10, 22, 7),
      );
}

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

/// Opens the center as the bell does: on top of the page in the shell.
Future<void> _pumpCenter(
  WidgetTester tester,
  ServerNotificationRepository repository, {
  SchoolNotificationFeed? school,
  bool newDesign = true,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  String languageCode = 'de',
  String? initialId,
  int? initialSchoolId,
  VoidCallback? onRefresh,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(languageCode: languageCode),
    newDesign: newDesign,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
  );
  await settleFor(tester);
  unawaited(nestedNavKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => ServerNotificationCenterPage(
      repository: repository,
      school: school,
      initialId: initialId,
      initialSchoolId: initialSchoolId,
      onRefresh: onRefresh ?? () {},
      openLink: (_) async => ServerNotificationLinkResult.opened,
    ),
  )));
  await settleFor(tester, duration: const Duration(milliseconds: 600));
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 600));

Finder _app(String id) => find.byKey(ValueKey('app-$id'));
Finder _schoolEntry(int id) => find.byKey(ValueKey('school-$id'));

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the shell of the new design shows the glass page',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository, school: _School().feed([]));

      expect(_header, findsOneWidget);
      expect(find.byType(GlassPageHeader), findsWidgets);
      expect(find.byType(AppBar), findsNothing);
      expect(
          find.byType(SegmentedButton<NotificationSourceFilter>), findsNothing);
      expect(find.byType(GlassSegmentedControl<NotificationSourceFilter>),
          findsOneWidget);
      // The center lies on top of a page, so it has a way back.
      expect(
        find.descendant(of: _header, matching: find.byType(BackButton)),
        findsOneWidget,
      );
    });

    testWidgets('the legacy design keeps the old page', (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(
        tester,
        repository,
        school: _School().feed([]),
        newDesign: false,
      );

      expect(_header, findsNothing);
      expect(find.byType(GlassPageHeader), findsNothing);
      expect(find.byType(SegmentedButton<NotificationSourceFilter>),
          findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
    });

    testWidgets('signed out, outside the shell, it keeps the old page',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      // The corner bell of the sign-in opens it on the root navigator.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        theme: ThemeData(colorScheme: AppPalette.light),
        home: ServerNotificationCenterPage(
          repository: repository,
          onRefresh: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(_header, findsNothing);
      expect(find.text('Wartung am Samstag'), findsOneWidget);
    });
  });

  group('content', () {
    testWidgets('entries of both sources on glass cards, newest first',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository,
          school: _School().feed(_schoolItems));

      final order = [
        _app(_a),
        _schoolEntry(1),
        _app(_b),
        _schoolEntry(2),
      ];
      double? previous;
      for (final entry in order) {
        expect(
          find.descendant(of: entry, matching: find.byType(GlassCard)),
          findsOneWidget,
        );
        final top = tester.getRect(entry).top;
        if (previous != null) expect(top, greaterThan(previous));
        previous = top;
      }
      // The label line, with the type in the app's language (#120).
      expect(find.text('App · Kritisch'), findsOneWidget);
      expect(find.text('App · Update'), findsOneWidget);
      expect(find.text('Schule'), findsWidgets);
      expect(find.byType(ServerNotificationTypeIcon), findsNWidgets(2));
      expect(find.byType(SchoolNotificationIcon), findsNWidgets(2));
      // Every school entry is unread, and both announcements are.
      expect(find.byKey(const Key('server-notification-unread-dot')),
          findsNWidgets(4));
      expect(find.byTooltip('Auf diesem Gerät ausblenden'), findsNWidgets(2));
      expect(find.byTooltip('Gelesen'), findsOneWidget);
      expect(find.byTooltip('Zu Mitteilungen wechseln'), findsOneWidget);
      // Two lines of the text at most.
      final body = tester.widget<Text>(find
          .text('Am Samstag ist die App von 8 bis 10 Uhr nicht erreichbar.'));
      expect(body.maxLines, 2);
    });

    testWidgets('a tile is one button with the hand', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository);

      final ink = find.descendant(of: _app(_a), matching: find.byType(InkWell));
      expect(tester.widget<InkWell>(ink.first).mouseCursor,
          NewDesignTheme.clickCursor);
      final node = tester.getSemantics(ink.first);
      expect(node.label, contains('Ungelesen'));
      expect(node.label, contains('Wartung am Samstag'));
      expect(node.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('the list builds only what is in view', (tester) async {
      final repository = await _repository(tester, [
        for (var i = 0; i < 40; i++)
          item(
            id: '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            title: 'Mitteilung $i',
            publishedAt:
                '2026-10-${(22 - i ~/ 2).toString().padLeft(2, '0')}T08:00:00Z',
          ),
      ]);
      await _pumpCenter(tester, repository);

      expect(find.text('Mitteilung 0'), findsOneWidget);
      expect(find.text('Mitteilung 39'), findsNothing);
    });

    testWidgets('refresh is a disc in the header', (tester) async {
      var refreshed = 0;
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository, onRefresh: () => refreshed++);

      final refresh = find.descendant(
        of: _header,
        matching: find.byTooltip('Aktualisieren'),
      );
      expect(refresh, findsOneWidget);
      await tester.tap(refresh);
      expect(refreshed, 1);
    });

    testWidgets('marking all read covers both sources', (tester) async {
      final school = _School();
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository, school: school.feed(_schoolItems));

      await tester.tap(find.text('Alle gelesen'));
      await _settle(tester);
      expect(school.allRead, 1);
      expect(repository.unreadCount, 0);
    });
  });

  group('filter', () {
    testWidgets('the source, unread and type filters narrow the list',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository,
          school: _School().feed(_schoolItems));

      await tester.tap(find
          .byKey(ValueKey('glass-segment-${NotificationSourceFilter.school}')));
      await _settle(tester);
      expect(_schoolEntry(1), findsOneWidget);
      expect(_app(_a), findsNothing);

      await tester.tap(find
          .byKey(ValueKey('glass-segment-${NotificationSourceFilter.app}')));
      await _settle(tester);
      expect(_schoolEntry(1), findsNothing);
      expect(_app(_a), findsOneWidget);
      expect(_app(_b), findsOneWidget);

      // The type chips, only for announcements.
      final update =
          find.byKey(const ValueKey('notification-filter-type-update'));
      expect(update, findsOneWidget);
      expect(tester.widget<ChoiceChip>(update).mouseCursor,
          NewDesignTheme.clickCursor);
      await tester.tap(update);
      await _settle(tester);
      expect(_app(_a), findsNothing);
      expect(_app(_b), findsOneWidget);

      final unread = find.byKey(const Key('notification-filter-unread'));
      expect(tester.widget<FilterChip>(unread).mouseCursor,
          NewDesignTheme.clickCursor);

      await tester.tap(find.byKey(const Key('notification-filter-reset')));
      await _settle(tester);
      expect(_schoolEntry(1), findsOneWidget);
      expect(_app(_a), findsOneWidget);
    });

    testWidgets('nothing matching shows a state card that resets',
        (tester) async {
      await repositoryReadAll(tester);
    });
  });

  group('detail', () {
    testWidgets('on phones, an entry opens a glass page with a way back',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository);

      await tester.tap(find.text('Wartung am Samstag'));
      await _settle(tester);
      expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
      expect(_detailHeader, findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('notification-detail')), findsOneWidget);
      expect(repository.isUnread(repository.byId(_a)!), isFalse);

      await tester.tap(find.descendant(
          of: _detailHeader, matching: find.byType(BackButton)));
      await _settle(tester);
      expect(find.byType(ServerNotificationDetailPage), findsNothing);
      expect(_header, findsOneWidget);
    });

    testWidgets('a school entry opens its text, a message entry the message',
        (tester) async {
      final school = _School();
      final repository = await _repository(tester, []);
      await _pumpCenter(tester, repository, school: school.feed(_schoolItems));

      await tester.tap(find.text('Neue Mitteilung'));
      await _settle(tester);
      expect(school.messages, [7]);

      await tester.tap(find.text('Elternsprechtag'));
      await _settle(tester);
      expect(find.byType(SchoolNotificationDetailPage), findsOneWidget);
      expect(_detailHeader, findsOneWidget);
      expect(find.text('Die Anmeldung ist im Sekretariat möglich.'),
          findsOneWidget);
      expect(school.read, [1]);
    });

    testWidgets('wide windows show list and detail side by side',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository, size: _wide);

      expect(find.descendant(of: _pane, matching: find.byType(GlassStateCard)),
          findsOneWidget);
      expect(find.text('Wähle eine Mitteilung aus.'), findsOneWidget);
      await tester.tap(find.text('Neue Version'));
      await _settle(tester);
      expect(find.byType(ServerNotificationDetailPage), findsNothing);
      expect(
        find.descendant(
            of: _pane, matching: find.byKey(const Key('notification-detail'))),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _app(_b),
          matching: find.byKey(const Key('server-notification-selected')),
        ),
        findsOneWidget,
      );
      // List and detail start below the floating header.
      final headerBottom = tester.getRect(_header).bottom;
      expect(tester.getRect(_app(_a)).top, greaterThan(headerBottom));
      expect(
        tester.getRect(find.byKey(const Key('notification-detail'))).top,
        greaterThan(headerBottom),
      );
    });

    testWidgets('a deep link opens the notification on phones', (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository, initialId: _b);

      expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
      expect(_detailHeader, findsOneWidget);
      expect(find.text('Die neue Version bringt das Design der Startseite.'),
          findsOneWidget);
    });

    testWidgets('a deep link selects the notification on wide windows',
        (tester) async {
      final school = _School();
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(
        tester,
        repository,
        school: school.feed(_schoolItems),
        size: _wide,
        initialSchoolId: 1,
      );

      expect(find.byType(SchoolNotificationDetailPage), findsNothing);
      expect(
        find.descendant(
            of: _pane, matching: find.byType(SchoolNotificationDetailView)),
        findsOneWidget,
      );
      expect(school.read, [1]);
    });
  });

  group('dismissal', () {
    testWidgets('asks in a glass sheet; cancel keeps, confirm hides',
        (tester) async {
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository);

      await tester.tap(find.descendant(
          of: _app(_a),
          matching: find.byTooltip('Auf diesem Gerät ausblenden')));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.text('Mitteilung ausblenden?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notification-dismiss-cancel')));
      await _settle(tester);
      expect(_app(_a), findsOneWidget);

      await tester.tap(find.descendant(
          of: _app(_a),
          matching: find.byTooltip('Auf diesem Gerät ausblenden')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('notification-dismiss-confirm')));
      await _settle(tester);
      expect(_app(_a), findsNothing);
      expect(repository.byId(_a), isNull);
    });
  });

  group('states', () {
    testWidgets('no announcements is a state card', (tester) async {
      final repository = await _repository(tester, []);
      await _pumpCenter(tester, repository);

      expect(
          find.byKey(const Key('notification-center-empty')), findsOneWidget);
      expect(find.byType(GlassStateCard), findsOneWidget);
      expect(find.text('Keine App-Mitteilungen'), findsOneWidget);
    });

    testWidgets('no entries of both sources is a state card', (tester) async {
      final repository = await _repository(tester, []);
      await _pumpCenter(tester, repository, school: _School().feed([]));

      expect(
          find.byKey(const Key('notification-center-empty')), findsOneWidget);
      expect(find.text('Keine Benachrichtigungen'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the list and says so', (tester) async {
      var refreshed = 0;
      final repository =
          await _repository(tester, _appItems, failAfterwards: true);
      await _pumpCenter(tester, repository, onRefresh: () => refreshed++);

      expect(
          find.byKey(const Key('notification-center-stale')), findsOneWidget);
      expect(
          find.textContaining('Aktualisierung nicht möglich'), findsOneWidget);
      expect(_app(_a), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byKey(const Key('notification-center-stale')),
        matching: find.byType(IconButton),
      ));
      expect(refreshed, 1);
    });

    testWidgets('a failed refresh without entries is a state card',
        (tester) async {
      final repository = await _repository(tester, [], failAfterwards: true);
      await _pumpCenter(tester, repository);

      expect(find.byType(GlassStateCard), findsOneWidget);
      expect(
          find.textContaining('Aktualisierung nicht möglich'), findsOneWidget);
    });

    testWidgets('offline, the school entries say how old they are',
        (tester) async {
      final repository = await _repository(tester, []);
      await _pumpCenter(
        tester,
        repository,
        school: _School().feed(_schoolItems, noInternet: true),
      );

      expect(
          find.byKey(const Key('notification-center-offline')), findsOneWidget);
      // Marking read needs the school.
      final markRead = tester.widget<IconButton>(find.descendant(
          of: _schoolEntry(1), matching: find.byType(IconButton)));
      expect(markRead.onPressed, isNull);
    });
  });

  group('look', () {
    testWidgets('blur only in the header, light and dark, phone and wide',
        (tester) async {
      for (final size in [_phone, _wide]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          final repository = await _repository(tester, _appItems);
          await _pumpCenter(
            tester,
            repository,
            school: _School().feed(_schoolItems),
            size: size,
            themeMode: mode,
          );
          // The navigation has its own; the page has only the header's.
          final page = find.byType(ServerNotificationCenterPage);
          expect(
            find.descendant(of: page, matching: find.byType(BackdropFilter)),
            findsWidgets,
          );
          for (final element in find
              .descendant(of: page, matching: find.byType(BackdropFilter))
              .evaluate()) {
            expect(
              find
                  .ancestor(
                    of: find.byWidget(element.widget),
                    matching: find.byType(GlassPageHeader),
                  )
                  .evaluate()
                  .isNotEmpty,
              isTrue,
              reason: 'blur outside the header at $size $mode',
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('high contrast and reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
        highContrast: true,
        disableAnimations: true,
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final repository = await _repository(tester, _appItems);
      await _pumpCenter(tester, repository,
          school: _School().feed(_schoolItems));

      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text at 200 % on a 320 px phone does not overflow',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = await _repository(tester, [
        item(title: 'Lang ' * 20, body: 'Text ' * 100),
        ..._appItems.skip(1),
      ]);
      await _pumpCenter(
        tester,
        repository,
        school: _School().feed(_schoolItems),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(_app(_a));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    for (final (code, title) in [
      ('it', 'notifications.title'),
      ('en', 'notifications.title'),
      ('lld', 'notifications.title'),
    ]) {
      testWidgets('speaks $code', (tester) async {
        final repository = await _repository(tester, _appItems);
        await _pumpCenter(
          tester,
          repository,
          school: _School().feed(_schoolItems),
          languageCode: code,
        );
        final l10n = tester.element(_header).l10n;
        expect(find.text(l10n.text(title)), findsOneWidget);
        expect(find.text(l10n.text('notifications.filter.all')), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Every entry read, then only unread ones: nothing left to show.
Future<void> repositoryReadAll(WidgetTester tester) async {
  final repository = await _repository(tester, _appItems);
  await _drive(tester, repository.markRead(_a));
  await _drive(tester, repository.markRead(_b));
  await _pumpCenter(tester, repository, school: _School().feed([]));

  await tester.tap(find.byKey(const Key('notification-filter-unread')));
  await _settle(tester);
  final empty = find.byKey(const Key('notification-center-filter-empty'));
  expect(empty, findsOneWidget);
  expect(find.text('Nichts gefunden'), findsOneWidget);
  await tester.tap(
      find.descendant(of: empty, matching: find.text('Filter zurücksetzen')));
  await _settle(tester);
  expect(empty, findsNothing);
  expect(_app(_a), findsOneWidget);
}
