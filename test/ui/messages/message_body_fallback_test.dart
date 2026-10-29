import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

const _unsupported =
    'Der Inhalt dieser Nachricht kann in der App nicht angezeigt werden.';
const _partial = 'Einige Inhalte dieser Nachricht (z. B. Bilder) können in '
    'der App nicht angezeigt werden.';
const _empty = 'Diese Nachricht enthält keinen Text.';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  Future<List<String>> pumpMessage(WidgetTester tester, String text) async {
    final replies = <String>[];
    final message = buildMessage(
      id: 981,
      subject: 'Synthetic important subject',
      text: text,
      attachments: [
        buildAttachment(
          messageId: 981,
          type: 'link',
          file: null,
          link: 'https://example.invalid/file',
          originalName: 'Synthetic attachment',
        ),
      ],
    ).rebuild(
      (b) => b
        ..showReply = true
        ..needsResponse = true
        ..archiveMessageEnabled = 1,
    );
    await pumpApp(
      tester,
      store: createStore(),
      home: MessagesPage(
        state: MessagesState(
          (b) => b.messages = ListBuilder<Message>([message]),
        ),
        noInternet: false,
        onOpenFile: (_) {},
        onMarkAsRead: (_) {},
        onArchive: (_) {},
        onReply: (id, response) => replies.add(response),
      ),
    );
    expect(find.text('Synthetic important subject'), findsOneWidget);
    await tester.tap(find.text('Synthetic important subject'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(MessageWidget), findsOneWidget);
    expect(find.text('Synthetic attachment'), findsOneWidget);
    expect(find.text('Archivieren'), findsOneWidget);
    await tester.tap(find.text('Stimme zu'));
    return replies;
  }

  final cases = <String, ({String text, String notice})>{
    'U10 embed-only': (
      text: '{"ops":[{"insert":{"image":"https://example.invalid/x.png"}},'
          '{"insert":"\\n"}]}',
      notice: _unsupported,
    ),
    'malformed JSON': (text: '{"ops":[{"insert":', notice: _unsupported),
    'non-delta JSON': (text: '{"ops":5}', notice: _unsupported),
    'plain text': (text: 'not a delta', notice: _unsupported),
    'empty delta': (text: '{"ops":[]}', notice: _empty),
    'newline-only delta': (text: '{"ops":[{"insert":"\\n"}]}', notice: _empty),
    'empty string': (text: '', notice: _unsupported),
  };
  for (final entry in cases.entries) {
    testWidgets(
        '${entry.key} body keeps the message, attachment and actions visible',
        (tester) async {
      final replies = await pumpMessage(tester, entry.value.text);
      expect(find.text(entry.value.notice), findsOneWidget);
      expect(replies, ['agree']);
    });
  }

  testWidgets('text around an embed is shown with a notice', (tester) async {
    await pumpMessage(
      tester,
      '{"ops":[{"insert":"Synthetic before\\n"},'
      '{"insert":{"image":"https://example.invalid/x.png"}},'
      '{"insert":"Synthetic after\\n"}]}',
    );
    expect(find.textContaining('Synthetic before'), findsOneWidget);
    expect(find.textContaining('Synthetic after'), findsOneWidget);
    expect(find.text(_partial), findsOneWidget);
  });

  testWidgets('an ordinary message shows no notice', (tester) async {
    await pumpMessage(tester, '{"ops":[{"insert":"Synthetic body\\n"}]}');
    expect(find.textContaining('Synthetic body'), findsOneWidget);
    for (final notice in [_unsupported, _partial, _empty]) {
      expect(find.text(notice), findsNothing);
    }
  });
}
