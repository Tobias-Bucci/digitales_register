import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart' show wrapper;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);
  testWidgets('failed reply keeps UI buttons and retry shows server success',
      (tester) async {
    final mock = MockWrapper();
    wrapper = mock;
    var succeed = false;
    when(() => mock.send('api/message/markAsRead', args: {'messageId': 25}))
        .thenAnswer((_) async => true);
    when(() => mock.send('api/message/reply',
            args: {
              'messageId': 25,
              'response': {'response': 'agree'},
            },
            acceptEmptyResponse: true))
        .thenAnswer((_) async => succeed ? true : null);
    final message = buildMessage().rebuild((b) => b
      ..showReply = true
      ..needsResponse = true);
    final store = createStore(
        initialState: AppState((b) => b.messagesState
          ..messages = ListBuilder<Message>([message])
          ..showMessage = 25),
        withMiddleware: true);
    await pumpApp(tester, store: store, home: MessagesPageContainer());
    final agree = find.widgetWithText(ElevatedButton, 'Stimme zu');
    await tester.ensureVisible(agree);
    await tester.tap(agree);
    await settleFor(tester);
    expect(agree, findsOneWidget);
    expect(
        find.widgetWithText(ElevatedButton, 'Stimme nicht zu'), findsOneWidget);
    expect(
        find.text(
            'Antwort konnte nicht gesendet werden. Bitte erneut versuchen.'),
        findsOneWidget);
    expect(find.text('Mit "Stimme zu" beantwortet.'), findsNothing);
    succeed = true;
    await tester.tap(agree);
    await settleFor(tester);
    expect(agree, findsNothing);
    expect(find.text('Mit "Stimme zu" beantwortet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final choice in ['agree', 'not_agree']) {
    for (final failure in <Object?>[
      null,
      false,
      [],
      'unexpected',
      {'unexpected': true},
      {'error': 'denied'},
      {'success': false},
      {'success': 0},
      const FormatException('invalid JSON'),
      TimeoutException('timeout'),
      DioException(
          requestOptions: RequestOptions(path: 'reply'),
          type: DioExceptionType.connectionError),
      DioException(
          requestOptions: RequestOptions(path: 'reply'),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: 'reply'), statusCode: 500)),
    ]) {
      test('$choice failure stays retryable: $failure', () async {
        final mock = MockWrapper();
        wrapper = mock;
        var succeed = false;
        when(() => mock.send('api/message/reply',
            args: {
              'messageId': 25,
              'response': {'response': choice},
            },
            acceptEmptyResponse: true)).thenAnswer((_) async {
          if (succeed) return {'success': true};
          if (failure is Exception) throw failure;
          return failure;
        });
        final message = buildMessage().rebuild((b) => b
          ..showReply = true
          ..needsResponse = true);
        final store = createStore(
            initialState: AppState((b) =>
                b.messagesState.messages = ListBuilder<Message>([message])),
            withMiddleware: true);
        var successCount = 0;
        final subscription = store
            .actionStream(MessagesActionsNames.repliedMessage)
            .listen((_) => successCount++);
        addTearDown(subscription.cancel);
        final payload = ReplyMessagePayload(messageId: 25, response: choice);
        await store.actions.messagesActions.replyMessage(payload);
        expect(store.state.messagesState.messages.single, message);
        expect(successCount, 0);
        succeed = true;
        await store.actions.messagesActions.replyMessage(payload);
        expect(store.state.messagesState.messages.single.showReply, false);
        expect(store.state.messagesState.messages.single.needsResponse, false);
        expect(store.state.messagesState.messages.single.badge,
            choice == 'agree' ? 'agree' : 'not_agree');
        expect(successCount, 1);
      });
    }
  }
  for (final acknowledgement in [
    true,
    '',
    {},
    {'error': false},
    {'error': 0},
    {'success': true}
  ]) {
    test('one request and one success for concurrent clicks: $acknowledgement',
        () async {
      final mock = MockWrapper();
      wrapper = mock;
      final response = Completer<Object?>();
      when(() => mock.send('api/message/reply',
          args: {
            'messageId': 25,
            'response': {'response': 'agree'},
          },
          acceptEmptyResponse: true)).thenAnswer((_) => response.future);
      final message = buildMessage().rebuild((b) => b
        ..showReply = true
        ..needsResponse = true);
      final store = createStore(
          initialState: AppState((b) =>
              b.messagesState.messages = ListBuilder<Message>([message])),
          withMiddleware: true);
      var successes = 0;
      final subscription = store
          .actionStream(MessagesActionsNames.repliedMessage)
          .listen((_) => successes++);
      addTearDown(subscription.cancel);
      final payload = ReplyMessagePayload(messageId: 25, response: 'agree');
      final pending = store.actions.messagesActions.replyMessage(payload);
      await Future<void>.delayed(Duration.zero);
      await store.actions.messagesActions.replyMessage(
          ReplyMessagePayload(messageId: 25, response: 'not_agree'));
      expect(store.state.messagesState.messages.single, message);
      response.complete(acknowledgement);
      await pending;
      await store.actions.messagesActions.replyMessage(payload);
      expect(successes, 1);
      verify(() => mock.send('api/message/reply',
          args: {
            'messageId': 25,
            'response': {'response': 'agree'},
          },
          acceptEmptyResponse: true)).called(1);
    });
  }
  test('completion from an old session cannot update another account',
      () async {
    final mock = MockWrapper();
    wrapper = mock;
    final response = Completer<Object?>();
    when(() => mock.send('api/message/reply',
        args: {
          'messageId': 25,
          'response': {'response': 'agree'},
        },
        acceptEmptyResponse: true)).thenAnswer((_) => response.future);
    final message = buildMessage().rebuild((b) => b
      ..showReply = true
      ..needsResponse = true);
    final store = createStore(
        initialState: AppState(
            (b) => b.messagesState.messages = ListBuilder<Message>([message])),
        withMiddleware: true);
    final pending = store.actions.messagesActions
        .replyMessage(ReplyMessagePayload(messageId: 25, response: 'agree'));
    await Future<void>.delayed(Duration.zero);
    wrapper = MockWrapper();
    response.complete(true);
    await pending;
    expect(store.state.messagesState.messages.single, message);
  });
}
