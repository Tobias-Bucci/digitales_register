import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart' show wrapper;
import 'package:dr/ui/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  MessagesPage page(MessagesState state, {void Function(Message)? onRead}) =>
      MessagesPage(
        state: state,
        noInternet: false,
        onOpenFile: (_) {},
        onMarkAsRead: onRead ?? (_) {},
        onArchive: (_) {},
        onReply: (id, response) {},
      );

  testWidgets('recipient archive fields show the message after scrolling inbox',
      (tester) async {
    final store = createStore();
    await store.actions.messagesActions.loaded([
      for (var id = 100; id < 125; id++)
        {
          'id': id,
          'subject': 'Empfangen $id',
          'text': '{"ops":[{"insert":"Nachricht\\n"}]}',
          'timeSent': '2026-09-30 11:09:53',
          'recipientString': 'Schüler/innen',
          'fromName': 'Absender',
          'label_incoming': true,
          'label_outgoing': false,
          'label_archived': false,
          'label_all': true,
          'archived': 0,
          'rarchived': 0,
          'archiveMessageEnabled': 1,
        },
      {
        'id': 1,
        'subject': 'Mensa-App und Mensazugang',
        'text': '{"ops":[{"insert":"Liebe Eltern,\\n"}, '
            '{"attributes":{"bold":true},"insert":"Montag, 7. September"}, '
            '{"insert":"\\n"}, '
            '{"attributes":{"underline":true,"bold":true},'
            '"insert":"Besonders wichtig:"}, '
            '{"attributes":{"link":"mailto:office@example.com"},'
            '"insert":"Kontakt"},{"insert":"\\n"}]}',
        'timeSent': '2026-08-27 11:27:26',
        'timeRead': '2026-08-28 07:44:29',
        'recipientString': 'Mensabesuch Schüler/innen',
        'fromName': 'Mensa',
        'label_incoming': false,
        'label_outgoing': false,
        'label_archived': true,
        'label_all': true,
        'archived': 0,
        'rarchived': 1,
        'archiveMessageEnabled': 2,
        'submissions': [],
      },
    ]);
    await pumpApp(tester, store: store, home: page(store.state.messagesState));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await settleFor(tester);
    await tester.tap(find.text('Archiviert'));
    await settleFor(tester);
    expect(find.text('Mensa-App und Mensazugang'), findsOneWidget);
    await tester.tap(find.text('Mensa-App und Mensazugang'));
    await settleFor(tester);
    expect(find.text('Archivierung aufheben'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final folderMessages = <Message>[
    buildMessage(id: 1, subject: 'Empfangene Nachricht'),
    buildMessage(id: 2, subject: 'Gesendete Nachricht').rebuild((b) => b
      ..incoming = false
      ..outgoing = true),
    buildMessage(id: 3, subject: 'Archivierte Nachricht').rebuild((b) => b
      ..incoming = false
      ..archived = true),
  ];

  testWidgets(
      'four folders filter messages and sent messages are not marked read',
      (tester) async {
    final markedRead = <int>[];
    await pumpApp(tester,
        store: createStore(),
        home: page(
            MessagesState((b) => b.messages = ListBuilder(folderMessages)),
            onRead: (m) => markedRead.add(m.id)));
    expect(find.text('Empfangene Nachricht'), findsOneWidget);
    expect(find.text('Gesendete Nachricht'), findsNothing);
    expect(find.text('Archivierte Nachricht'), findsNothing);

    await tester.tap(find.text('Gesendet'));
    await settleFor(tester);
    expect(find.text('Empfangene Nachricht'), findsNothing);
    expect(find.text('Gesendete Nachricht'), findsOneWidget);
    expect(find.text('neu'), findsNothing);
    await tester.tap(find.text('Gesendete Nachricht'));
    await settleFor(tester);
    expect(markedRead, isEmpty);

    await tester.tap(find.text('Archiviert'));
    await settleFor(tester);
    expect(find.text('Archivierte Nachricht'), findsOneWidget);
    expect(find.text('Gesendete Nachricht'), findsNothing);

    await tester.tap(find.text('Alle'));
    await settleFor(tester);
    expect(find.byType(MessageWidget), findsNWidgets(3));
  });

  testWidgets('opening a sent or archived message selects the correct folder',
      (tester) async {
    final state = MessagesState((b) => b
      ..messages = ListBuilder(folderMessages)
      ..showMessage = 2);
    await pumpApp(tester, store: createStore(), home: page(state));
    expect(find.text('Gesendete Nachricht'), findsOneWidget);
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);

    await pumpApp(tester,
        store: createStore(),
        home: page(state.rebuild((b) => b..showMessage = 3)));
    await settleFor(tester);
    expect(find.text('Archivierte Nachricht'), findsOneWidget);
    expect(find.text('Gesendete Nachricht'), findsNothing);
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
  });

  testWidgets('archiving moves a message from received into archive and all',
      (tester) async {
    final mock = MockWrapper();
    wrapper = mock;
    when(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 1},
        acceptEmptyResponse: true)).thenAnswer((_) async => {'success': true});
    when(() => mock.send('api/message/getMyMessages'))
        .thenAnswer((_) async => null);
    when(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 2},
        acceptEmptyResponse: true)).thenAnswer((_) async => {'error': false});
    final store = createStore(
      initialState:
          AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                buildMessage().rebuild((b) => b
                  ..archiveMessageEnabled = 1
                  ..timeRead = b.timeSent),
              ])),
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: MessagesPageContainer());
    await tester.tap(find.text('Betreff'));
    await settleFor(tester);
    await tester.tap(find.text('Archivieren'));
    await settleFor(tester);
    expect(find.text('Betreff'), findsNothing);

    await tester.tap(find.text('Archiviert'));
    await settleFor(tester);
    expect(find.text('Betreff'), findsOneWidget);
    await tester.tap(find.text('Betreff'));
    await settleFor(tester);
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
    expect(find.text('Archivieren'), findsNothing);
    expect(find.text('Archivierung aufheben'), findsOneWidget);

    await tester.tap(find.text('Alle'));
    await settleFor(tester);
    expect(find.text('Betreff'), findsOneWidget);
    await tester.tap(find.text('Archivierung aufheben'));
    await settleFor(tester);
    await tester.tap(find.text('Empfangen'));
    await settleFor(tester);
    expect(find.text('Betreff'), findsOneWidget);
    verify(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 2},
        acceptEmptyResponse: true)).called(1);
  });

  for (final labels in {
    'de': ['Empfangen', 'Gesendet', 'Archiviert', 'Alle'],
    'en': ['Received', 'Sent', 'Archived', 'All'],
    'it': ['Ricevute', 'Inviate', 'Archiviate', 'Tutte'],
    'lld': ['Ressüdes', 'Mendades', 'Archiviades', 'Dütes'],
  }.entries) {
    testWidgets('folders fit a phone screen in ${labels.key}', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpApp(tester,
          store: createStore(
            initialState:
                AppState((b) => b.settingsState.languageCode = labels.key),
          ),
          home: page(MessagesState()));
      await settleFor(tester);
      for (final label in labels.value) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expanding a message shows link attachments', (tester) async {
    await pumpApp(
      tester,
      store: createStore(),
      home: MessagesPage(
        state: MessagesState(
          (b) => b.messages = ListBuilder<Message>(<Message>[
            buildMessage(
              attachments: <MessageAttachmentFile>[
                buildAttachment(
                  type: 'link',
                  file: null,
                  link: 'https://example.com/form',
                  originalName: 'Online-Umfrage',
                ),
              ],
            ),
          ]),
        ),
        noInternet: false,
        onOpenFile: (_) {},
        onMarkAsRead: (_) {},
        onArchive: (_) {},
        onReply: (id, response) {},
      ),
    );

    expect(find.text('Betreff'), findsOneWidget);

    await tester.tap(find.text('Betreff'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.byType(MessageWidget), findsOneWidget);
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
    expect(find.text('Online-Umfrage'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });
}
