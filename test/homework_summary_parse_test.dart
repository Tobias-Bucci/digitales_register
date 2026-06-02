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

import 'package:dr/ui/homework_summary_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses homework summary html into weeks and entries', () {
    final document = HomeworkSummaryDocument.parse('''
<div id="classSummary">
  <div class="summary">
    <h1 class="h1">Hausaufgaben Übersicht - 5AT</h1>
    <h3>Woche vom 18/5/2026</h3>
    <table class="summary-table">
      <thead>
        <tr>
          <th>Datum</th>
          <th>Fach</th>
          <th>Art</th>
          <th>Name</th>
          <th>Online Abgabe</th>
        </tr>
      </thead>
      <tr>
        <td class="name-cell">Mo, 18/05</td>
        <td>Italienisch</td>
        <td>Prüfung</td>
        <td>Interrogazioni Cap.3</td>
        <td>Nein</td>
      </tr>
    </table>
    <h3>Woche vom 1/6/2026</h3>
    <table class="summary-table">
      <thead>
        <tr>
          <th>Datum</th>
          <th>Fach</th>
          <th>Art</th>
          <th>Name</th>
          <th>Online Abgabe</th>
        </tr>
      </thead>
    </table>
  </div>
</div>
''');

    expect(document.title, 'Hausaufgaben Übersicht - 5AT');
    expect(document.weeks, hasLength(2));
    expect(document.weeks.first.title, 'Woche vom 18/5/2026');
    expect(document.weeks.first.entries, hasLength(1));
    expect(document.weeks.first.entries.first.dateText, 'Mo, 18/05');
    expect(document.weeks.first.entries.first.secondaryText,
        'Italienisch - Prüfung');
    expect(
        document.weeks.first.entries.first.primaryText, 'Interrogazioni Cap.3');
    expect(document.weeks.first.entries.first.extraCells.single.header,
        'Online Abgabe');
    expect(document.weeks.first.entries.first.extraCells.single.value, 'Nein');
    expect(document.weeks.last.entries, isEmpty);
  });
}
