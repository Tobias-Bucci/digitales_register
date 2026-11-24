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

// #168: one malformed entry from the school server leaves out that entry
// instead of hiding the whole page. When every entry is malformed, the page
// still shows its error.

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/ui/build_failure_placeholder.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _message(int id, {bool broken = false}) => {
      'id': id,
      'subject': 'Message $id',
      'text': '{"ops":[{"insert":"Text\\n"}]}',
      if (!broken) 'timeSent': '2026-03-0${id}T10:00:00',
      'recipientString': 'Class',
      'fromName': 'Teacher',
    };

Map<String, Object?> _grade(String date, {bool broken = false}) => {
      'grade': '8.00',
      'weight': 100,
      if (!broken) 'date': date,
      'cancelled': 0,
      'type': 'Test',
    };

Map<String, Object?> _futureAbsence(int id, {bool broken = false}) => {
      'id': id,
      'studentId': 1,
      if (!broken) 'startDate': '2026-05-0$id 00:00:00',
      'endDate': '2026-05-0$id 00:00:00',
      'startTime': 1,
      'endTime': 6,
      'justified': 2,
    };

Map<String, Object?> _absenceGroup(int day, {bool broken = false}) => {
      'date': '2026-04-0$day 08:00:00',
      'justified': 2,
      'group': [
        {
          'id': day,
          'minutes': 50,
          if (!broken) 'date': '2026-04-0$day 08:00:00',
          'hour': 1,
          'minutes_begin': 0,
          'minutes_end': 0,
          'justified': 2,
        },
      ],
    };

Map<String, Object?> _absencesPayload({
  required List<Object> groups,
  required List<Object> future,
}) =>
    {
      'statistics': {
        'counter': 2,
        'counterForSchool': 2,
        'delayed': 0,
        'justified': 2,
        'notJustified': 0,
        'percentage': '1',
      },
      'absences': groups,
      'futureAbsences': future,
      'canEdit': false,
    };

void main() {
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() {
    store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
    );
  });

  group('parseEachSkippingFailures', () {
    int parse(dynamic item) => getInt(item)!;

    test('leaves out the elements that fail', () {
      expect(parseEachSkippingFailures([1, 'x', null, 4], parse), [1, 4]);
    });

    test('an empty list stays empty', () {
      expect(parseEachSkippingFailures(const <Object>[], parse), isEmpty);
    });

    test('rethrows when every element fails', () {
      expect(() => parseEachSkippingFailures(['x', null], parse),
          throwsA(isA<ParseException>()));
    });
  });

  test('messages: one broken message leaves the others', () {
    store.actions.messagesActions.loaded([
      _message(1),
      _message(2, broken: true),
      _message(3),
    ]);
    expect(store.state.messagesState.messages.map((m) => m.id), [1, 3]);
  });

  test('messages: only broken messages still fail the page', () {
    expect(
      () => store.actions.messagesActions
          .loaded([_message(1, broken: true), _message(2, broken: true)]),
      throwsA(isA<ParseException>()),
    );
  });

  test('grades: one broken grade leaves the other grades of the subject', () {
    store.actions.gradesActions.loaded(
      SubjectsLoadedPayload(
        (b) => b
          ..semester = Semester.first.toBuilder()
          ..data = <String, Object?>{
            'subjects': <Object>[
              <String, Object?>{
                'subject': <String, Object?>{'id': 1, 'name': 'Deutsch'},
                'grades': <Object>[
                  _grade('2026-02-01'),
                  _grade('2026-02-02', broken: true),
                  _grade('2026-02-03'),
                ],
              },
            ],
          },
      ),
    );
    final grades =
        store.state.gradesState.subjects.single.gradesAll[Semester.first]!;
    expect(grades.map((g) => g.date.day), [1, 3]);
  });

  test('absences: a broken group or future absence leaves the others', () {
    store.actions.absencesActions.loaded(_absencesPayload(
      groups: [
        _absenceGroup(1),
        _absenceGroup(2, broken: true),
        _absenceGroup(3),
      ],
      future: [_futureAbsence(1, broken: true), _futureAbsence(2)],
    ));
    final state = store.state.absencesState;
    expect(state.absences.map((g) => g.date!.day), [3, 1]);
    expect(state.futureAbsences.map((a) => a.id), [2]);
    expect(state.statistic!.counter, 2);
  });

  group('build failures outside debug builds', () {
    late ErrorWidgetBuilder original;
    setUp(() => original = ErrorWidget.builder);
    tearDown(() => ErrorWidget.builder = original);

    test('debug builds keep the detailed error widget', () {
      // Tests run as a debug build.
      installBuildFailurePlaceholder();
      expect(ErrorWidget.builder, same(original));
    });

    testWidgets('show a calm hint instead of a grey box', (tester) async {
      installBuildFailurePlaceholder(debugMode: false);
      final widget = ErrorWidget.builder(
          FlutterErrorDetails(exception: StateError('broken')));
      expect(widget, isA<BuildFailurePlaceholder>());
      // Without Material, localizations or bounded constraints.
      await tester.pumpWidget(Row(
        textDirection: TextDirection.ltr,
        children: [widget],
      ));
      expect(find.text('This content cannot be displayed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // testWidgets checks that the builder is back before tearDown runs.
      ErrorWidget.builder = original;
    });
  });
}
