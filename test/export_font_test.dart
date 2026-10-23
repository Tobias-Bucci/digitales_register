import 'dart:convert';
import 'package:dr/export/export_font.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('supplementary characters retain a valid UTF-16 PDF text map', () async {
    final font =
        ExportTtfFont(await rootBundle.load('assets/fonts/NotoEmoji.ttf'));
    final document = pw.Document(compress: false);
    document.addPage(
        pw.Page(build: (_) => pw.Text('👍', style: pw.TextStyle(font: font))));
    final encoded = latin1.decode(await document.save());
    expect(encoded, contains('<D83DDC4D>'));
    expect(encoded, isNot(contains('<1F44D>')));
  });
}
