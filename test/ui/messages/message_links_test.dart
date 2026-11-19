import 'dart:convert';

import 'package:dr/external_links.dart';
import 'package:dr/ui/messages.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

// #141: links in messages open through the same check as everywhere else:
// only web addresses, and a failure is shown.
void main() {
  late List<Uri> launched;

  setUp(() async {
    await bootstrapTestEnvironment();
    launched = [];
    externalLinkLauncherOverride = (uri) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() async {
    externalLinkLauncherOverride = null;
    await resetTestState();
  });

  group('a link attachment', () {
    for (final (link, opens) in [
      ('https://example.com/form', Uri.parse('https://example.com/form')),
      ('www.example.com/form', Uri.parse('https://www.example.com/form')),
      ('javascript:alert(1)', null),
      ('file:///data/user/0/x', null),
    ]) {
      test('$link ${opens == null ? 'is refused' : 'opens'}', () async {
        final store = createStore(withMiddleware: true);
        addTearDown(store.dispose);

        await store.actions.messagesActions
            .openFile(buildAttachment(type: 'link', file: null, link: link));

        expect(launched, [if (opens != null) opens]);
      });
    }
  });

  group('a link in the text of a message', () {
    Future<void> tapLink(WidgetTester tester, String link) async {
      final text = jsonEncode({
        'ops': [
          {'insert': 'Hier: '},
          {
            'insert': 'Formular',
            'attributes': {'link': link},
          },
          {'insert': '\n'},
        ],
      });
      await pumpApp(
        tester,
        store: createStore(),
        home: Scaffold(body: renderMessage(buildMessage(text: text))),
      );
      final span = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((rich) => rich.text)
          .expand((root) {
        final spans = <TextSpan>[];
        root.visitChildren((span) {
          if (span is TextSpan && span.text == 'Formular') spans.add(span);
          return true;
        });
        return spans;
      }).single;
      (span.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
    }

    testWidgets('a web address opens', (tester) async {
      await tapLink(tester, 'https://example.com/a');
      expect(launched, [Uri.parse('https://example.com/a')]);
    });

    testWidgets('another scheme is refused', (tester) async {
      await tapLink(tester, 'javascript:alert(1)');
      expect(launched, isEmpty);
    });
  });
}
