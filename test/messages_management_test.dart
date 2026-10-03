import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart' show wrapper;
import 'package:dr/serializers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

Map<String, Object?> messagePayload(int id) => {
      'id': id,
      'subject': 'Mitteilung $id',
      'text': '{"ops":[{"insert":"Inhalt\\n"}]}',
      'timeSent': '2026-09-30 11:09:53',
      'fromName': 'Absender',
      'recipientString': 'Empfänger',
      'archiveMessageEnabled': 1,
      'label_all': true,
    };

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  test('parses received, nested sent and archived server messages', () async {
    final store = createStore();
    await store.actions.messagesActions.loaded([
      {
        ...messagePayload(1),
        'label_incoming': true,
        'label_outgoing': false,
        'label_archived': false,
      },
      {
        'message': {
          ...messagePayload(2),
          'label_incoming': false,
          'label_outgoing': true,
          'label_archived': false,
        },
        'replies': [],
        'userMessage': null,
      },
      {
        ...messagePayload(3),
        'label_incoming': false,
        'label_outgoing': false,
        'label_archived': true,
        'archiveMessageEnabled': 2,
        'archived': 0,
        'rarchived': 1,
      },
      {
        ...messagePayload(4),
        'label_archived': false,
        'archived': 0,
        'rarchived': 1
      },
    ]);

    final messages = store.state.messagesState.messages;
    expect(messages, hasLength(4));
    expect(messages[0].incoming, isTrue);
    expect(messages[0].isNew, isTrue);
    expect(messages[0].canArchive, isTrue);
    expect(messages[1].outgoing, isTrue);
    expect(messages[1].incoming, isFalse);
    expect(messages[1].isNew, isFalse);
    expect(messages[2].archived, isTrue);
    expect(messages[2].canArchive, isFalse);
    expect(messages[2].canUnarchive, isTrue);
    expect(messages[3].archived, isTrue);
  });

  test('folder flags persist and older saved messages still deserialize', () {
    final message = buildMessage().rebuild((b) => b
      ..incoming = false
      ..outgoing = true
      ..archived = true
      ..archiveMessageEnabled = 1
      ..archiving = true);
    final json = (serializers.serializeWith(Message.serializer, message)!
            as Iterable<Object?>)
        .toList();
    final restored = serializers.deserializeWith(Message.serializer, json)!;
    expect(restored.outgoing, isTrue);
    expect(restored.archived, isTrue);
    expect(restored.archiving, isFalse);

    const newFields = {
      'incoming',
      'outgoing',
      'archived',
      'labelAll',
      'archiveMessageEnabled'
    };
    final oldJson = <Object?>[
      for (var i = 0; i < json.length; i += 2)
        if (!newFields.contains(json[i])) ...[json[i], json[i + 1]],
    ];
    final old = serializers.deserializeWith(Message.serializer, oldJson)!;
    expect(old.incoming, isTrue);
    expect(old.outgoing, isFalse);
    expect(old.archived, isFalse);
    expect(old.labelAll, isTrue);
    expect(old.canArchive, isFalse);
  });

  test('archive waits for the server and prevents duplicate requests',
      () async {
    final mock = MockWrapper();
    wrapper = mock;
    final response = Completer<Object?>();
    when(() => mock.send('api/message/getMyMessages'))
        .thenAnswer((_) async => null);
    when(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 1},
        acceptEmptyResponse: true)).thenAnswer((_) => response.future);
    final store = createStore(
      initialState:
          AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                buildMessage().rebuild((b) => b..archiveMessageEnabled = 1),
              ])),
      withMiddleware: true,
    );

    final pending = store.actions.messagesActions.archiveMessage(25);
    await Future<void>.delayed(Duration.zero);
    expect(store.state.messagesState.messages.single.archiving, isTrue);
    expect(store.state.messagesState.messages.single.archived, isFalse);
    await store.actions.messagesActions.archiveMessage(25);

    response.complete({'success': true});
    await pending;
    expect(store.state.messagesState.messages.single.archived, isTrue);
    expect(store.state.messagesState.messages.single.archiving, isFalse);
    verify(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 1},
        acceptEmptyResponse: true)).called(1);
  });

  for (final response in [
    true,
    '',
    {},
    {'error': false},
    {'error': 0}
  ]) {
    test('archive accepts successful acknowledgements: $response', () async {
      final mock = MockWrapper();
      wrapper = mock;
      when(() => mock.send('api/message/archiveMessage',
          args: {'messageId': 25, 'archiveType': 1},
          acceptEmptyResponse: true)).thenAnswer((_) async => response);
      when(() => mock.send('api/message/getMyMessages'))
          .thenAnswer((_) async => [
                {
                  ...messagePayload(25),
                  'label_incoming': false,
                  'label_archived': true,
                  'rarchived': 1,
                  'archiveMessageEnabled': 2,
                }
              ]);
      final store = createStore(
        initialState:
            AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                  buildMessage().rebuild((b) => b..archiveMessageEnabled = 1),
                ])),
        withMiddleware: true,
      );
      await store.actions.messagesActions.archiveMessage(25);
      expect(store.state.messagesState.messages.single.archived, isTrue);
      expect(store.state.messagesState.messages.single.canUnarchive, isTrue);
      verify(() => mock.send('api/message/getMyMessages')).called(1);
    });
  }

  for (final outgoing in [false, true]) {
    test('unarchive uses type 2 and restores the original folder: $outgoing',
        () async {
      final mock = MockWrapper();
      wrapper = mock;
      when(() => mock.send('api/message/archiveMessage',
          args: {'messageId': 25, 'archiveType': 2},
          acceptEmptyResponse: true)).thenAnswer((_) async => {'error': false});
      when(() => mock.send('api/message/getMyMessages'))
          .thenAnswer((_) async => [
                {
                  ...messagePayload(25),
                  'label_incoming': !outgoing,
                  'label_outgoing': outgoing,
                  'label_archived': false,
                  'rarchived': 0,
                }
              ]);
      final store = createStore(
        initialState:
            AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                  buildMessage().rebuild((b) => b
                    ..incoming = false
                    ..archived = true
                    ..archiveMessageEnabled = 2),
                ])),
        withMiddleware: true,
      );
      await store.actions.messagesActions.archiveMessage(25);
      final restored = store.state.messagesState.messages.single;
      expect(restored.archived, isFalse);
      expect(restored.incoming, !outgoing);
      expect(restored.outgoing, outgoing);
      expect(restored.archiving, isFalse);
      verify(() => mock.send('api/message/archiveMessage',
          args: {'messageId': 25, 'archiveType': 2},
          acceptEmptyResponse: true)).called(1);
    });
  }

  for (final response in [
    null,
    false,
    {'success': false},
    {'error': 'denied'}
  ]) {
    test('failed archive keeps the message and allows retry: $response',
        () async {
      final mock = MockWrapper();
      wrapper = mock;
      when(() => mock.send('api/message/archiveMessage',
          args: {'messageId': 25, 'archiveType': 1},
          acceptEmptyResponse: true)).thenAnswer((_) async => response);
      final store = createStore(
        initialState:
            AppState((b) => b.messagesState.messages = ListBuilder<Message>([
                  buildMessage().rebuild((b) => b..archiveMessageEnabled = 1),
                ])),
        withMiddleware: true,
      );

      await store.actions.messagesActions.archiveMessage(25);

      expect(store.state.messagesState.messages.single.archived, isFalse);
      expect(store.state.messagesState.messages.single.archiving, isFalse);
      expect(store.state.messagesState.messages.single.canArchive, isTrue);
    });
  }

  test('offline and disallowed archive actions do not contact the server',
      () async {
    final mock = MockWrapper();
    wrapper = mock;
    final store = createStore(
      initialState: AppState((b) => b
        ..noInternet = true
        ..messagesState.messages = ListBuilder<Message>([
          buildMessage().rebuild((b) => b..archiveMessageEnabled = 1),
        ])),
      withMiddleware: true,
    );
    await store.actions.messagesActions.archiveMessage(25);
    expect(store.state.messagesState.messages.single.archiving, isFalse);

    final disallowedStore = createStore(
      initialState: AppState((b) =>
          b.messagesState.messages = ListBuilder<Message>([buildMessage()])),
      withMiddleware: true,
    );
    await disallowedStore.actions.messagesActions.archiveMessage(25);
    verifyNever(() => mock.send('api/message/archiveMessage',
        args: {'messageId': 25, 'archiveType': 1}, acceptEmptyResponse: true));
  });
}
