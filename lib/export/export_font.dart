// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:pdf/pdf.dart';
// pdf 3.13.1 exposes the font but not its Unicode map type. Keep this workaround
// isolated until upstream encodes supplementary characters as UTF-16BE.
// ignore: implementation_imports
import 'package:pdf/src/pdf/obj/unicode_cmap.dart';
import 'package:pdf/widgets.dart' as pw;

class ExportTtfFont extends pw.TtfFont {
  ExportTtfFont(super.data);
  @override
  PdfFont buildFont(PdfDocument pdfDocument) {
    final font = PdfTtfFont(pdfDocument, data);
    pdfDocument.objects.remove(font.unicodeCMap);
    font.unicodeCMap = _Utf16Cmap(pdfDocument);
    return font;
  }
}

class _Utf16Cmap extends PdfUnicodeCmap {
  _Utf16Cmap(PdfDocument document) : super(document, false);
  @override
  // Replace the upstream stream entirely; super.prepare would emit a second, invalid CMap.
  // ignore: must_call_super
  void prepare() {
    buf.putString(
        '/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n'
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n'
        '/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n'
        '1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n');
    for (var start = 0; start < cmap.length; start += 100) {
      final end = (start + 100).clamp(0, cmap.length);
      buf.putString('${end - start} beginbfchar\n');
      for (var i = start; i < end; i++) {
        final unicode = String.fromCharCode(cmap[i])
            .codeUnits
            .map((unit) => unit.toRadixString(16).padLeft(4, '0').toUpperCase())
            .join();
        buf.putString('<${i.toRadixString(16).padLeft(4, '0')}> <$unicode>\n');
      }
      buf.putString('endbfchar\n');
    }
    buf.putString(
        'endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend');
  }
}
