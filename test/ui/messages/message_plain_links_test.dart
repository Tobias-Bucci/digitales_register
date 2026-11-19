import 'dart:convert';

import 'package:dr/external_links.dart';
import 'package:dr/ui/messages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

// #143: web addresses typed into the text of a message open as well, through
// the same check as every other link (#141), and keep the formatting of the
// text around them.

/// A message body as the server sends it.
String _body(List<Map<String, Object?>> ops) => jsonEncode({'ops': ops});

/// Every piece of text the message body shows, in order.
List<TextSpan> _spans(WidgetTester tester) {
  final spans = <TextSpan>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
        spans.add(span);
      }
      return true;
    });
  }
  return spans;
}

List<TextSpan> _links(WidgetTester tester) =>
    _spans(tester).where((span) => span.recognizer != null).toList();

String _shownText(WidgetTester tester) =>
    _spans(tester).map((span) => span.text).join();

void main() {
  late List<Uri> launched;
  var launches = true;

  setUp(() async {
    await bootstrapTestEnvironment();
    launched = [];
    launches = true;
    externalLinkLauncherOverride = (uri) async {
      launched.add(uri);
      return launches;
    };
  });
  tearDown(() async {
    externalLinkLauncherOverride = null;
    await resetTestState();
  });

  Future<void> show(
    WidgetTester tester,
    List<Map<String, Object?>> ops, {
    int id = 25,
  }) {
    return pumpApp(
      tester,
      store: createStore(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: renderMessage(buildMessage(id: id, text: _body(ops))),
        ),
      ),
    );
  }

  /// Taps every link shown, in order, and returns what opened.
  Future<List<Uri>> tapAll(WidgetTester tester) async {
    for (final link in _links(tester)) {
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
    }
    return launched;
  }

  group('a plain address in the text', () {
    for (final (name, text, link, opens) in [
      (
        'at the end of a sentence',
        'Die Anmeldung ist unter https://example.org/form.\n',
        'https://example.org/form',
        'https://example.org/form',
      ),
      for (final mark in ['!', '?', ',', ':', ';'])
        (
          'before "$mark"',
          'Siehe https://example.org/a$mark Danke\n',
          'https://example.org/a',
          'https://example.org/a',
        ),
      (
        'in brackets',
        'Alle Infos (www.school.example/info) bitte lesen\n',
        'www.school.example/info',
        'https://www.school.example/info',
      ),
      (
        'in quotes',
        'Bitte "https://example.org/x" öffnen\n',
        'https://example.org/x',
        'https://example.org/x',
      ),
      (
        'in typographic quotes',
        'Bitte „https://example.org/x“ öffnen\n',
        'https://example.org/x',
        'https://example.org/x',
      ),
      (
        'in guillemets',
        'Bitte «www.example.org/y» öffnen\n',
        'www.example.org/y',
        'https://www.example.org/y',
      ),
      (
        'without a scheme',
        'Formular: www.school.example/info\n',
        'www.school.example/info',
        'https://www.school.example/info',
      ),
      (
        'in capitals',
        'SIEHE HTTPS://EXAMPLE.ORG/INFO\n',
        'HTTPS://EXAMPLE.ORG/INFO',
        'https://example.org/INFO',
      ),
      (
        'with a query and an anchor',
        'Hier https://example.org/a?b=1&c=zwei#teil-2 klicken\n',
        'https://example.org/a?b=1&c=zwei#teil-2',
        'https://example.org/a?b=1&c=zwei#teil-2',
      ),
      (
        'with international characters',
        'Siehe https://example.org/straße-über und mehr\n',
        'https://example.org/straße-über',
        'https://example.org/straße-über',
      ),
    ]) {
      testWidgets('$name opens', (tester) async {
        await show(tester, [
          {'insert': text},
        ]);

        expect(_links(tester).map((span) => span.text), [link]);
        // Nothing of the text is lost or moved.
        expect(_shownText(tester), text.trimRight());
        expect(await tapAll(tester), [Uri.parse(opens)]);
      });
    }

    testWidgets('two addresses in one op both open', (tester) async {
      await show(tester, [
        {
          'insert': 'Erst https://example.org/a lesen, dann '
              'www.example.org/b ausfüllen.\n',
        },
      ]);

      expect(_links(tester).map((span) => span.text),
          ['https://example.org/a', 'www.example.org/b']);
      expect(await tapAll(tester), [
        Uri.parse('https://example.org/a'),
        Uri.parse('https://www.example.org/b'),
      ]);
    });

    testWidgets('an address that touches a line break ends at it',
        (tester) async {
      await show(tester, [
        {'insert': 'Link:\nhttps://example.org/a\nNächste Zeile\n'},
      ]);

      expect(
          _links(tester).map((span) => span.text), ['https://example.org/a']);
      expect(find.textContaining('Nächste Zeile', findRichText: true),
          findsOneWidget);
      expect(await tapAll(tester), [Uri.parse('https://example.org/a')]);
    });

    testWidgets('an address across two ops is one link in both formats',
        (tester) async {
      // An editor can format part of an address; it stays one link, and each
      // part keeps its own formatting.
      await show(tester, [
        {
          'insert': 'www.example.org/an',
          'attributes': {'bold': true},
        },
        {'insert': 'meldung bis Freitag\n'},
      ]);

      final links = _links(tester);
      expect(links.map((span) => span.text), ['www.example.org/an', 'meldung']);
      expect(links.first.style?.fontWeight, FontWeight.bold);
      expect(links.last.style?.fontWeight, isNull);
      expect(await tapAll(tester), [
        Uri.parse('https://www.example.org/anmeldung'),
        Uri.parse('https://www.example.org/anmeldung'),
      ]);
    });
  });

  group('the formatting', () {
    testWidgets('of an address inside formatted text is kept', (tester) async {
      await show(tester, [
        {
          'insert': 'Wichtig: https://example.org/frist beachten',
          'attributes': {
            'bold': true,
            'italics': true,
            'underline': true,
            'strike': true,
          },
        },
        {'insert': '\n'},
      ]);

      final spans = _spans(tester);
      expect(spans.map((span) => span.text),
          ['Wichtig: ', 'https://example.org/frist', ' beachten']);
      for (final span in spans) {
        expect(span.style?.fontWeight, FontWeight.bold, reason: span.text);
        expect(span.style?.fontStyle, FontStyle.italic, reason: span.text);
        expect(span.style?.decoration?.contains(TextDecoration.lineThrough),
            isTrue,
            reason: span.text);
        expect(
            span.style?.decoration?.contains(TextDecoration.underline), isTrue,
            reason: span.text);
      }
      expect(spans[1].recognizer, isNotNull);
      expect(spans[0].recognizer, isNull);
      expect(spans[2].recognizer, isNull);
    });

    testWidgets('of a list line is kept, the last one too (#144)',
        (tester) async {
      await show(tester, [
        {'insert': 'Einleitung\n'},
        {'insert': 'Formular: www.example.org/f'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': 'Ohne Link'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]);

      expect(find.text('•'), findsNWidgets(2));
      expect(_links(tester).map((span) => span.text), ['www.example.org/f']);
      // The link is in the first list line, next to its bullet.
      final row = find.ancestor(
        of: find.textContaining('Formular', findRichText: true),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: row, matching: find.text('•')),
        findsOneWidget,
      );
      expect(await tapAll(tester), [Uri.parse('https://www.example.org/f')]);
    });

    for (final attributes in <Map<String, Object>>[
      {'header': 2},
      {'blockquote': true},
    ]) {
      testWidgets('of a ${attributes.keys.single} line is kept',
          (tester) async {
        await show(tester, [
          {'insert': 'Vor dem Link '},
          {'insert': '\n', 'attributes': attributes},
        ]);
        final plainWidgets =
            tester.allWidgets.map((w) => w.runtimeType).toList();

        await show(
          tester,
          [
            {'insert': 'Vor dem Link https://example.org/q'},
            {'insert': '\n', 'attributes': attributes},
          ],
          id: 26,
        );

        // The same widgets, only the address became a link.
        expect(tester.allWidgets.map((w) => w.runtimeType), plainWidgets);
        expect(
            _links(tester).map((span) => span.text), ['https://example.org/q']);
      });
    }

    testWidgets('a link looks like one, in the colors of the theme',
        (tester) async {
      await show(tester, [
        {'insert': 'Siehe https://example.org/a\n'},
      ]);

      final link = _links(tester).single;
      final context = tester.element(find.byType(RichText).first);
      expect(link.style?.color, Theme.of(context).colorScheme.primary);
      expect(
          link.style?.decoration?.contains(TextDecoration.underline), isTrue);
      final text = _spans(tester).first;
      expect(text.style?.color, isNull);
      expect(text.style?.decoration?.contains(TextDecoration.underline),
          isNot(isTrue));
    });

    testWidgets('a long text without an address is shown as it is',
        (tester) async {
      final long = List.filled(4000, 'Ein Satz ohne Adresse, Nr. 3.').join(' ');
      await show(tester, [
        {
          'insert': long,
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);

      final spans = _spans(tester);
      expect(spans, hasLength(1));
      expect(spans.single.text, long);
      expect(spans.single.recognizer, isNull);
    });
  });

  group('what does not open', () {
    for (final text in [
      'javascript:alert(1)',
      'file:///data/user/0/x',
      'data:text/html,<b>x</b>',
      'intent://scan/#Intent;scheme=zxing;end',
      'ftp://example.org/x',
      'https://school.it@example.org/x',
      'sekretariat@school.example',
      'max@www.school.example',
    ]) {
      testWidgets('"$text" stays text', (tester) async {
        await show(tester, [
          {'insert': 'Siehe $text bitte\n'},
        ]);

        expect(_links(tester), isEmpty);
        expect(_shownText(tester), 'Siehe $text bitte');
      });
    }

    testWidgets('an explicit link keeps its target', (tester) async {
      await show(tester, [
        {
          'insert': 'www.example.org/sichtbar',
          'attributes': {'link': 'https://example.com/ziel'},
        },
        {'insert': ' und www.example.org/b\n'},
      ]);

      expect(_links(tester).map((span) => span.text),
          ['www.example.org/sichtbar', 'www.example.org/b']);
      expect(await tapAll(tester), [
        Uri.parse('https://example.com/ziel'),
        Uri.parse('https://www.example.org/b'),
      ]);
    });
  });

  group('a tap', () {
    testWidgets('shows the message when the link cannot open', (tester) async {
      launches = false;
      await show(tester, [
        {'insert': 'Siehe https://example.org/a\n'},
      ]);

      await tapAll(tester);
      await tester.pump();

      expect(launched, [Uri.parse('https://example.org/a')]);
      expect(find.text('Dieser Link konnte nicht geöffnet werden'),
          findsOneWidget);
    });

    testWidgets('a screen reader announces the address as a link',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, [
        {'insert': 'Siehe https://example.org/a bitte\n'},
      ]);

      expect(
        find.semantics.byLabel('https://example.org/a').evaluate().single,
        containsSemantics(label: 'https://example.org/a', isLink: true),
      );
      semantics.dispose();
    });
  });

  group('the message', () {
    testWidgets('shows new links when its text changes', (tester) async {
      await show(tester, [
        {'insert': 'Alt: https://example.org/alt\n'},
      ]);
      expect(_links(tester).single.text, 'https://example.org/alt');

      // The same message id with a new text, as after a reload.
      await show(tester, [
        {'insert': 'Neu: https://example.org/neu\n'},
      ]);
      expect(_links(tester).single.text, 'https://example.org/neu');
      expect(await tapAll(tester), [Uri.parse('https://example.org/neu')]);
    });

    testWidgets('disposes the tap recognizers of its links', (tester) async {
      final created = <Object>{};
      final disposed = <Object>{};
      void track(ObjectEvent event) {
        if (event.object is! TapGestureRecognizer) return;
        if (event is ObjectCreated) created.add(event.object);
        if (event is ObjectDisposed) disposed.add(event.object);
      }

      FlutterMemoryAllocations.instance.addListener(track);
      addTearDown(
          () => FlutterMemoryAllocations.instance.removeListener(track));

      final ops = [
        {'insert': 'Siehe https://example.org/a und '},
        {
          'insert': 'hier',
          'attributes': {'link': 'https://example.org/b'},
        },
        {'insert': '\n'},
      ];
      await show(tester, ops);
      // Rebuilds, as when the theme or the page changes.
      for (var i = 0; i < 3; i++) {
        await show(tester, ops);
      }
      expect(_links(tester), isNotEmpty);

      await tester.pumpWidget(const SizedBox());

      expect(created, isNotEmpty);
      expect(disposed, created);
    });
  });
}
