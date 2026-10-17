import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

void main() {
  test('preserves existing grade display conventions', () {
    expect(formatGradeFromString('8.00'), '8');
    expect(formatGradeFromString('8.25'), '8+');
    expect(formatGradeFromString('8.50'), '8/9');
    expect(formatGradeFromString('8.75'), '9-');
    expect(formatGradeFromString('12.00'), '12');
    expect(formatGradeFromString('8.33'), '8.33');
  });
  final validGrades = <String, (int, String, String)>{
    '8': (800, '8.00', '8'),
    '8.0': (800, '8.00', '8'),
    '8.': (800, '8.00', '8'),
    '.50': (50, '0.50', '0/1'),
    '8.5': (850, '8.50', '8/9'),
    '8.50': (850, '8.50', '8/9'),
    '8.5000': (850, '8.50', '8/9'),
    '12': (1200, '12.00', '12'),
    '12.00': (1200, '12.00', '12'),
    '0': (0, '0.00', '0'),
    '0.0': (0, '0.00', '0'),
    ' 8.50 ': (850, '8.50', '8/9'),
    '\t8.5\r\n': (850, '8.50', '8/9'),
    '+8.5': (850, '8.50', '8/9'),
    '0008.5': (850, '8.50', '8/9'),
    '8.334': (833, '8.33', '8.33'),
    '8.335': (834, '8.34', '8.34'),
    '1.005': (101, '1.01', '1.01'),
    '8.249': (825, '8.25', '8+'),
    '8.995': (900, '9.00', '9'),
    '0.0049': (0, '0.00', '0'),
    '0.005': (1, '0.01', '0.01'),
    '123456789.125': (12345678913, '123456789.13', '123456789.13'),
  };
  for (final entry in validGrades.entries) {
    test('numeric backend grade ${entry.key} is parsed, rounded and normalized',
        () {
      final (hundredths, normalized, formatted) = entry.value;
      expect(parseBackendGradeHundredths(entry.key), hundredths);
      expect(validateBackendGrade(entry.key), normalized);
      expect(formatGradeFromString(entry.key), formatted);
      expect(validateBackendGrade(normalized), normalized);
    });
  }
  for (final invalid in [
    null,
    '',
    ' ',
    '8,5',
    '8,50',
    'abc',
    '.',
    '+',
    '8.5.2',
    '-8.50',
    '-0.01',
    '8.5abc',
    'abc8.5',
    '8 .5',
    'NaN',
    'Infinity',
    '1e2',
    '0x08',
    '99999999999999999999999999999999999999999999999999',
  ]) {
    test('malformed grade is unavailable: $invalid', () {
      expect(validateBackendGrade(invalid), isNull);
      expect(parseBackendGradeHundredths(invalid), isNull);
      expect(formatGradeFromString(invalid), 'keine Note eingetragen');
    });
  }
  test('dashboard preserves homework and valid grades beside a corrupt grade',
      () async {
    final store = createStore();
    await store.actions.dashboardActions.loaded(DaysLoadedPayload((b) => b
      ..future = false
      ..markNewOrChangedEntries = false
      ..deduplicateEntries = false
      ..data = [
        {
          'date': '2026-03-28',
          'items': [
            for (final (index, entry) in ['abc', ...validGrades.keys].indexed)
              {
                'id': index,
                'type': 'grade',
                'title': 'Grade',
                'subtitle': 'Subject',
                'grade': entry
              },
            {
              'id': 100,
              'type': 'homework',
              'title': 'Homework',
              'subtitle': ''
            },
          ]
        },
      ]));
    final items = store.state.dashboardState.allDays!.single.homework;
    expect(items, hasLength(validGrades.length + 2));
    expect(items.first.grade, isNull);
    expect(items.first.gradeFormatted, 'keine Note eingetragen');
    for (final (index, entry) in validGrades.entries.indexed) {
      expect(items[index + 1].grade, entry.value.$2);
      expect(items[index + 1].gradeFormatted, entry.value.$3);
    }
    expect(items.last.title, 'Homework');
  });
  test('basic and detailed grades use the same rounded hundredths model',
      () async {
    final store = createStore();
    final inputs = [...validGrades.keys, '8,5', 'abc', '', '-8.50', null];
    final expected = [
      ...validGrades.values.map((value) => value.$1),
      null,
      null,
      null,
      null,
      null
    ];
    await store.actions.gradesActions.loaded(SubjectsLoadedPayload((b) => b
      ..semester = Semester.first.toBuilder()
      ..data = {
        'subjects': [
          {
            'subject': {'id': 1, 'name': 'Subject'},
            'grades': [
              for (final grade in inputs)
                {
                  'grade': grade,
                  'weight': 100,
                  'date': '2026-03-28',
                  'cancelled': 0,
                  'type': 'Test'
                },
            ]
          },
        ]
      }));
    var subject = store.state.gradesState.subjects.single;
    expect(
        subject.gradesAll[Semester.first]!.map((grade) => grade.grade).toList(),
        expected);
    await store.actions.gradesActions
        .detailsLoaded(SubjectDetailLoadedPayload((b) => b
          ..semester = Semester.first.toBuilder()
          ..subject = subject.toBuilder()
          ..data = {
            'grades': [
              for (final (index, grade) in inputs.indexed)
                {
                  'id': index,
                  'grade': grade,
                  'weight': 100,
                  'date': '2026-03-28',
                  'cancelled': false,
                  'typeName': 'Test',
                  'created': '2026-03-28',
                  'name': 'Grade',
                  'description': '',
                  'type': 'grade'
                },
            ],
            'observations': []
          }));
    subject = store.state.gradesState.subjects.single;
    expect(subject.grades[Semester.first]!.map((grade) => grade.grade).toList(),
        expected);
  });
}
