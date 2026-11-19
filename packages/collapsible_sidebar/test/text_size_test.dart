import 'dart:io';

import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

const _longWord = 'Pruefungskalenderverwaltungsuebersichtsseite';
const _short = 'Noten';

/// Real Roboto metrics instead of the test font's square glyphs.
Future<void> _loadRoboto(WidgetTester tester) => tester.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT'] ??
          File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      final loader = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        final file = File('$fonts/roboto-$weight.ttf');
        if (file.existsSync()) {
          loader.addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())),
          );
        }
      }
      await loader.load();
    });

Future<void> _pump(
  WidgetTester tester, {
  required double scale,
  bool alwaysExpanded = true,
}) async {
  await _loadRoboto(tester);
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: Row(
          children: [
            CollapsibleSidebar(
              alwaysExpanded: alwaysExpanded,
              iconSize: 26,
              minWidth: 62,
              textStyle: const TextStyle(fontSize: 15, height: 1.5),
              items: [
                CollapsibleItem(
                  text: _short,
                  icon: Icons.auto_graph_outlined,
                  onPressed: () {},
                  isSelected: true,
                ),
                CollapsibleItem(
                  text: _longWord,
                  icon: Icons.school_outlined,
                  onPressed: () {},
                ),
              ],
              body: const SizedBox(),
              titleTooltip: 'title',
              toggleTooltipCollapsed: 'Expand',
              toggleTooltipExpanded: 'Collapse',
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _tile(WidgetTester tester, String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first,
    );

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('a long word without spaces fits at text size $scale',
        (tester) async {
      await _pump(tester, scale: scale);
      expect(tester.takeException(), isNull);

      final label = find.text(_longWord);
      final text = tester.widget<Text>(label);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final rect = tester.getRect(label);
      // No line is cut off: the text gets the height it needs, inside the item.
      expect(
        paragraph.getMaxIntrinsicHeight(rect.width),
        lessThanOrEqualTo(rect.height + 0.5),
      );
      final tile = _tile(tester, _longWord);
      expect(rect.top, greaterThanOrEqualTo(tile.top));
      expect(rect.bottom, lessThanOrEqualTo(tile.bottom));
      // Too long for two lines: it ends with an ellipsis.
      expect(paragraph.didExceedMaxLines, isTrue);
    });

    testWidgets('items are at least as tall as before at text size $scale',
        (tester) async {
      await _pump(tester, scale: scale);

      final tile = _tile(tester, _short);
      if (scale == 1) {
        expect(tile.height, 42);
      } else {
        expect(tile.height, greaterThan(42));
      }
      final selected =
          find.byKey(const ValueKey('collapsible-sidebar-selected-box'));
      expect(tester.getRect(selected), tile);
    });

    testWidgets('the collapsed sidebar keeps square items at text size $scale',
        (tester) async {
      await _pump(tester, scale: scale, alwaysExpanded: false);
      expect(tester.takeException(), isNull);

      expect(_tile(tester, _short).size, const Size(42, 42));
      expect(_tile(tester, _longWord).size, const Size(42, 42));
    });
  }

  testWidgets('the icon keeps the whole label as its tooltip', (tester) async {
    await _pump(tester, scale: 3);

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == _longWord,
      ),
      findsOneWidget,
    );
  });
}
