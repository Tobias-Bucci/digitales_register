// Issue #134: a day with two lessons running in parallel lost every lesson
// after the first one, because only the first group of the day was read.

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/calendar.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

const _wednesday = '2026-11-25';

Map<String, Object?> _entry(
  int hour,
  String subject,
  String teacher, {
  int? toHour,
  int? id,
  String date = _wednesday,
}) {
  final to = toHour ?? hour;
  String time(int h) => (7 + h).toString().padLeft(2, '0');
  return <String, Object?>{
    'isLesson': 1,
    'hour': hour,
    'linkedHoursCount': to - hour,
    'lesson': <String, Object?>{
      if (id != null) 'id': id,
      'hour': hour,
      'toHour': to,
      'date': date,
      'classId': 7,
      'subject': <String, Object?>{'id': subject.hashCode, 'name': subject},
      'teachers': <Object>[
        <String, Object?>{'firstName': 'T', 'lastName': teacher},
      ],
      'rooms': <Object>[
        <String, Object?>{'name': '3B'},
      ],
      'homeworkExams': <Object>[],
      'lessonContents': <Object>[],
      'timeStartObject': <String, Object?>{'h': time(hour), 'm': '00'},
      'timeEndObject': <String, Object?>{'h': time(hour), 'm': '50'},
      'linkedHours': <Object>[
        for (var h = hour + 1; h <= to; h++)
          <String, Object?>{
            'date': date,
            'timeStartObject': <String, Object?>{'h': time(h), 'm': '00'},
            'timeEndObject': <String, Object?>{'h': time(h), 'm': '50'},
          },
      ],
    },
  };
}

/// The Wednesday of the report: lesson 1, two parallel lessons in 2–3, then
/// lessons 4, 5 and 6. The register puts the first lesson in a group of its
/// own and the parallel lessons in two columns of the next group.
Map<String, Object?> _issueWednesday() => <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{'1': _entry(1, 'GES', 'Rauch')},
      },
      '2': <String, Object?>{
        '1': <String, Object?>{
          '2': _entry(2, 'Deutsch', 'Rauch', toHour: 3),
          '4': _entry(4, 'BuS', 'Mumelter'),
          '5': _entry(5, 'DEU', 'Rauch'),
          '6': _entry(6, 'MAT', 'Thaler'),
        },
        '2': <String, Object?>{
          '2': _entry(2, 'Informatik', 'Awerk', toHour: 3),
        },
      },
    };

/// A normal day as the register sends it: one group with one column.
Map<String, Object?> _plainDay(String date) => <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          '1': _entry(1, 'MAT', 'Thaler', date: date),
          '2': _entry(2, 'DEU', 'Rauch', toHour: 3, date: date),
          '4': _entry(4, 'GES', 'Rauch', date: date),
        },
      },
    };

void main() {
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() {
    store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
      middleware: middleware(includeErrorMiddleware: false),
    );
  });

  Future<CalendarDay> load(Map<String, Object?> day,
      {String date = _wednesday}) async {
    await store.actions.calendarActions.loaded(
      CalendarLoadedPayload(
        data: <String, dynamic>{date: day},
        config: SubstituteDetectionConfig(
          (b) => b
            ..enabled = false
            ..primaryTeachers = MapBuilder<String, BuiltList<String>>()
            ..lockedSubjects = ListBuilder<String>(),
        ),
      ),
    );
    return store.state.calendarState.days[UtcDateTime.parse(date)]!;
  }

  List<String> lessons(CalendarDay day) => [
        for (final hour in day.hours)
          '${hour.fromHour}-${hour.toHour} ${hour.subject}',
      ];

  test('keeps every lesson of a day with parallel lessons in 2–3', () async {
    final day = await load(_issueWednesday());

    expect(lessons(day), [
      '1-1 GES',
      '2-3 Deutsch',
      '2-3 Informatik',
      '4-4 BuS',
      '5-5 DEU',
      '6-6 MAT',
    ]);
    expect(day.fromHour, 1);
    expect(day.toHour, 6);
    final informatik = day.hours.firstWhere((h) => h.subject == 'Informatik');
    expect(informatik.teachers.single.lastName, 'Awerk');
    expect(informatik.timeSpans, hasLength(2));
  });

  test('keeps parallel lessons of a single hour and the lessons around them',
      () async {
    final day = await load(<String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          '1': _entry(1, 'GES', 'Rauch'),
          '2': _entry(2, 'Religion', 'Huber'),
          '3': _entry(3, 'MAT', 'Thaler'),
        },
        '2': <String, Object?>{'2': _entry(2, 'Ethik', 'Moser')},
      },
    });

    expect(lessons(day).first, '1-1 GES');
    expect(lessons(day).sublist(1, 3),
        unorderedEquals(['2-2 Ethik', '2-2 Religion']));
    expect(lessons(day).last, '3-3 MAT');
    expect(day.toHour, 3);
  });

  test('a parallel lesson that ends later sets the end of the day', () async {
    final day = await load(<String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          '1': _entry(1, 'GES', 'Rauch'),
          '5': _entry(5, 'DEU', 'Rauch'),
        },
        '2': <String, Object?>{'4': _entry(4, 'Sport', 'Pichler', toHour: 6)},
      },
    });

    expect(lessons(day), ['1-1 GES', '4-6 Sport', '5-5 DEU']);
    expect(day.toHour, 6);
  });

  test('a lesson listed in two columns is kept once', () async {
    final day = await load(<String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          '1': _entry(1, 'GES', 'Rauch', id: 11),
          '2': _entry(2, 'MAT', 'Thaler', id: 12, toHour: 3),
        },
        '2': <String, Object?>{
          '2': _entry(2, 'MAT', 'Thaler', id: 12, toHour: 3),
          '4': _entry(4, 'BuS', 'Mumelter', id: 14),
        },
      },
    });

    expect(lessons(day), ['1-1 GES', '2-3 MAT', '4-4 BuS']);
  });

  test('normal days are parsed as before', () async {
    final day = await load(_plainDay('2026-11-23'), date: '2026-11-23');

    expect(lessons(day), ['1-1 MAT', '2-3 DEU', '4-4 GES']);
    expect(day.toHour, 4);
  });

  test('a whole week keeps its other days next to the parallel Wednesday',
      () async {
    await store.actions.calendarActions.loaded(
      CalendarLoadedPayload(
        data: <String, dynamic>{
          '2026-11-24': _plainDay('2026-11-24'),
          _wednesday: _issueWednesday(),
          '2026-11-26': _plainDay('2026-11-26'),
        },
        config: SubstituteDetectionConfig(
          (b) => b
            ..enabled = false
            ..primaryTeachers = MapBuilder<String, BuiltList<String>>()
            ..lockedSubjects = ListBuilder<String>(),
        ),
      ),
    );
    final days = store.state.calendarState.days;

    expect(days[UtcDateTime(2026, 11, 24)]!.hours, hasLength(3));
    expect(days[UtcDateTime(2026, 11, 25)]!.hours, hasLength(6));
    expect(days[UtcDateTime(2026, 11, 26)]!.hours, hasLength(3));
  });

  group('calendarDayEntries', () {
    test('reads every group and column', () {
      expect(calendarDayEntries(_issueWednesday()), hasLength(6));
    });

    test('skips empty slots', () {
      expect(
        calendarDayEntries(<String, Object?>{
          '1': <String, Object?>{
            '1': <String, Object?>{'1': _entry(1, 'GES', 'Rauch'), '2': null},
            '2': <Object?>[],
          },
        }),
        hasLength(1),
      );
    });
  });
}
