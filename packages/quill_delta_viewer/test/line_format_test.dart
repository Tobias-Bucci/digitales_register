import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';

// #144: the format of the last line, headings, block quotes, numbered lists
// and italic text.

Delta _delta(List<Map<String, Object?>> ops) => Delta.fromJson(ops);

Map<String, Object?> _line(Map<String, Object?> attributes) =>
    {'insert': '\n', 'attributes': attributes};

/// Every piece of text shown, as the spans that carry it.
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

/// The style the text [text] is shown in, merged from the root of its
/// [RichText] down.
TextStyle _styleOf(WidgetTester tester, String text) {
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

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(QuillDeltaViewer)));

/// The list markers, in order.
List<String> _markers(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .whereType<String>()
    .where((data) => data == '•' || RegExp(r'^\d+\.$').hasMatch(data))
    .toList();

void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
  );

  Future<void> show(
    WidgetTester tester,
    List<Map<String, Object?>> ops, {
    ThemeData? withTheme,
  }) {
    return tester.pumpWidget(MaterialApp(
      theme: withTheme ?? theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: QuillDeltaViewer(delta: _delta(ops)),
        ),
      ),
    ));
  }

  group('the last line', () {
    testWidgets('keeps its bullet', (tester) async {
      await show(tester, [
        {'insert': 'Bitte mitbringen:\n'},
        {'insert': 'Turnschuhe'},
        _line({'list': 'bullet'}),
        {'insert': 'Trinkflasche'},
        _line({'list': 'bullet'}),
      ]);

      expect(_markers(tester), ['•', '•']);
      final row = find.ancestor(
        of: find.textContaining('Trinkflasche', findRichText: true),
        matching: find.byType(Row),
      );
      expect(
          find.descendant(of: row, matching: find.text('•')), findsOneWidget);
    });

    testWidgets('keeps its number', (tester) async {
      await show(tester, [
        {'insert': 'Ablauf'},
        _line({'list': 'ordered'}),
        {'insert': 'Abgabe'},
        _line({'list': 'ordered'}),
      ]);

      expect(_markers(tester), ['1.', '2.']);
    });

    testWidgets('keeps its heading and block quote', (tester) async {
      await show(tester, [
        {'insert': 'Zitat'},
        _line({'blockquote': true}),
        {'insert': 'Ende'},
        _line({'header': 2}),
      ]);

      expect(find.bySemanticsLabel('Ende'), findsOneWidget);
      expect(_styleOf(tester, 'Ende').fontSize,
          _theme(tester).textTheme.titleMedium!.fontSize);
      expect(_styleOf(tester, 'Zitat').color,
          _theme(tester).colorScheme.onSurfaceVariant);
    });

    testWidgets('keeps the format of its text', (tester) async {
      await show(tester, [
        {
          'insert': 'Fett am Ende',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ]);

      expect(_styleOf(tester, 'Fett am Ende').fontWeight, FontWeight.bold);
    });

    testWidgets('an empty last line adds nothing', (tester) async {
      await show(tester, [
        {'insert': 'Hallo\n'},
      ]);
      final oneLine = tester.getSize(find.byType(QuillDeltaViewer));

      await show(tester, [
        {'insert': 'Hallo\n\n'},
      ]);

      expect(tester.getSize(find.byType(QuillDeltaViewer)), oneLine);
      expect(_spans(tester).map((span) => span.text).join(), 'Hallo');
    });

    testWidgets('an empty line between lines stays', (tester) async {
      await show(tester, [
        {'insert': 'Hallo\n'},
      ]);
      final oneLine = tester.getSize(find.byType(QuillDeltaViewer)).height;

      await show(tester, [
        {'insert': 'Hallo\n\nTschüss\n'},
      ]);

      expect(
        tester.getSize(find.byType(QuillDeltaViewer)).height,
        moreOrLessEquals(oneLine * 3, epsilon: 1),
      );
    });
  });

  group('a numbered list', () {
    testWidgets('counts 1, 2, 3 and starts again after a plain line',
        (tester) async {
      await show(tester, [
        {'insert': 'Erstens'},
        _line({'list': 'ordered'}),
        {'insert': 'Zweitens'},
        _line({'list': 'ordered'}),
        {'insert': 'Drittens'},
        _line({'list': 'ordered'}),
        {'insert': 'Zwischentext\n'},
        {'insert': 'Neu eins'},
        _line({'list': 'ordered'}),
        {'insert': 'Neu zwei'},
        _line({'list': 'ordered'}),
        {'insert': 'Schluss\n'},
      ]);

      expect(_markers(tester), ['1.', '2.', '3.', '1.', '2.']);
    });

    testWidgets('starts again after a bullet list', (tester) async {
      await show(tester, [
        {'insert': 'Eins'},
        _line({'list': 'ordered'}),
        {'insert': 'Punkt'},
        _line({'list': 'bullet'}),
        {'insert': 'Wieder eins'},
        _line({'list': 'ordered'}),
      ]);

      expect(_markers(tester), ['1.', '•', '1.']);
    });

    testWidgets('a number is next to its line', (tester) async {
      await show(tester, [
        {'insert': 'Eins'},
        _line({'list': 'ordered'}),
        {'insert': 'Zwei'},
        _line({'list': 'ordered'}),
      ]);

      final row = find.ancestor(
        of: find.textContaining('Zwei', findRichText: true),
        matching: find.byType(Row),
      );
      expect(
          find.descendant(of: row, matching: find.text('2.')), findsOneWidget);
    });
  });

  group('a heading', () {
    for (final level in [1, 2, 3]) {
      testWidgets('of level $level uses the theme title size', (tester) async {
        await show(tester, [
          {'insert': 'Überschrift $level'},
          _line({'header': level}),
          {'insert': 'Text darunter\n'},
        ]);

        final textTheme = _theme(tester).textTheme;
        final title = [
          textTheme.titleLarge!,
          textTheme.titleMedium!,
          textTheme.titleSmall!,
        ][level - 1];
        final heading = _styleOf(tester, 'Überschrift $level');
        expect(heading.fontSize, isNotNull);
        expect(heading.fontSize, title.fontSize);
        expect(heading.fontWeight, FontWeight.w600);
        final body = _styleOf(tester, 'Text darunter');
        expect(body.fontSize, textTheme.bodyMedium!.fontSize);
        expect(body.fontWeight, isNot(FontWeight.w600));
      });
    }

    testWidgets('is a header for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, [
        {'insert': 'Elternsprechtag'},
        _line({'header': 1}),
        {'insert': 'Der Text\n'},
      ]);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Elternsprechtag')),
        isSemantics(isHeader: true),
      );
      semantics.dispose();
    });
  });

  group('a block quote', () {
    testWidgets('has a border at the start and a muted color', (tester) async {
      await show(tester, [
        {'insert': 'Vorher\n'},
        {'insert': 'Zitierter Satz'},
        _line({'blockquote': true}),
        {'insert': 'Nachher\n'},
      ]);

      final box = tester.widget<DecoratedBox>(find
          .ancestor(
            of: find.textContaining('Zitierter Satz', findRichText: true),
            matching: find.byType(DecoratedBox),
          )
          .first);
      final border = (box.decoration as BoxDecoration).border! as Border;
      expect(border.left.color, _theme(tester).colorScheme.outlineVariant);
      expect(border.left.width, greaterThan(0));
      expect(_styleOf(tester, 'Zitierter Satz').color,
          _theme(tester).colorScheme.onSurfaceVariant);
      expect(_styleOf(tester, 'Nachher').color,
          isNot(theme.colorScheme.onSurfaceVariant));
    });
  });

  group('italic text', () {
    for (final name in ['italic', 'italics']) {
      testWidgets('is shown for "$name"', (tester) async {
        await show(tester, [
          {
            'insert': 'schräg',
            'attributes': {name: true},
          },
          {'insert': ' gerade\n'},
        ]);

        expect(_styleOf(tester, 'schräg').fontStyle, FontStyle.italic);
        expect(_styleOf(tester, ' gerade').fontStyle, isNull);
      });
    }
  });

  testWidgets('a link inside a heading, a quote and a list keeps working',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: QuillDeltaViewer(
          onLinkTap: tapped.add,
          delta: _delta([
            {
              'insert': 'h',
              'attributes': {'link': 'https://h.example'},
            },
            _line({'header': 1}),
            {
              'insert': 'q',
              'attributes': {'link': 'https://q.example'},
            },
            _line({'blockquote': true}),
            {
              'insert': 'o',
              'attributes': {'link': 'https://o.example', 'bold': true},
            },
            _line({'list': 'ordered'}),
          ]),
        ),
      ),
    ));

    final links =
        _spans(tester).where((span) => span.recognizer != null).toList();
    expect(links.map((span) => span.text), ['h', 'q', 'o']);
    for (final link in links) {
      expect(link.style?.color, theme.colorScheme.primary);
      (link.recognizer! as dynamic).onTap!();
    }
    expect(tapped,
        ['https://h.example', 'https://q.example', 'https://o.example']);
  });

  testWidgets('a long formatted message fits a narrow screen at large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await show(tester, [
      for (var i = 0; i < 20; i++) ...[
        {'insert': 'Abschnitt $i mit einer recht langen Überschrift'},
        _line({'header': 1 + i % 3}),
        {'insert': 'Ein Punkt mit sehr viel Text, der umbrechen muss $i'},
        _line({'list': i.isEven ? 'ordered' : 'bullet'}),
        {'insert': 'Ein Zitat, das ebenfalls umbrechen muss, Nr. $i'},
        _line({'blockquote': true}),
      ],
    ]);

    expect(tester.takeException(), isNull);
  });
}
