import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

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
