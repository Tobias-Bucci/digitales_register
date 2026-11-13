import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/dashboard_app_header.dart' show GlassHeaderShell;
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/server_notifications/server_notification_bell.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/ui/server_notifications/server_notification_popup.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const a = '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731';
const b = '5f0e2c1a-7f4d-4b52-9d43-2a6c0f3e1b10';
const c = '2c9a7e44-1d6b-4c3f-8a55-73e1b9d0c2f4';

final popup = find.byKey(const Key('server-notification-popup'));

final popupClose = find.byKey(const Key('server-notification-popup-close'));
final popupOpen = find.byKey(const Key('server-notification-popup-open'));

Widget app({
  required Widget home,
  ThemeMode mode = ThemeMode.light,
  Locale locale = const Locale('de'),
  GlobalKey<NavigatorState>? navigator,
  TransitionBuilder? builder,
}) =>
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      themeMode: mode,
      theme: ThemeData(colorScheme: AppPalette.light),
      darkTheme: ThemeData(colorScheme: AppPalette.dark),
      navigatorKey: navigator,
      builder: builder,
      home: home,
    );

Future<ServerNotificationRepository> filled(
  WidgetTester tester,
  List<Map<String, dynamic>> items,
) async {
  final server = FakeServer()..replyList(items);
  return synced(tester, server);
}

/// Finishes [future] inside the test's fake time, where everything here runs.
Future<void> drive(WidgetTester tester, Future<Object?> future) async {
  var done = false;
  unawaited(future.whenComplete(() => done = true).catchError((Object _) {
    return null;
  }));
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: 'future never finished');
}

Future<ServerNotificationRepository> synced(
  WidgetTester tester,
  FakeServer server, {
  int syncs = 1,
}) async {
  final repository = repositoryFor(server, FakeStorage.existingInstall());
  for (var i = 0; i < syncs; i++) {
    await drive(tester, repository.sync(selection));
  }
  return repository;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  group('bell', () {
    Future<void> pumpBell(
      WidgetTester tester,
      ServerNotificationRepository repository, {
      bool hideWhenEmpty = false,
      bool enabled = true,
    }) async {
      await tester.pumpWidget(app(
        home: Scaffold(
          appBar: AppBar(actions: [
            ServerNotificationBell(
              repository: repository,
              enabled: enabled,
              hideWhenEmpty: hideWhenEmpty,
              onPressed: () {},
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the unread count, for eyes and screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await filled(tester, [item(), item(id: b)]);
      await pumpBell(tester, repository);
      expect(find.text('2'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(IconButton)),
        containsSemantics(tooltip: 'App-Mitteilungen, 2 ungelesen'),
      );
      semantics.dispose();
    });

    testWidgets('no badge without unread notifications', (tester) async {
      final repository = await filled(tester, []);
      await pumpBell(tester, repository);
      expect(find.byKey(const Key('server-notification-bell')), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    });

    testWidgets('large counts are capped', (tester) async {
      final repository = await filled(tester, [
        for (var i = 0; i < 120; i++)
          item(id: '00000000-0000-4000-8000-${'$i'.padLeft(12, '0')}'),
      ]);
      await pumpBell(tester, repository);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('the count follows the read state', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpBell(tester, repository);
      expect(find.text('1'), findsOneWidget);
      await drive(tester, repository.markRead(a));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsNothing);
    });

    testWidgets('a build without the feature shows nothing', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpBell(tester, repository, enabled: false);
      expect(find.byKey(const Key('server-notification-bell')), findsNothing);
    });

    testWidgets('can stay out of the way while empty', (tester) async {
      final repository = await filled(tester, []);
      await pumpBell(tester, repository, hideWhenEmpty: true);
      expect(find.byKey(const Key('server-notification-bell')), findsNothing);
    });

    testWidgets('is keyboard reachable and opens with Enter', (tester) async {
      final repository = await filled(tester, []);
      var pressed = 0;
      await tester.pumpWidget(app(
        home: Scaffold(
          body: ServerNotificationBell(
            repository: repository,
            enabled: true,
            onPressed: () => pressed++,
          ),
        ),
      ));
      await tester.pump();
      FocusManager.instance.primaryFocus?.nextFocus();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 1);
    });
  });

  group('center', () {
    Future<void> pumpCenter(
      WidgetTester tester,
      ServerNotificationRepository repository, {
      ThemeMode mode = ThemeMode.light,
      ServerNotificationLinkOpener? openLink,
      VoidCallback? onRefresh,
      Size size = const Size(400, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        mode: mode,
        home: ServerNotificationCenterPage(
          repository: repository,
          onRefresh: onRefresh ?? () {},
          openLink:
              openLink ?? (_) async => ServerNotificationLinkResult.opened,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists newest first with type and unread mark', (tester) async {
      final repository = await filled(tester, [
        item(id: b, title: 'Älter', publishedAt: '2026-10-01T07:00:00Z'),
        item(title: 'Neuer'),
      ]);
      await pumpCenter(tester, repository);
      final first = tester.getTopLeft(find.text('Neuer')).dy;
      final second = tester.getTopLeft(find.text('Älter')).dy;
      expect(first, lessThan(second));
      expect(find.text('Information'), findsNWidgets(2));
      expect(find.byKey(const Key('server-notification-unread-dot')),
          findsNWidgets(2));
    });

    testWidgets('shows the empty state', (tester) async {
      final repository = await filled(tester, []);
      await pumpCenter(tester, repository);
      expect(find.text('Keine App-Mitteilungen'), findsOneWidget);
    });

    testWidgets('renders markup as plain text', (tester) async {
      final repository =
          await filled(tester, [item(title: '<b>Fett</b>', body: '<i>x</i>')]);
      await pumpCenter(tester, repository);
      expect(find.text('<b>Fett</b>'), findsOneWidget);
    });

    testWidgets('a failed sync is a note, not an error page', (tester) async {
      final server = FakeServer()
        ..replyList([item()])
        ..reply(jsonResponse({}, status: 500));
      final repository = await synced(tester, server, syncs: 2);
      await pumpCenter(tester, repository);
      expect(
          find.textContaining('Aktualisierung nicht möglich'), findsOneWidget);
      expect(find.text('Titel'), findsOneWidget);
    });

    testWidgets('the refresh button is available without a touch gesture',
        (tester) async {
      var refreshed = 0;
      final repository = await filled(tester, []);
      await pumpCenter(tester, repository, onRefresh: () => refreshed++);
      await tester.tap(find.byTooltip('Aktualisieren'));
      expect(refreshed, 1);
    });

    testWidgets('opening a notification reads it', (tester) async {
      final repository = await filled(tester, [item(body: 'Der ganze Text')]);
      await pumpCenter(tester, repository);
      expect(repository.unreadCount, 1);
      await tester.tap(find.text('Titel'));
      await settle(tester);
      expect(find.text('Der ganze Text'), findsOneWidget);
      expect(repository.unreadCount, 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('server-notification-unread-dot')),
          findsNothing);
      expect(find.text('Titel'), findsOneWidget, reason: 'read items stay');
    });

    testWidgets('dismissal asks first, and cancel keeps it', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpCenter(tester, repository);
      await tester.tap(find.byTooltip('Auf diesem Gerät ausblenden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.text('Titel'), findsOneWidget);

      await tester.tap(find.byTooltip('Auf diesem Gerät ausblenden'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ausblenden'));
      await settle(tester);
      expect(find.text('Titel'), findsNothing);
      expect(repository.notifications, isEmpty);
    });

    testWidgets('wide windows show list and detail side by side',
        (tester) async {
      final repository = await filled(tester, [item(body: 'Der ganze Text')]);
      await pumpCenter(tester, repository, size: const Size(1200, 800));
      expect(find.text('Wähle eine Mitteilung aus.'), findsOneWidget);
      await tester.tap(find.text('Titel'));
      await settle(tester);
      expect(find.byType(ServerNotificationCenterPage), findsOneWidget);
      expect(find.byType(ServerNotificationDetailPage), findsNothing);
      expect(find.text('Der ganze Text'), findsWidgets);
      expect(repository.unreadCount, 0);
    });

    testWidgets('has no overflow on a small phone with large text',
        (tester) async {
      final repository = await filled(tester, [
        item(title: 'Lang ' * 20, body: 'Text ' * 100),
      ]);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2),
          ),
          child: ServerNotificationCenterPage(
            repository: repository,
            onRefresh: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiles describe themselves to screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await filled(tester, [item()]);
      await pumpCenter(tester, repository);
      expect(
        find.bySemanticsLabel(RegExp(r'^Ungelesen, Information, Titel, ')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('tap targets and contrast meet the guidelines ($mode)',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = await filled(tester, [item(color: '#E9A23B')]);
        await pumpCenter(tester, repository, mode: mode);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  });

  group('detail', () {
    Future<void> pumpDetail(
      WidgetTester tester,
      ServerNotificationRepository repository, {
      String id = a,
      ServerNotificationLinkOpener? openLink,
    }) async {
      await tester.pumpWidget(app(
        home: ServerNotificationDetailPage(
          id: id,
          repository: repository,
          openLink:
              openLink ?? (_) async => ServerNotificationLinkResult.opened,
        ),
      ));
      await settle(tester);
    }

    testWidgets('shows everything the issue asks for', (tester) async {
      final repository = await filled(tester, [
        item(
          title: 'Wartung',
          body: 'Zeile 1\nZeile 2',
          expiresAt: '2026-12-01T10:00:00Z',
        ),
      ]);
      await pumpDetail(tester, repository);
      expect(find.text('Wartung'), findsOneWidget);
      expect(find.text('Zeile 1\nZeile 2'), findsOneWidget);
      expect(find.text('Information'), findsOneWidget);
      expect(find.textContaining('Veröffentlicht:'), findsOneWidget);
      expect(find.textContaining('Gültig bis:'), findsOneWidget);
      expect(repository.unreadCount, 0);
      await tester.pumpWidget(const SizedBox());
      repository.dispose();
    });

    testWidgets('shows where an external link leads and opens it validated',
        (tester) async {
      ServerNotificationLink? opened;
      final repository = await filled(tester, [
        item(link: {'kind': 'external', 'target': 'https://example.com/a'}),
      ]);
      await pumpDetail(tester, repository, openLink: (link) async {
        opened = link;
        return ServerNotificationLinkResult.opened;
      });
      await tester.tap(find.text('example.com öffnen'));
      await tester.pumpAndSettle();
      expect((opened! as ExternalNotificationLink).uri.scheme, 'https');
    });

    testWidgets('an invalid link shows no button', (tester) async {
      final repository = await filled(tester, [
        item(link: {'kind': 'external', 'target': 'http://example.com'}),
      ]);
      await pumpDetail(tester, repository);
      expect(find.textContaining('öffnen'), findsNothing);
    });

    testWidgets('an unknown route shows no button', (tester) async {
      final repository = await filled(tester, [
        item(link: {'kind': 'internal', 'target': 'admin'}),
      ]);
      await pumpDetail(tester, repository);
      expect(find.text('In der App öffnen'), findsNothing);
    });

    testWidgets('explains an internal link while signed out', (tester) async {
      final repository = await filled(tester, [
        item(link: {'kind': 'internal', 'target': 'grades'}),
      ]);
      await pumpDetail(tester, repository,
          openLink: (_) async => ServerNotificationLinkResult.needsLogin);
      await tester.tap(find.text('In der App öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Dieser Link ist nach der Anmeldung verfügbar.'),
          findsOneWidget);
    });

    testWidgets('a failed link says so', (tester) async {
      final repository = await filled(tester, [
        item(link: {'kind': 'external', 'target': 'https://example.com/'}),
      ]);
      await pumpDetail(tester, repository,
          openLink: (_) async => ServerNotificationLinkResult.failed);
      await tester.tap(find.text('example.com öffnen'));
      await tester.pumpAndSettle();
      expect(
          find.text('Der Link konnte nicht geöffnet werden.'), findsOneWidget);
    });

    testWidgets('a revoked notification turns into a notice', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpDetail(tester, repository, id: b);
      expect(find.text('Diese Mitteilung ist nicht mehr verfügbar.'),
          findsOneWidget);
    });

    testWidgets('the title is a heading for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await filled(tester, [item(title: 'Wartung')]);
      await pumpDetail(tester, repository);
      expect(
        tester.getSemantics(find.text('Wartung')),
        containsSemantics(isHeader: true),
      );
      semantics.dispose();
    });
  });

  group('popup', () {
    late GlobalKey<NavigatorState> navigator;

    Future<void> pumpHost(
      WidgetTester tester,
      ServerNotificationRepository repository, {
      bool Function()? isBlocked,
      Listenable? blockedChanges,
      ThemeMode mode = ThemeMode.light,
      bool newDesign = false,
      bool Function({String? initialId})? openInShell,
    }) async {
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(
        mode: mode,
        navigator: navigator,
        home: const Scaffold(body: Text('App')),
        builder: (context, child) => ServerNotificationHost(
          newDesign: newDesign,
          openInShell: openInShell ?? ({String? initialId}) => false,
          repository: repository,
          navigator: () => navigator.currentState,
          isBlocked: isBlocked ?? () => false,
          blockedChanges: blockedChanges ?? ChangeNotifier(),
          onLanguage: (_) {},
          child: child!,
        ),
      ));
      await tester.pump();
      // The first frame only starts the fade-in, at opacity zero.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a regular popup closes itself after about six seconds',
        (tester) async {
      final repository = await filled(tester, [item(title: 'Neu')]);
      await pumpHost(tester, repository);
      expect(popup, findsOneWidget);
      expect(find.text('Neu'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(popup, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(repository.unreadCount, 1, reason: 'closing does not read');
      expect(repository.notifications, hasLength(1));
      expect(repository.pendingAlerts, isEmpty);
    });

    testWidgets('a critical popup stays until closed by hand', (tester) async {
      final repository = await filled(tester, [
        item(title: 'Störung', critical: true),
      ]);
      await pumpHost(tester, repository);
      expect(find.text('Wichtige App-Mitteilung'), findsOneWidget);
      await tester.pump(const Duration(minutes: 5));
      expect(popup, findsOneWidget);
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      expect(repository.unreadCount, 1);
    });

    testWidgets('the fixture of a critical type needs a manual close',
        (tester) async {
      final server = FakeServer()
        ..reply(jsonResponse(fixture('list-critical')));
      final repository = await synced(tester, server);
      await pumpHost(tester, repository);
      await tester.pump(const Duration(seconds: 30));
      expect(popup, findsOneWidget);
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
    });

    testWidgets('it blocks nothing: the app below stays usable',
        (tester) async {
      var taps = 0;
      final repository = await filled(tester, [item(critical: true)]);
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(
        navigator: navigator,
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Darunter'),
            ),
          ),
        ),
        builder: (context, child) => ServerNotificationHost(
          repository: repository,
          navigator: () => navigator.currentState,
          isBlocked: () => false,
          blockedChanges: ChangeNotifier(),
          onLanguage: (_) {},
          child: child!,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Darunter'));
      expect(taps, 1);
    });

    testWidgets('several new messages make one summary popup', (tester) async {
      final repository = await filled(tester, [
        item(title: 'Eins'),
        item(id: b, title: 'Zwei'),
        item(id: c, title: 'Drei'),
      ]);
      await pumpHost(tester, repository);
      expect(popup, findsOneWidget);
      expect(find.text('3 neue App-Mitteilungen'), findsOneWidget);
      expect(find.text('Eins'), findsNothing);
      await tester.tap(popupOpen);
      await tester.pumpAndSettle();
      expect(find.byType(ServerNotificationCenterPage), findsOneWidget);
      expect(repository.unreadCount, 3, reason: 'each one still to be read');
    });

    testWidgets('one critical among several makes the summary manual',
        (tester) async {
      final repository = await filled(tester, [
        item(title: 'Eins'),
        item(id: b, title: 'Zwei', critical: true),
      ]);
      await pumpHost(tester, repository);
      await tester.pump(const Duration(seconds: 30));
      expect(popup, findsOneWidget);
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
    });

    testWidgets('a later arrival joins the open popup', (tester) async {
      final server = FakeServer()
        ..replyList([item(title: 'Eins')], etag: 'W/"1"')
        ..replyList([item(title: 'Eins'), item(id: b, title: 'Zwei')],
            etag: 'W/"2"');
      final repository = await synced(tester, server);
      await pumpHost(tester, repository);
      await drive(tester, repository.sync(selection));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(popup, findsOneWidget);
      expect(find.text('2 neue App-Mitteilungen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    });

    testWidgets('nothing is announced twice', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpHost(tester, repository);
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
      // Any later change, such as a poll, must not bring it back.
      await drive(tester, repository.markAlerted(const []));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    });

    testWidgets('opening a single popup leads to its detail, which reads it',
        (tester) async {
      final repository = await filled(tester, [item(body: 'Der ganze Text')]);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHost(tester, repository);
      await tester.tap(popupOpen);
      await settle(tester);
      expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
      expect(repository.unreadCount, 0);
    });

    group('open in the new design', () {
      testWidgets('goes to the shell, with the one notification',
          (tester) async {
        final opened = <String?>[];
        final repository = await filled(tester, [item(body: 'Der ganze Text')]);
        await pumpHost(tester, repository, newDesign: true,
            openInShell: ({String? initialId}) {
          opened.add(initialId);
          return true;
        });
        await tester.tap(popupOpen);
        await settle(tester);
        expect(opened, [a]);
        expect(find.byType(ServerNotificationCenterPage), findsNothing);
        expect(find.byType(ServerNotificationDetailPage), findsNothing);
      });

      testWidgets('a summary goes to the shell without a focus',
          (tester) async {
        final opened = <String?>[];
        final repository =
            await filled(tester, [item(title: 'Eins'), item(id: b)]);
        await pumpHost(tester, repository, newDesign: true,
            openInShell: ({String? initialId}) {
          opened.add(initialId);
          return true;
        });
        await tester.tap(popupOpen);
        await settle(tester);
        expect(opened, [null]);
        expect(find.byType(ServerNotificationCenterPage), findsNothing);
      });

      testWidgets('without a shell, as signed out, it opens as before',
          (tester) async {
        final repository = await filled(tester, [item(body: 'Der ganze Text')]);
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpHost(tester, repository,
            newDesign: true, openInShell: ({String? initialId}) => false);
        await tester.tap(popupOpen);
        await settle(tester);
        expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
      });

      testWidgets('Legacy never asks the shell', (tester) async {
        final opened = <String?>[];
        final repository = await filled(tester, [item(body: 'Der ganze Text')]);
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpHost(tester, repository, openInShell: ({String? initialId}) {
          opened.add(initialId);
          return true;
        });
        await tester.tap(popupOpen);
        await settle(tester);
        expect(opened, isEmpty);
        expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
      });
    });

    testWidgets('dismissing elsewhere removes it from the popup',
        (tester) async {
      final repository = await filled(tester, [item(critical: true)]);
      await pumpHost(tester, repository);
      await drive(tester, repository.dismiss(a));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    });

    testWidgets('waits for the app lock instead of timing out unseen',
        (tester) async {
      var locked = true;
      final changes = ValueNotifier(0);
      final repository = await filled(tester, [item()]);
      await pumpHost(tester, repository,
          isBlocked: () => locked, blockedChanges: changes);
      expect(popup, findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(repository.pendingAlerts, hasLength(1));
      locked = false;
      changes.value++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(popup, findsOneWidget);
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
    });

    testWidgets('Escape closes, F6 reaches it by keyboard', (tester) async {
      final repository = await filled(tester, [item(critical: true)]);
      await pumpHost(tester, repository);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      final open = tester.widget<TextButton>(popupOpen);
      expect(open.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    });

    testWidgets('keys pass through while no popup is open', (tester) async {
      final repository = await filled(tester, []);
      await pumpHost(tester, repository);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
    });

    testWidgets('hovering holds the popup open', (tester) async {
      final repository = await filled(tester, [item()]);
      await pumpHost(tester, repository);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(popup));
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      expect(popup, findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    });

    testWidgets('is announced and labelled for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await filled(tester, [item(title: 'Neu')]);
      await pumpHost(tester, repository);
      final live = find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.liveRegion == true);
      expect(
        tester.getSemantics(live),
        containsSemantics(
          isLiveRegion: true,
          label: 'Neue App-Mitteilung: Neu\nText',
        ),
      );
      expect(
        tester.getSemantics(popupClose),
        containsSemantics(
            label: 'Schließen', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
      await tester.tap(popupClose);
      await tester.pumpAndSettle();
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('meets contrast and target guidelines ($mode)',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final repository = await filled(tester, [item(critical: true)]);
        await pumpHost(tester, repository, mode: mode);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });
    }

    group('placement (#111)', () {
      const statusBar = 24.0;

      /// A window of [size] with a status bar, showing [home].
      Future<void> pumpPage(
        WidgetTester tester,
        ServerNotificationRepository repository, {
        required Size size,
        required Widget home,
        bool newDesign = true,
        double keyboard = 0,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: statusBar);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.reset);
        navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(
          navigator: navigator,
          home: home,
          builder: (context, child) => ServerNotificationHost(
            newDesign: newDesign,
            repository: repository,
            navigator: () => navigator.currentState,
            isBlocked: () => false,
            blockedChanges: ChangeNotifier(),
            onLanguage: (_) {},
            child: child!,
          ),
        ));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      Rect card(WidgetTester tester) => tester.getRect(
          find.descendant(of: popup, matching: find.byType(Semantics)).first);

      final header = find.byKey(const Key('test-header'));
      final bell = find.byKey(const Key('test-bell'));
      final school = find.text('Schule am Berg');

      for (final newDesign in [true, false]) {
        final design = newDesign ? 'new' : 'legacy';
        testWidgets(
            'a phone shows it across the width below the header '
            '($design design)', (tester) async {
          final repository = await filled(tester, [item(critical: true)]);
          await pumpPage(
            tester,
            repository,
            size: const Size(360, 640),
            newDesign: newDesign,
            home: newDesign
                ? const Scaffold(appBar: TestHeader(), body: Text('App'))
                : Scaffold(
                    appBar: AppBar(
                      title: const Text('Schule am Berg'),
                      actions: [
                        IconButton(
                          key: const Key('test-bell'),
                          onPressed: () {},
                          icon: const Icon(Icons.notifications_outlined),
                        ),
                      ],
                    ),
                    body: const Text('App'),
                  ),
          );
          final rect = card(tester);
          final headerBottom = newDesign
              ? tester.getRect(header).bottom
              : tester.getRect(find.byType(AppBar)).bottom;
          expect(headerBottom, statusBar + kToolbarHeight);
          expect(rect.top, greaterThanOrEqualTo(headerBottom));
          expect(rect.top, lessThanOrEqualTo(headerBottom + 12),
              reason: 'directly below it');
          for (final covered in [bell, school]) {
            expect(rect.overlaps(tester.getRect(covered)), isFalse);
          }
          expect(rect.left, 12);
          expect(rect.right, 360 - 12);
          expect(rect.height, lessThanOrEqualTo(640 * 0.4));
          await tester.tap(popupClose);
          await tester.pumpAndSettle();
        });
      }

      testWidgets('a wide window shows it in the top end corner',
          (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(1280, 800),
          home: const Scaffold(
            appBar: TestHeader(floatingMaxWidth: 1000),
            body: Text('App'),
          ),
        );
        final rect = card(tester);
        final headerRect = tester.getRect(header);
        expect(headerRect.bottom,
            statusBar + DesignTokens.gutter + kToolbarHeight);
        expect(rect.top, greaterThanOrEqualTo(headerRect.bottom));
        expect(rect.overlaps(headerRect), isFalse);
        expect(rect.overlaps(tester.getRect(bell)), isFalse);
        expect(rect.right, 1280 - 12);
        expect(rect.width, lessThanOrEqualTo(420));
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      testWidgets('follows a header that grows', (tester) async {
        final strip = ValueNotifier(false);
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(360, 640),
          home: ValueListenableBuilder(
            valueListenable: strip,
            builder: (context, strip, _) => Scaffold(
              appBar: TestHeader(strip: strip),
              body: const Text('App'),
            ),
          ),
        );
        expect(card(tester).top, greaterThanOrEqualTo(statusBar + 56));
        strip.value = true;
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(header).bottom, statusBar + 56 + 48);
        expect(card(tester).top, greaterThanOrEqualTo(statusBar + 56 + 48));
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      testWidgets('without a header it keeps clear of the status bar',
          (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(360, 640),
          home: const Scaffold(body: Text('App')),
        );
        final rect = card(tester);
        expect(rect.top, greaterThan(statusBar));
        // Room for the toolbars of older pages and the bell of the sign-in.
        expect(rect.top, greaterThanOrEqualTo(statusBar + kToolbarHeight));
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      testWidgets('the header of a covered page does not count',
          (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(360, 640),
          home: const Scaffold(
            appBar: TestHeader(strip: true),
            body: Text('App'),
          ),
        );
        expect(card(tester).top, greaterThanOrEqualTo(statusBar + 56 + 48));
        navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Andere Seite')),
        ));
        await tester.pumpAndSettle();
        expect(card(tester).top, lessThan(statusBar + 56 + 48));
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      for (final newDesign in [true, false]) {
        testWidgets(
            'large text and long texts fit the height '
            '(${newDesign ? 'new' : 'legacy'} design)', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final repository = await filled(tester, [
            item(title: 'Lang ' * 30, body: 'Text ' * 200, critical: true),
          ]);
          await pumpPage(
            tester,
            repository,
            size: const Size(360, 640),
            newDesign: newDesign,
            home: const Scaffold(appBar: TestHeader(), body: Text('App')),
          );
          expect(tester.takeException(), isNull);
          final rect = card(tester);
          expect(rect.height, lessThanOrEqualTo(640 * 0.4 + 0.01));
          expect(rect.bottom, lessThanOrEqualTo(640));
          // The way to the full text stays reachable.
          await tester.ensureVisible(popupOpen);
          await tester.pumpAndSettle();
          await tester.tap(popupOpen);
          await settle(tester);
          expect(find.byType(ServerNotificationDetailPage), findsOneWidget);
        });
      }

      testWidgets('a short window with the keyboard open does not overflow',
          (tester) async {
        final repository = await filled(tester, [
          item(title: 'Lang ' * 30, body: 'Text ' * 200, critical: true),
        ]);
        await pumpPage(
          tester,
          repository,
          size: const Size(640, 360),
          keyboard: 200,
          home: const Scaffold(appBar: TestHeader(), body: Text('App')),
        );
        expect(tester.takeException(), isNull);
        final rect = card(tester);
        expect(rect.top, greaterThanOrEqualTo(statusBar + 56));
        // Above the keyboard: the body scrolls in what is left.
        expect(rect.bottom, lessThanOrEqualTo(360 - 200 + 0.01));
        expect(popupClose.hitTestable(), findsOneWidget);
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      testWidgets('slides in from above', (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(
          navigator: navigator,
          home: const Scaffold(body: Text('App')),
          builder: (context, child) => ServerNotificationHost(
            newDesign: true,
            repository: repository,
            navigator: () => navigator.currentState,
            isBlocked: () => false,
            blockedChanges: ChangeNotifier(),
            onLanguage: (_) {},
            child: child!,
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final during = card(tester).top;
        await tester.pumpAndSettle();
        expect(during, lessThan(card(tester).top));
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      testWidgets('swiping it up closes it, without reading it',
          (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(360, 640),
          home: const Scaffold(appBar: TestHeader(), body: Text('App')),
        );
        await tester.drag(popup, const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(popup, findsNothing);
        expect(repository.unreadCount, 1);
      });

      testWidgets('a short drag lets it snap back', (tester) async {
        final repository = await filled(tester, [item(critical: true)]);
        await pumpPage(
          tester,
          repository,
          size: const Size(360, 640),
          home: const Scaffold(appBar: TestHeader(), body: Text('App')),
        );
        final before = card(tester);
        final gesture = await tester.startGesture(tester.getCenter(popup));
        await gesture.moveBy(const Offset(0, -20));
        await gesture.moveBy(const Offset(0, -5));
        await tester.pump(const Duration(seconds: 1));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(popup, findsOneWidget);
        expect(card(tester), before);
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });
    });

    group('in the new design', () {
      testWidgets('fits with large text', (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = await filled(tester, [item(critical: true)]);
        await pumpHost(tester, repository, newDesign: true);
        expect(tester.takeException(), isNull);
        expect(popupOpen, findsOneWidget);
        await tester.tap(popupClose);
        await tester.pumpAndSettle();
      });

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('meets contrast and target guidelines ($mode)',
            (tester) async {
          final semantics = tester.ensureSemantics();
          final repository = await filled(tester, [item(critical: true)]);
          await pumpHost(tester, repository, mode: mode, newDesign: true);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          semantics.dispose();
          await tester.tap(popupClose);
          await tester.pumpAndSettle();
        });
      }

      testWidgets('opens the detail, closes itself and takes the keyboard',
          (tester) async {
        final repository = await filled(tester, [item(title: 'Neu')]);
        await pumpHost(tester, repository, newDesign: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.f6);
        await tester.pump();
        expect(
            tester.widget<FilledButton>(popupOpen).focusNode!.hasFocus, isTrue);
        await tester.tap(popupOpen);
        await tester.pumpAndSettle();
        expect(popup, findsNothing);
        expect(find.byType(ServerNotificationDetailPage), findsOneWidget);

        final again = await filled(tester, [item(id: b)]);
        await pumpHost(tester, again, newDesign: true);
        await tester.pump(serverNotificationPopupDuration);
        await tester.pumpAndSettle();
        expect(popup, findsNothing);
      });
    });

    testWidgets('respects reduced motion', (tester) async {
      final repository = await filled(tester, [item(critical: true)]);
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: app(
          navigator: navigator,
          home: const Scaffold(body: Text('App')),
          builder: (context, child) => ServerNotificationHost(
            repository: repository,
            navigator: () => navigator.currentState,
            isBlocked: () => false,
            blockedChanges: ChangeNotifier(),
            onLanguage: (_) {},
            child: child!,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(popup, findsOneWidget);
      // At its place at once, without sliding in.
      final first = tester.getRect(popup);
      await tester.pumpAndSettle();
      expect(tester.getRect(popup), first);
      expect(first.top, kToolbarHeight + 8);
    });
  });

  group('theming', () {
    double contrast(Color a, Color b) {
      final first = a.computeLuminance();
      final second = b.computeLuminance();
      final hi = first > second ? first : second;
      final lo = first > second ? second : first;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final scheme in [AppPalette.light, AppPalette.dark]) {
      testWidgets('any type color stays readable (${scheme.brightness})',
          (tester) async {
        for (final value in [
          0xFFFFFF00,
          0xFF000000,
          0xFFFFFFFF,
          0xFFE9A23B,
          0xFF2E7D5B,
          0xFFC4372C,
          0xFF2F6FB5,
        ]) {
          final background = Color.alphaBlend(
              Color(value).withValues(alpha: 0.16), scheme.surfaceContainerLow);
          final color = readableServerNotificationColor(Color(value),
              background: background, towards: scheme.onSurface);
          expect(contrast(color, background), greaterThanOrEqualTo(4.5),
              reason: value.toRadixString(16));
        }
      });
    }

    testWidgets('a type without usable color uses the theme', (tester) async {
      final repository = await filled(tester, [item(color: 'nonsense')]);
      await tester.pumpWidget(app(
        home: ServerNotificationCenterPage(
            repository: repository, onRefresh: () {}),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ServerNotificationTypeIcon), findsOneWidget);
    });

    testWidgets('an unknown icon renders the fallback', (tester) async {
      final repository = await filled(tester, [item(icon: 'skull')]);
      await tester.pumpWidget(app(
        home: ServerNotificationCenterPage(
            repository: repository, onRefresh: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(serverNotificationFallbackIcon), findsOneWidget);
    });
  });

  group('languages', () {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('the center renders in $locale', (tester) async {
        final repository = await filled(tester, [item()]);
        await tester.pumpWidget(app(
          locale: locale,
          home: ServerNotificationCenterPage(
              repository: repository, onRefresh: () {}),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('2026'), findsOneWidget);
      });
    }

    // The server labels its types in one language (#120).
    final germanTypes = [
      item(
          title: 'Wartungsarbeiten',
          typeKey: 'maintenance',
          typeLabel: 'Wartung',
          publishedAt: '2026-10-22T19:03:00Z'),
      item(
          id: b,
          title: 'Ausfall',
          typeKey: 'critical',
          typeLabel: 'Kritisch',
          critical: true,
          publishedAt: '2026-10-22T19:02:00Z'),
      item(
          id: c,
          title: 'Termin',
          typeKey: 'event',
          typeLabel: 'Veranstaltung',
          publishedAt: '2026-10-22T19:01:00Z'),
    ];

    testWidgets('known types follow the app language in list and speech',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = await filled(tester, germanTypes);
      await tester.pumpWidget(app(
        locale: const Locale('it'),
        home: ServerNotificationCenterPage(
            repository: repository, onRefresh: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Manutenzione'), findsOneWidget);
      expect(find.text('Critico'), findsOneWidget);
      expect(find.text('Wartung'), findsNothing);
      expect(find.text('Kritisch'), findsNothing);
      // A key the app does not know keeps the server's label.
      expect(find.text('Veranstaltung'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(', Manutenzione, Wartungsarbeiten, ')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(', Critico, Ausfall, ')),
          findsOneWidget);
      semantics.dispose();
    });

    for (final (locale, expected) in [
      (const Locale('it'), 'Manutenzione'),
      (const Locale('en'), 'Maintenance'),
      (
        const Locale.fromSubtags(languageCode: 'de', countryCode: 'LLD'),
        'Manutenziun'
      ),
      (const Locale('de'), 'Wartung'),
    ]) {
      testWidgets('the detail names the type in $locale', (tester) async {
        final repository = await filled(tester, germanTypes);
        await tester.pumpWidget(app(
          locale: locale,
          home: ServerNotificationDetailPage(
            id: a,
            repository: repository,
            openLink: (_) async => ServerNotificationLinkResult.opened,
          ),
        ));
        await settle(tester);
        expect(find.text(expected), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        repository.dispose();
      });
    }

    testWidgets('the popup host reports the app language, also after a change',
        (tester) async {
      final repository = await filled(tester, []);
      final reported = <String>[];
      Widget host(Locale locale) => app(
            locale: locale,
            home: const Text('App'),
            builder: (context, child) => ServerNotificationHost(
              repository: repository,
              navigator: () => null,
              isBlocked: () => false,
              blockedChanges: ChangeNotifier(),
              onLanguage: reported.add,
              child: child!,
            ),
          );
      await tester.pumpWidget(host(const Locale('it')));
      await tester.pumpAndSettle();
      expect(reported, ['it']);
      await tester.pumpWidget(host(
          const Locale.fromSubtags(languageCode: 'de', countryCode: 'LLD')));
      await tester.pumpAndSettle();
      expect(reported.last, 'lld');
      await tester.pumpWidget(host(const Locale('en')));
      await tester.pumpAndSettle();
      expect(reported.last, 'en');
    });
  });

  group('fresh installation (#103)', () {
    Future<ServerNotificationRepository> freshlyInstalled(
      WidgetTester tester,
      FakeServer server, {
      int syncs = 1,
    }) async {
      final repository = repositoryFor(server, FakeStorage());
      for (var i = 0; i < syncs; i++) {
        await drive(tester, repository.sync(selection));
      }
      return repository;
    }

    final backlog = [
      item(title: 'Alt 1', publishedAt: '2026-03-01T08:00:00Z'),
      item(id: b, title: 'Alt 2', publishedAt: '2026-05-01T08:00:00Z'),
      item(id: c, title: 'Alt 3', publishedAt: '2026-07-01T08:00:00Z'),
    ];

    Future<void> pumpEverything(
      WidgetTester tester,
      ServerNotificationRepository repository,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(
        navigator: navigator,
        home: Scaffold(
          appBar: AppBar(actions: [
            ServerNotificationBell(
              repository: repository,
              enabled: true,
              onPressed: () => showServerNotificationCenter(
                navigator.currentState!,
                repository: repository,
              ),
            ),
          ]),
          body: const Text('App'),
        ),
        builder: (context, child) => ServerNotificationHost(
          repository: repository,
          navigator: () => navigator.currentState,
          isBlocked: () => false,
          blockedChanges: ChangeNotifier(),
          onLanguage: (_) {},
          child: child!,
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('no popup and no badge, but the center lists the backlog',
        (tester) async {
      final server = FakeServer()..replyList(backlog);
      final repository = await freshlyInstalled(tester, server);
      await pumpEverything(tester, repository);
      expect(popup, findsNothing);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

      await tester.tap(find.byKey(const Key('server-notification-bell')));
      await tester.pumpAndSettle();
      for (final title in ['Alt 1', 'Alt 2', 'Alt 3']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(
          find.byKey(const Key('server-notification-unread-dot')), findsNothing,
          reason: 'listed as read');
    });

    testWidgets('a notification after the first sync pops up and counts',
        (tester) async {
      final server = FakeServer()
        ..replyList(backlog)
        ..replyList([
          item(
              id: '00000000-0000-4000-8000-000000000099',
              title: 'Neu',
              publishedAt: '2026-10-22T20:05:00Z'),
          ...backlog,
        ]);
      final repository = await freshlyInstalled(tester, server, syncs: 2);
      await pumpEverything(tester, repository);
      expect(popup, findsOneWidget);
      expect(find.descendant(of: popup, matching: find.text('Neu')),
          findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'the badge');
    });

    testWidgets('a critical backlog item pops up, counts and stays open',
        (tester) async {
      final server = FakeServer()
        ..replyList([
          item(
              id: '00000000-0000-4000-8000-000000000098',
              title: 'Ausfall',
              critical: true,
              publishedAt: '2026-08-01T08:00:00Z'),
          ...backlog,
        ]);
      final repository = await freshlyInstalled(tester, server);
      await pumpEverything(tester, repository);
      expect(popup, findsOneWidget);
      expect(find.descendant(of: popup, matching: find.text('Ausfall')),
          findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'the badge');
      await tester.pump(const Duration(seconds: 30));
      expect(popup, findsOneWidget, reason: 'critical: closed by hand only');
    });
  });
}

/// A header of the new design, as the dashboard has it: a school name and a
/// bell, and on request the strip for new entries.
class TestHeader extends StatelessWidget implements PreferredSizeWidget {
  const TestHeader({super.key, this.floatingMaxWidth, this.strip = false});

  final double? floatingMaxWidth;
  final bool strip;

  double get _height => kToolbarHeight + (strip ? 48 : 0);

  @override
  Size get preferredSize => Size.fromHeight(
      _height + (floatingMaxWidth == null ? 0 : DesignTokens.gutter));

  @override
  Widget build(BuildContext context) => GlassHeaderShell(
        surfaceKey: const Key('test-header'),
        floatingMaxWidth: floatingMaxWidth,
        child: SizedBox(
          height: _height,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Schule am Berg')),
                  IconButton(
                    key: const Key('test-bell'),
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_outlined),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
