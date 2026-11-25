// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:dr/bundled_font_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(LicenseRegistry.reset);

  test('every bundled font file has a listed license', () {
    final fonts = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.ttf') || name.endsWith('.otf'))
        .toList();
    expect(fonts, isNotEmpty);
    // A new font file needs its family and license added to the list.
    final families =
        bundledFontLicenses.keys.map((family) => family.replaceAll(' ', ''));
    for (final font in fonts) {
      expect(families.any(font.startsWith), isTrue, reason: font);
    }
    for (final path in bundledFontLicenses.values) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('the license page lists the OFL of each bundled font', () async {
    registerBundledFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    for (final family in bundledFontLicenses.keys) {
      final entry = entries.singleWhere(
        (entry) => entry.packages.contains(family),
        orElse: () => fail('no license entry for $family'),
      );
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE'));
      expect(text, contains('Copyright'));
    }
  });
}
