import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart' show Store;
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/export_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/messages.dart';
import 'package:dr/ui/messages_new.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

const _phone = Size(412, 900);

/// Two received messages, one unread with an attachment and a reply, one sent
/// and one archived.
List<Message> _messages() => [
      buildMessage(
        id: 1,
        subject: 'Elternsprechtag',
        fromName: 'Sekretariat',
        attachments: [
          buildAttachment(id: 7, messageId: 1, originalName: 'Termine.pdf'),
        ],
      ).rebuild((b) => b
        ..incoming = true
        ..labelAll = true
        ..showReply = true
        ..needsResponse = true
        ..responseRequired = 1
        ..archiveMessageEnabled = 1),
      buildMessage(id: 2, subject: 'Wandertag').rebuild((b) => b
        ..incoming = true
        ..labelAll = true
        ..timeRead = fixtureNow),
      buildMessage(id: 3, subject: 'Gesendete Frage').rebuild((b) => b
        ..incoming = false
        ..outgoing = true
        ..labelAll = true),
      buildMessage(id: 4, subject: 'Alte Mitteilung').rebuild((b) => b
        ..incoming = false
        ..archived = true
        ..labelAll = true
        ..timeRead = fixtureNow),
    ];

MessagesState _messagesState({
  List<Message>? messages,
  int? showMessage,
  UtcDateTime? lastFetched,
}) =>
    MessagesState((b) => b
      ..messages = ListBuilder<Message>(messages ?? _messages())
      ..showMessage = showMessage
      ..lastFetched = lastFetched ?? fixtureNow);

AppState _state({
  MessagesState? messages,
  String languageCode = 'de',
  bool noInternet = false,
  bool loggedIn = true,
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = loggedIn
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
      b.noInternet = noInternet;
      b.messagesState.replace(messages ?? _messagesState());
    });

class _Calls {
  final read = <int>[];
  final archived = <int>[];
  final replies = <String>[];
  final opened = <int>[];
  int retries = 0;
}

/// The page with callbacks that record what it asks for.
MessagesPage _page(
  _Calls calls, {
  MessagesState? state,
  bool noInternet = false,
}) =>
    MessagesPage(
      state: state ?? _messagesState(),
      noInternet: noInternet,
      onOpenFile: (file) => calls.opened.add(file.id),
      onMarkAsRead: (m) => calls.read.add(m.id),
      onArchive: (m) => calls.archived.add(m.id),
      onReply: (id, response) => calls.replies.add(response),
      onRetry: () => calls.retries++,
    );

/// Opens the messages as the navigation does, below the shell of the new
/// design. [page] replaces the container.
Future<Store<AppState, AppStateBuilder, AppActions>> _pumpMessages(
  WidgetTester tester, {
  Widget? page,
  AppState? state,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  bool newDesign = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: state ?? _state(),
    newDesign: newDesign,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
    darkTheme: themeController.buildTheme(
      brightness: Brightness.dark,
      amoledMode: amoled,
    ),
  );
  await settleFor(tester);
  scaffoldKey!.currentState!
      .selectContentWidget(page ?? MessagesPageContainer(), Pages.messages);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _entry(int id) => find.byKey(ValueKey('messages-entry-$id'));
Finder _open(int id) => find.byKey(ValueKey('messages-open-$id'));
Finder _segment(int folder) => find.byKey(ValueKey('glass-segment-$folder'));
final _header = find.byKey(const Key('messages-app-header'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the new design shows the glass page', (tester) async {
      await _pumpMessages(tester);

      expect(find.byType(MessagesPageNew), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(MessageWidget), findsNothing);
      expect(_header, findsOneWidget);
    });

    testWidgets('Legacy keeps the tabs and expansion tiles', (tester) async {
      await _pumpMessages(tester, newDesign: false);

      expect(find.byType(MessagesPageNew), findsNothing);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(MessageWidget), findsNWidgets(2));
    });

    testWidgets('a switch of the design keeps the folder', (tester) async {
      final store = await _pumpMessages(tester);
      await _tap(tester, _segment(1));
      expect(find.text('Gesendete Frage'), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Gesendete Frage'), findsOneWidget);
      expect(find.text('Wandertag'), findsNothing);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(MessagesPageNew), findsOneWidget);
      expect(find.text('Gesendete Frage'), findsOneWidget);
    });
  });

  group('content', () {
    testWidgets('a glass header with export and folders, no back button',
        (tester) async {
      await _pumpMessages(tester);

      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('messages-export')), findsOneWidget);
      expect(
        find.descendant(
          of: _header,
          matching: find.byType(GlassSegmentedControl<int>),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(_entry(1)).top,
        greaterThanOrEqualTo(tester.getRect(_header).bottom),
      );
    });

    testWidgets('export opens the export page', (tester) async {
      await _pumpMessages(tester);
      await _tap(tester, find.byKey(const Key('messages-export')));
      expect(find.byType(ExportPage), findsOneWidget);
    });

    testWidgets('the folders filter the messages', (tester) async {
      await _pumpMessages(tester);
      expect(find.text('Elternsprechtag'), findsOneWidget);
      expect(find.text('Wandertag'), findsOneWidget);
      expect(find.text('Gesendete Frage'), findsNothing);

      await _tap(tester, _segment(1));
      expect(find.text('Gesendete Frage'), findsOneWidget);
      expect(find.text('Wandertag'), findsNothing);

      await _tap(tester, _segment(2));
      expect(find.text('Alte Mitteilung'), findsOneWidget);
      expect(find.text('Gesendete Frage'), findsNothing);

      await _tap(tester, _segment(3));
      expect(find.byType(MessageEntry), findsNWidgets(4));
    });

    testWidgets('unread messages carry the blue mark', (tester) async {
      await _pumpMessages(tester);
      final scheme = Theme.of(tester.element(_entry(1))).colorScheme;

      expect(
        find.descendant(
          of: _entry(1),
          matching: find.byKey(const Key('messages-unread-mark')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _entry(2),
          matching: find.byKey(const Key('messages-unread-mark')),
        ),
        findsNothing,
      );
      final mark = tester.widget<DecoratedBox>(
        find.byKey(const Key('messages-unread-mark')),
      );
      expect(
        (mark.decoration as ShapeDecoration).color,
        scheme.infoContainer,
      );
      expect(
        find.descendant(
            of: _entry(1), matching: find.text('Nicht beantwortet')),
        findsOneWidget,
      );
    });

    testWidgets('each message is in a layer of its own, closed is not built',
        (tester) async {
      await _pumpMessages(tester);

      expect(
        find.ancestor(of: _entry(1), matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      expect(find.textContaining('Sehr geehrte Eltern'), findsNothing);
      expect(find.text('Termine.pdf'), findsNothing);
    });

    testWidgets('a tap opens a message, marks it read, and shows its parts',
        (tester) async {
      final calls = _Calls();
      await _pumpMessages(tester, page: _page(calls));

      await _tap(tester, _open(1));
      expect(calls.read, [1]);
      expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
      expect(find.text('Termine.pdf'), findsOneWidget);
      expect(
          find.textContaining('Sekretariat', findRichText: true), findsWidgets);

      await tester.ensureVisible(find.text('Öffnen'));
      await _tap(tester, find.text('Öffnen'));
      expect(calls.opened, [7]);

      await tester.ensureVisible(find.byKey(const Key('messages-reply-agree')));
      await _tap(tester, find.byKey(const Key('messages-reply-agree')));
      await _tap(tester, find.byKey(const Key('messages-reply-not-agree')));
      expect(calls.replies, ['agree', 'not_agree']);

      await tester.ensureVisible(find.byKey(const Key('messages-archive')));
      await _tap(tester, find.byKey(const Key('messages-archive')));
      expect(calls.archived, [1]);

      // One open at a time; a read message is not marked again.
      await _tap(tester, _open(2));
      expect(calls.read, [1]);
      expect(find.text('Termine.pdf'), findsNothing);
    });

    testWidgets('a sent message is not marked read', (tester) async {
      final calls = _Calls();
      await _pumpMessages(tester, page: _page(calls));
      await _tap(tester, _segment(1));
      await _tap(tester, _open(3));
      expect(calls.read, isEmpty);
    });

    testWidgets('an attachment shows its download, offline it cannot open',
        (tester) async {
      final calls = _Calls();
      final messages = _messages();
      messages[0] = messages[0].rebuild((b) => b.attachments = ListBuilder([
            buildAttachment(
              id: 7,
              messageId: 1,
              originalName: 'Termine.pdf',
              downloading: true,
            ),
          ]));
      await _pumpMessages(
        tester,
        page: _page(
          calls,
          state: _messagesState(messages: messages, showMessage: 1),
          noInternet: true,
        ),
      );

      expect(
        find.byKey(const Key('messages-attachment-downloading')),
        findsOneWidget,
      );
      final open = tester.widget<TextButton>(find.ancestor(
        of: find.text('Öffnen'),
        matching: find.byType(TextButton),
      ));
      expect(open.onPressed, isNull);
      expect(find.byKey(const Key('messages-last-fetched')), findsOneWidget);
    });

    testWidgets('a message header is one button for screen readers',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpMessages(tester);

      final node = tester.getSemantics(_open(1));
      expect(node.label, startsWith('Elternsprechtag, neu'));
      expect(
        node,
        isSemantics(isButton: true, hasTapAction: true, hasExpandedState: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('messages-header-title'))),
        isSemantics(label: 'Mitteilungen', isHeader: true),
      );
      semantics.dispose();
    });
  });

  group('deep link', () {
    testWidgets('showMessage opens the page with the message in view',
        (tester) async {
      final mock = MockWrapper();
      wrapper = mock;
      when(() => mock.send(any(), args: any(named: 'args')))
          .thenAnswer((_) async => null);
      when(() => mock.send(any())).thenAnswer((_) async => null);
      final messages = [
        for (var id = 100; id < 140; id++)
          buildMessage(id: id, subject: 'Mitteilung $id').rebuild((b) => b
            ..incoming = true
            ..labelAll = true
            ..timeRead = fixtureNow),
        buildMessage(id: 500, subject: 'Ziel').rebuild((b) => b
          ..archived = true
          ..labelAll = true),
      ];
      tester.view.physicalSize = const Size(412, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = createStore(
        // Signed out, so that the middleware does not save the state.
        initialState: _state(
          messages: _messagesState(messages: messages),
          loggedIn: false,
        ),
        newDesign: true,
        withMiddleware: true,
      );
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);

      // Not awaited: the route it opens only finishes while frames are pumped.
      unawaited(store.actions.routingActions.showMessage(139));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(find.byType(MessagesPageNew), findsOneWidget);
      expect(find.text('Mitteilung 139'), findsOneWidget);
      final entry = tester.getRect(_entry(139));
      expect(entry.top, greaterThanOrEqualTo(tester.getRect(_header).bottom));
      expect(entry.top, lessThan(800));
      expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);

      // Another link, to a message in another folder.
      unawaited(store.actions.routingActions.showMessage(500));
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(find.text('Ziel'), findsOneWidget);
      expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
      expect(
        store.state.messagesState.messages
            .firstWhere((m) => m.id == 500)
            .archived,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('states', () {
    testWidgets('an empty folder says so', (tester) async {
      await _pumpMessages(
        tester,
        state: _state(messages: _messagesState(messages: const [])),
      );
      expect(find.byKey(const Key('messages-empty-0')), findsOneWidget);
      expect(find.text('Noch keine Mitteilungen'), findsOneWidget);
      expect(_header, findsOneWidget);
    });

    testWidgets('offline without messages offers a retry', (tester) async {
      final calls = _Calls();
      await _pumpMessages(
        tester,
        page: _page(
          calls,
          state: MessagesState(),
          noInternet: true,
        ),
      );
      expect(find.byKey(const Key('messages-offline')), findsOneWidget);
      await _tap(tester, find.text('Erneut versuchen'));
      expect(calls.retries, 1);
    });

    testWidgets('offline with messages shows the hint, not the black pill',
        (tester) async {
      final calls = _Calls();
      await _pumpMessages(
        tester,
        page: _page(calls, noInternet: true),
      );
      expect(find.byKey(const Key('messages-last-fetched')), findsOneWidget);
      expect(find.byType(GlassOfflineHint), findsOneWidget);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(GlassOfflineHint),
          matching: find.byType(IconButton),
        ),
      );
      expect(calls.retries, 1);
    });

    testWidgets('while loading, quiet rows and the bar', (tester) async {
      final calls = _Calls();
      await _pumpMessages(
        tester,
        page: MessagesPage(
          state: null,
          noInternet: false,
          onOpenFile: (_) {},
          onMarkAsRead: (_) {},
          onArchive: (_) {},
          onReply: (_, __) {},
          onRetry: () => calls.retries++,
        ),
      );
      expect(find.byKey(const Key('messages-loading')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the list ends above the bar', (tester) async {
      final messages = [
        for (var id = 1; id < 30; id++)
          buildMessage(id: id, subject: 'Mitteilung $id').rebuild((b) => b
            ..incoming = true
            ..labelAll = true),
      ];
      await _pumpMessages(
        tester,
        size: const Size(360, 640),
        state: _state(messages: _messagesState(messages: messages)),
      );

      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      final header = tester.getRect(_header);
      expect(header.left, 0);
      expect(header.top, 0);
      await tester.drag(
        find.byKey(const Key('messages-list')),
        const Offset(0, -5000),
      );
      await settleFor(tester);
      expect(
        tester.getRect(_entry(29)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });

    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('at ${size.width} x ${size.height} the header floats',
          (tester) async {
        await _pumpMessages(tester, size: size);

        expect(find.byType(AppNavigationRail), findsOneWidget);
        final header = tester.getRect(_header);
        final entry = tester.getRect(_entry(1));
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(entry.left, header.left);
        expect(entry.right, header.right);
        expect(entry.top, greaterThanOrEqualTo(header.bottom));
        // The full names of the folders fit here (the test font is wider
        // than Roboto, so only the wide window is sure to fit them).
        if (size.width >= 1280) {
          expect(find.text('Empfangen'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('320 px, text at $scale, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpMessages(
            tester,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
            page: _page(_Calls(), state: _messagesState(showMessage: 1)),
          );

          expect(tester.takeException(), isNull);
          expect(
              tester.getSize(_entry(1)).width, 320 - 2 * DesignTokens.gutter);
          expect(tester.getSize(_open(1)).height, greaterThanOrEqualTo(48));
          // The short names, the full ones are for screen readers.
          expect(find.text('Empf.'), findsOneWidget);
          final control = tester.getRect(
            find.byType(GlassSegmentedControl<int>),
          );
          expect(control.right, lessThanOrEqualTo(320));
        });
      }
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pumpMessages(
        tester,
        page: _page(_Calls(), state: _messagesState(showMessage: 1)),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('messages-list')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('high contrast has no blur and no light, ${themeMode.name}',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpMessages(
          tester,
          themeMode: themeMode,
          page: _page(_Calls(), state: _messagesState(showMessage: 1)),
        );

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(MessagesPageNew),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint && widget.painter is GlassSheenPainter,
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without blur the header stays readable', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      addTearDown(GlassPerformance.instance.reset);
      await _pumpMessages(tester);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('messages-header-title')), findsOneWidget);
    });
  });

  testWidgets('with reduced motion a message opens at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpMessages(tester);

    await tester.tap(_open(2));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
    expect(
      tester.getSize(find.byType(SizeTransition)).height,
      greaterThan(100),
    );
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpMessages(
          tester,
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );

        final l10n = tester.element(find.byType(MessagesPageNew)).l10n;
        final title = tester.widget<Text>(
          find.byKey(const Key('messages-header-title')),
        );
        expect(title.data, l10n.text('messages.title'));
        final control = tester.widget<GlassSegmentedControl<int>>(
          find.byType(GlassSegmentedControl<int>),
        );
        expect(
          [for (final segment in control.segments) segment.fullLabel],
          [for (final key in messageFolderKeys) l10n.text(key)],
        );
        for (final segment in control.segments) {
          expect(segment.label, isNot(startsWith('messages.')));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
