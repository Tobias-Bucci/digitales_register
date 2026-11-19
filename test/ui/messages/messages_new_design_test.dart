import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart' show Store;
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/data.dart';
import 'package:dr/external_links.dart';
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
import 'package:dr/ui/dashboard_columns.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderFlex;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';

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
        expect(header.width, lessThanOrEqualTo(DashboardColumns.maxWidth));
        // Centered below the header, which is as wide on every page (#140).
        expect(entry.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(entry.center.dx, closeTo(header.center.dx, 0.5));
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

  group('addresses in the text (#143)', () {
    for (final newDesign in [true, false]) {
      testWidgets(
          '${newDesign ? 'the new design' : 'Legacy'} shows and opens them',
          (tester) async {
        final launched = <Uri>[];
        externalLinkLauncherOverride = (uri) async {
          launched.add(uri);
          return true;
        };
        addTearDown(() => externalLinkLauncherOverride = null);
        final messages = _messages()
          ..[1] = _messages()[1].rebuild((b) => b
            ..text = jsonEncode({
              'ops': [
                {'insert': 'Anmeldung: https://example.org/anmeldung.\n'},
                {
                  'insert': 'Infos: www.example.org/wandertag',
                  'attributes': {'bold': true},
                },
                {
                  'insert': '\n',
                  'attributes': {'list': 'bullet'},
                },
                {'insert': 'Danke\n'},
              ],
            }));
        await _pumpMessages(
          tester,
          newDesign: newDesign,
          page: _page(
            _Calls(),
            state: _messagesState(messages: messages, showMessage: 2),
          ),
        );
        if (find
            .textContaining('Danke', findRichText: true)
            .evaluate()
            .isEmpty) {
          await _tap(tester, _open(2));
        }

        final links = <TextSpan>[];
        for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
          rich.text.visitChildren((span) {
            if (span is TextSpan && span.recognizer != null) links.add(span);
            return true;
          });
        }
        expect(links.map((span) => span.text),
            ['https://example.org/anmeldung', 'www.example.org/wandertag']);
        expect(links.last.style?.fontWeight, FontWeight.bold);
        for (final link in links) {
          (link.recognizer! as TapGestureRecognizer).onTap!();
        }
        await tester.pump();
        expect(launched, [
          Uri.parse('https://example.org/anmeldung'),
          Uri.parse('https://www.example.org/wandertag'),
        ]);
      });
    }
  });

  group('formatted text (#144)', () {
    // As a teacher formats it in the web register: a heading, a numbered
    // list, a quote, italic text, and a list item as the very last line.
    Message formatted() => _messages()[1].rebuild((b) => b
      ..text = jsonEncode({
        'ops': [
          {'insert': 'Wandertag am Freitag www.example.org/wandertag'},
          {
            'insert': '\n',
            'attributes': {'header': 1},
          },
          {
            'insert': 'Bitte beachten',
            'attributes': {'italic': true},
          },
          {'insert': ':\n'},
          {'insert': 'Treffpunkt am Bahnhof'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'Anmeldung: https://example.org/anmeldung'},
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {
            'insert': 'Jause',
            'attributes': {'bold': true},
          },
          {
            'insert': '\n',
            'attributes': {'list': 'ordered'},
          },
          {'insert': 'Die Direktion: www.example.org/regeln'},
          {
            'insert': '\n',
            'attributes': {'blockquote': true},
          },
          {'insert': 'Mitnehmen'},
          {
            'insert': '\n',
            'attributes': {'header': 3},
          },
          {'insert': 'Regenjacke'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
          {'insert': 'Turnschuhe'},
          {
            'insert': '\n',
            'attributes': {'list': 'bullet'},
          },
        ],
      }));

    Future<void> showFormatted(
      WidgetTester tester, {
      required bool newDesign,
      ThemeMode themeMode = ThemeMode.light,
      Size size = _phone,
    }) async {
      await _pumpMessages(
        tester,
        newDesign: newDesign,
        themeMode: themeMode,
        size: size,
        page: _page(
          _Calls(),
          state: _messagesState(
            messages: _messages()..[1] = formatted(),
            showMessage: 2,
          ),
        ),
      );
      if (find
          .textContaining('Turnschuhe', findRichText: true)
          .evaluate()
          .isEmpty) {
        await _tap(tester, _open(2));
      }
    }

    List<String> markers(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .where((data) => data == '•' || RegExp(r'^\d+\.$').hasMatch(data))
        .toList();

    /// The style [text] is shown in, merged from the root of its RichText.
    TextStyle styleOf(WidgetTester tester, String text) {
      TextStyle? found;
      void visit(InlineSpan span, TextStyle style) {
        final merged = style.merge(span.style);
        if (span is TextSpan) {
          if (span.text?.contains(text) ?? false) found ??= merged;
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child, merged);
          }
        }
      }

      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        visit(rich.text, const TextStyle());
      }
      return found!;
    }

    for (final newDesign in [true, false]) {
      final design = newDesign ? 'the new design' : 'Legacy';
      for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('$design, ${themeMode.name}: every line keeps its format',
            (tester) async {
          final launched = <Uri>[];
          externalLinkLauncherOverride = (uri) async {
            launched.add(uri);
            return true;
          };
          addTearDown(() => externalLinkLauncherOverride = null);
          final semantics = tester.ensureSemantics();
          await showFormatted(tester,
              newDesign: newDesign, themeMode: themeMode);

          // The numbers count, and the last line keeps its bullet.
          expect(markers(tester), ['1.', '2.', '3.', '•', '•']);
          final lastRow = find
              .ancestor(
                of: find.textContaining('Turnschuhe', findRichText: true),
                matching: find.byType(Row),
              )
              .first;
          expect(find.descendant(of: lastRow, matching: find.text('•')),
              findsOneWidget);

          final theme = Theme.of(tester.element(find.byType(MessagesPage)));
          final heading = styleOf(tester, 'Wandertag am Freitag');
          expect(heading.fontSize, theme.textTheme.titleLarge!.fontSize);
          expect(heading.fontSize,
              greaterThan(styleOf(tester, 'Treffpunkt').fontSize!));
          expect(styleOf(tester, 'Mitnehmen').fontSize,
              theme.textTheme.titleSmall!.fontSize);
          // The heading is marked as one for screen readers; the package
          // tests check the semantics tree itself.
          expect(
            find.ancestor(
              of: find.textContaining('Wandertag am Freitag',
                  findRichText: true),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.header == true,
              ),
            ),
            findsOneWidget,
          );

          expect(styleOf(tester, 'Bitte beachten').fontStyle, FontStyle.italic);
          expect(styleOf(tester, 'Die Direktion').color,
              theme.colorScheme.onSurfaceVariant);
          expect(styleOf(tester, 'Jause').fontWeight, FontWeight.bold);

          // Addresses in a heading, a numbered item and a quote open.
          final links = <TextSpan>[];
          for (final rich
              in tester.widgetList<RichText>(find.byType(RichText))) {
            rich.text.visitChildren((span) {
              if (span is TextSpan && span.recognizer != null) {
                links.add(span);
              }
              return true;
            });
          }
          expect(links.map((span) => span.text), [
            'www.example.org/wandertag',
            'https://example.org/anmeldung',
            'www.example.org/regeln',
          ]);
          for (final link in links) {
            expect(link.style?.color, theme.colorScheme.primary);
            expect(link.style?.decoration?.contains(TextDecoration.underline),
                isTrue);
            (link.recognizer! as TapGestureRecognizer).onTap!();
          }
          await tester.pump();
          expect(launched, [
            Uri.parse('https://www.example.org/wandertag'),
            Uri.parse('https://example.org/anmeldung'),
            Uri.parse('https://www.example.org/regeln'),
          ]);
          semantics.dispose();
        });
      }

      for (final (name, size, scale) in [
        ('a narrow phone at text size 2', const Size(320, 640), 2.0),
        ('a wide window', const Size(1600, 1000), 1.0),
      ]) {
        testWidgets('$design fits $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await showFormatted(tester, newDesign: newDesign, size: size);

          final error = tester.takeException();
          if (newDesign) {
            expect(error, isNull);
          } else {
            // The title row of a Legacy message (subject and badges) does
            // not fit 320 px at text size 2, with or without formatting
            // (#147). The body is checked below.
            expect('$error', anyOf('null', contains('overflowed')));
          }
          expect(markers(tester), ['1.', '2.', '3.', '•', '•']);

          // Every line of the body wraps inside it: no text and no list
          // line is wider than the body.
          final body = tester.getRect(find.byType(QuillDeltaViewer));
          final texts = find.descendant(
            of: find.byType(QuillDeltaViewer),
            matching: find.byType(RichText),
          );
          expect(texts, findsWidgets);
          for (final text in texts.evaluate()) {
            final rect = tester.getRect(find.byWidget(text.widget));
            expect(rect.left, greaterThanOrEqualTo(body.left - 0.5));
            expect(rect.right, lessThanOrEqualTo(body.right + 0.5));
          }
          for (final row in tester.renderObjectList<RenderFlex>(find.descendant(
            of: find.byType(QuillDeltaViewer),
            matching: find.byType(Row),
          ))) {
            var width = 0.0;
            row.visitChildren(
                (child) => width += (child as RenderBox).size.width);
            expect(width, lessThanOrEqualTo(row.size.width + 0.5));
          }
        });
      }
    }
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
