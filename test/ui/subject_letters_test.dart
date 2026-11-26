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
import 'package:dr/ui/calendar_card.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/fonts.dart';
import '../support/test_harness.dart';

// #181: a subject's mark shows its first two letters, so that "Mathematik"
// and "Musik" can be told apart.
final _today = UtcDateTime(2026, 10, 20);

/// Android's largest font size.
const _largestTextScale = 2.0;

void _expectInside(WidgetTester tester, Finder inner, Finder outer) {
  final innerRect = tester.getRect(inner);
  final outerRect = tester.getRect(outer);
  const tolerance = 0.01;
  expect(innerRect.left, greaterThanOrEqualTo(outerRect.left - tolerance));
  expect(innerRect.right, lessThanOrEqualTo(outerRect.right + tolerance));
  expect(innerRect.top, greaterThanOrEqualTo(outerRect.top - tolerance));
  expect(innerRect.bottom, lessThanOrEqualTo(outerRect.bottom + tolerance));
}

void main() {
  group('subjectLetters', () {
    test('an empty name has no letters', () {
      expect(subjectLetters(''), '');
      expect(subjectLetters('   '), '');
    });

    test('a name of one letter keeps it', () {
      expect(subjectLetters('M'), 'M');
      expect(subjectLetters('d'), 'D');
    });

    test('a name of two letters shows both', () {
      expect(subjectLetters('Ma'), 'Ma');
      expect(subjectLetters('IT'), 'It');
    });

    test('a longer name shows its first two letters', () {
      expect(subjectLetters('Mathematik'), 'Ma');
      expect(subjectLetters('Musik'), 'Mu');
      expect(subjectLetters('Deutsch'), 'De');
      expect(subjectLetters('Geschichte'), 'Ge');
      expect(subjectLetters('Geographie'), 'Ge');
      expect(subjectLetters('MATHEMATIK'), 'Ma');
      expect(subjectLetters('religion'), 'Re');
    });

    test('umlauts and combined characters stay whole', () {
      expect(subjectLetters('Ökologie'), 'Ök');
      expect(subjectLetters('Übungen'), 'Üb');
      expect(subjectLetters('äSTHETIK'), 'Äs');
      // "Ö" written as "O" and a combining diaeresis is one character.
      expect(subjectLetters('Ökologie'), 'Ök');
      expect(subjectLetters('Ëëtica'), 'Ëë');
    });

    test('leading and trailing whitespace is ignored', () {
      expect(subjectLetters('  Mathematik'), 'Ma');
      expect(subjectLetters('\tMusik \n'), 'Mu');
    });

    test('a second character that is no letter is left out', () {
      expect(subjectLetters('E-Technik'), 'E');
      expect(subjectLetters('M 2'), 'M');
      expect(subjectLetters('1. Fremdsprache'), '1');
    });
  });

  group('marks', () {
    setUp(() async {
      await bootstrapTestEnvironment(fixedNow: _today);
    });

    tearDown(resetTestState);

    for (final scale in [1.0, _largestTextScale]) {
      testWidgets('the dashboard shows two letters that fit, text x$scale',
          (tester) async {
        await loadRoboto(tester);
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final store = createStore(
          initialState: AppState((b) {
            b.dashboardState.allDays = ListBuilder<Day>([
              buildDay(date: _today, homework: [
                buildHomework(
                  id: 1,
                  title: 'Hausaufgabe',
                  label: 'Mathematik',
                  checkable: true,
                ),
                buildHomework(
                  id: 2,
                  title: 'Hausaufgabe',
                  label: 'Musik',
                  checkable: true,
                ),
              ]),
            ]);
            b.loginState
              ..loggedIn = true
              ..username = 'anna';
            b.noInternet = true;
          }),
          newDesign: true,
        );
        await pumpApp(tester, store: store, home: DaysContainer());
        await settleFor(tester);

        for (final (id, letters) in [(1, 'Ma'), (2, 'Mu')]) {
          final text = find.byKey(ValueKey('compact-row-subject-$id'));
          expect(tester.widget<Text>(text).data, letters);
          _expectInside(
            tester,
            text,
            find.byKey(ValueKey('compact-row-subject-box-$id')),
          );
          // The row still names the whole subject to a screen reader.
          expect(
            find.bySemanticsLabel(
                RegExp('^${letters == 'Ma' ? 'Mathematik' : 'Musik'}, ')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('two letters fit the calendar circle, text x$scale',
          (tester) async {
        await loadRoboto(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Center(
                child: CircledLetter(letter: 'Mw', color: Colors.blue),
              ),
            ),
          ),
        );

        final circle = find.byType(CircledLetter);
        expect(tester.getSize(circle), const Size(45, 45));
        final text = find.text('Mw');
        _expectInside(tester, text, circle);
        // Inside the round shape too: the corners of the text's box lie in the
        // circle.
        final rect = tester.getRect(text);
        final center = tester.getCenter(circle);
        for (final corner in [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ]) {
          expect((corner - center).distance, lessThanOrEqualTo(22.5));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
