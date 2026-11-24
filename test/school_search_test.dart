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

import 'package:dr/config.dart';
import 'package:dr/school_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final names = schools.keys;

  test('a school name lists only the schools with that name (#171)', () {
    expect(searchSchools(names, 'Cusanus'), ['Cusanus Gymnasium Bruneck']);
    expect(searchSchools(names, 'cusanus'), ['Cusanus Gymnasium Bruneck']);
  });

  test('every word must match; word starts come first', () {
    final results = searchSchools(names, 'gymnasium brun');
    expect(results, isNotEmpty);
    for (final name in results) {
      expect(
          name.toLowerCase(), allOf(contains('gymnasium'), contains('brun')));
    }
  });

  test('case and accents do not matter', () {
    final withAccent = schools.keys.firstWhere(
        (name) => name.contains(RegExp('[äöüàèéìòù]')),
        orElse: () => '');
    if (withAccent.isEmpty) return;
    final word = withAccent
        .split(' ')
        .firstWhere((w) => w.contains(RegExp('[äöüàèéìòù]')));
    final plain = word
        .toLowerCase()
        .replaceAll('ä', 'a')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp('[àá]'), 'a')
        .replaceAll(RegExp('[èé]'), 'e')
        .replaceAll('ì', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ù', 'u');
    expect(searchSchools(names, plain), contains(withAccent));
  });

  test('a typo still finds the school', () {
    expect(
        searchSchools(names, 'Cusanos'), contains('Cusanus Gymnasium Bruneck'));
  });

  test('at most 15 schools, nothing for an empty query', () {
    expect(searchSchools(names, 'schule').length, lessThanOrEqualTo(15));
    expect(searchSchools(names, '  '), isEmpty);
  });
}
