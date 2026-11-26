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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

// #178: every icon button and the done checkbox of the legacy dashboard must
// have an accessible name, or a screen reader only says "Button".
void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() {
    resetTestState();
  });

  testWidgets('every legacy day action has an accessible name', (tester) async {
    final semantics = tester.ensureSemantics();
    final reminder = buildHomework(
      title: 'Turnbeutel einpacken',
      subtitle: '',
      label: 'Mathematik',
      type: HomeworkType.homework,
      checkable: true,
      deleteable: true,
      isChanged: true,
    ).rebuild(
      (b) => b.previousVersion.replace(
        buildHomework(
          title: 'Turnbeutel',
          subtitle: '',
          label: 'Mathematik',
          type: HomeworkType.homework,
        ),
      ),
    );
    final deleted = buildHomework(
      id: 2,
      title: 'Alte Aufgabe',
      label: 'Deutsch',
      deleted: true,
      isChanged: true,
    ).rebuild(
      (b) => b.previousVersion.replace(
        buildHomework(id: 2, title: 'Alte Aufgabe', label: 'Deutsch'),
      ),
    );
    final store = createStore(
      initialState: AppState(
        (b) => b.dashboardState
          ..future = true
          ..allDays = ListBuilder<Day>(<Day>[
            buildDay(
              date: UtcDateTime(2050),
              homework: <Homework>[reminder],
              deletedHomework: <Homework>[deleted],
            ),
          ]),
      ),
    );

    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);

    expect(find.byType(DayWidget), findsOneWidget);
    final buttons = find.descendant(
      of: find.byType(DayWidget),
      matching: find.byType(IconButton),
    );
    // Deleted entries, add, delete, edit and history.
    expect(buttons, findsNWidgets(5));
    final tooltips = <String>[
      for (final button in tester.widgetList<IconButton>(buttons))
        button.tooltip ?? '',
    ];
    expect(tooltips, everyElement(isNotEmpty));
    expect(
      tooltips,
      containsAll(<String>[
        'Gelöschte Einträge',
        'Neuer Eintrag',
        'Löschen',
        'Bearbeiten',
        'Verlauf',
      ]),
    );

    final checkbox = tester.widget<Checkbox>(
      find.descendant(
        of: find.byType(DayWidget),
        matching: find.byType(Checkbox),
      ),
    );
    expect(checkbox.semanticLabel, 'Als erledigt markieren');
    expect(find.bySemanticsLabel('Als erledigt markieren'), findsOneWidget);
    // A screen reader announces the tooltip as the button's name.
    expect(
      tester.getSemantics(find.byTooltip('Verlauf')),
      containsSemantics(tooltip: 'Verlauf', isButton: true),
    );

    // The changed deleted entry starts a short scroll highlight.
    await tester.pump(const Duration(seconds: 1));
    semantics.dispose();
  });
}
