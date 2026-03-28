import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/messages_container.dart';
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

  testWidgets('expanding a message reveals its content and open attachment action',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.messagesState.messages = ListBuilder<Message>(<Message>[
          buildMessage(
            attachments: <MessageAttachmentFile>[
              buildAttachment(fileAvailable: false),
            ],
          ),
        ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: MessagesPageContainer(),
    );

    expect(find.text('Betreff'), findsOneWidget);

    await tester.tap(find.text('Betreff'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.byType(MessageWidget), findsOneWidget);
    expect(find.textContaining('Sehr geehrte Eltern'), findsOneWidget);
    expect(find.text('Anhang:'), findsOneWidget);
    expect(find.text('Öffnen'), findsOneWidget);
  });

  testWidgets('shows a linear progress indicator while an attachment downloads',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.messagesState.messages = ListBuilder<Message>(<Message>[
          buildMessage(
            attachments: <MessageAttachmentFile>[
              buildAttachment(downloading: true),
            ],
          ),
        ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: MessagesPageContainer(),
    );

    await tester.tap(find.text('Betreff'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the open action for already downloaded attachments',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.messagesState.messages = ListBuilder<Message>(<Message>[
          buildMessage(
            attachments: <MessageAttachmentFile>[
              buildAttachment(fileAvailable: true),
            ],
          ),
        ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: MessagesPageContainer(),
    );

    await tester.tap(find.text('Betreff'));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 400));

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Öffnen'), findsOneWidget);
  });
}
