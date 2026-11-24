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

import 'package:fuzzy/fuzzy.dart';

/// The schools offered for [query] in the school field, best first.
///
/// Schools whose name contains every word of the query, ignoring case and
/// accents, are offered first: those where every word starts a word of the
/// name ("Cusanus" in "Cusanus Gymnasium Bruneck"), then the others. Only
/// when no name contains the words, a strict fuzzy search tolerates typos
/// ("Cusanos"). A plain fuzzy search also listed unrelated schools such as
/// "Grundschule Sexten" for "Cusanus" (#171).
List<String> searchSchools(
  Iterable<String> names,
  String query, {
  int limit = 15,
}) {
  final words = _words(query);
  if (words.isEmpty) return const [];
  final startsWords = <String>[];
  final contains = <String>[];
  for (final name in names) {
    final nameWords = _words(name);
    final normalized = nameWords.join(' ');
    if (!words.every(normalized.contains)) continue;
    final atWordStarts =
        words.every((word) => nameWords.any((w) => w.startsWith(word)));
    (atWordStarts ? startsWords : contains).add(name);
  }
  final direct = [...startsWords, ...contains];
  if (direct.isNotEmpty) return direct.take(limit).toList();
  return Fuzzy<String>(
    names.toList(),
    options: FuzzyOptions<String>(
      maxPatternLength: 256,
      tokenize: true,
      threshold: 0.3,
    ),
  ).search(query).take(limit).map((result) => result.item).toList();
}

List<String> _words(String text) => _fold(text.toLowerCase())
    .split(RegExp('[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toList();

const _folds = {
  'ä': 'a',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ë': 'e',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ï': 'i',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ö': 'o',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ü': 'u',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ß': 'ss',
  'ç': 'c',
};

String _fold(String text) {
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    buffer.write(_folds[char] ?? char);
  }
  return buffer.toString();
}
