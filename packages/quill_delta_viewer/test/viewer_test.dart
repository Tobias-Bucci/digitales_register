import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';

Delta _delta(List<Map<String, Object?>> ops) => Delta.fromJson(ops);

List<TextSpan> _links(WidgetTester tester) {
  final links = <TextSpan>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) links.add(span);
      return true;
    });
  }
  return links;
}

void main() {
  Widget app(Delta delta,
          {void Function(String)? onLinkTap, ThemeData? theme}) =>
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: QuillDeltaViewer(delta: delta, onLinkTap: onLinkTap),
        ),
      );

  final withLinks = _delta([
    {'insert': 'Text '},
    {
      'insert': 'a',
      'attributes': {'link': 'https://a.example'},
    },
    {'insert': ' und '},
    {
      'insert': 'b',
      'attributes': {'link': 'https://b.example', 'bold': true},
    },
    {'insert': '\n'},
  ]);

  testWidgets('a tapped link goes to onLinkTap', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(app(withLinks, onLinkTap: tapped.add));

    for (final link in _links(tester)) {
      (link.recognizer! as TapGestureRecognizer).onTap!();
    }

    expect(tapped, ['https://a.example', 'https://b.example']);
  });

  testWidgets('a link is underlined in the primary color', (tester) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    );
    await tester.pumpWidget(app(withLinks, theme: theme));

    for (final link in _links(tester)) {
      expect(link.style?.color, theme.colorScheme.primary);
      expect(
          link.style?.decoration?.contains(TextDecoration.underline), isTrue);
    }
    expect(_links(tester).last.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('the tap recognizers are disposed, and not made on every build',
      (tester) async {
    final created = <Object>{};
    final disposed = <Object>{};
    void track(ObjectEvent event) {
      if (event.object is! TapGestureRecognizer) return;
      if (event is ObjectCreated) created.add(event.object);
      if (event is ObjectDisposed) disposed.add(event.object);
    }

    FlutterMemoryAllocations.instance.addListener(track);
    addTearDown(() => FlutterMemoryAllocations.instance.removeListener(track));

    await tester.pumpWidget(app(withLinks));
    expect(created, hasLength(2));

    // The same text again: nothing new.
    await tester.pumpWidget(app(Delta.from(withLinks)));
    expect(created, hasLength(2));
    expect(disposed, isEmpty);

    // Another theme, animated: new colors, the same recognizers.
    final tapped = <String>[];
    await tester.pumpWidget(
      app(withLinks, theme: ThemeData.dark(), onLinkTap: tapped.add),
    );
    await tester.pumpAndSettle();
    expect(created, hasLength(2));
    expect(disposed, isEmpty);
    expect(_links(tester).first.style?.color,
        ThemeData.dark().colorScheme.primary);
    for (final link in _links(tester)) {
      (link.recognizer! as TapGestureRecognizer).onTap!();
    }
    expect(tapped, ['https://a.example', 'https://b.example']);

    // Another text: the old recognizers go.
    await tester.pumpWidget(app(_delta([
      {
        'insert': 'c',
        'attributes': {'link': 'https://c.example'},
      },
      {'insert': '\n'},
    ])));
    expect(created, hasLength(3));
    expect(disposed, hasLength(2));

    await tester.pumpWidget(const SizedBox());
    expect(disposed, created);
  });
}
