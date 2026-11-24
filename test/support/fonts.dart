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

import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// Flutter's bundled Material fonts (`bin/cache/artifacts/material_fonts`).
///
/// Uses `FLUTTER_ROOT` when set, else walks up from the test runner binary
/// (`<root>/bin/cache/artifacts/engine/<platform>/flutter_tester`).
Directory materialFontsDirectory() {
  const relative = 'bin/cache/artifacts/material_fonts';
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) return Directory('$root/$relative');
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = Directory('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate;
    if (dir.parent.path == dir.path) {
      throw StateError('Flutter\'s material fonts were not found; '
          'set FLUTTER_ROOT.');
    }
    dir = dir.parent;
  }
}

/// The font file [name] in [materialFontsDirectory], whatever its case.
///
/// The Flutter SDK names them `Roboto-Regular.ttf` on Linux and macOS but
/// `roboto-regular.ttf` on Windows (#172). A fixed spelling found the files
/// only on Windows, and the fit tests then measured the square test glyphs.
File materialFont(String name) {
  final wanted = name.toLowerCase();
  final directory = materialFontsDirectory();
  for (final entity in directory.listSync()) {
    if (entity is File &&
        entity.uri.pathSegments.last.toLowerCase() == wanted) {
      return entity;
    }
  }
  throw StateError('$name is missing in ${directory.path}');
}

/// Loads [files] (names in [materialFontsDirectory]) as font [family].
Future<void> loadMaterialFontFamily(
    String family, Iterable<String> files) async {
  final loader = FontLoader(family);
  for (final name in files) {
    final bytes = await materialFont(name).readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

const robotoFiles = [
  'roboto-regular.ttf',
  'roboto-medium.ttf',
  'roboto-bold.ttf',
];

/// Real Roboto metrics, so fit checks match an Android phone rather than the
/// test font's square glyphs. Fails if the fonts are missing, instead of
/// silently measuring the test font.
Future<void> loadRoboto(WidgetTester tester) =>
    tester.runAsync(() => loadMaterialFontFamily('Roboto', robotoFiles));
