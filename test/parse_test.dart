import 'dart:convert';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('parse absences from maps and encoded json', () {
    store.actions.absencesActions.loaded(absencesJson);
    store.actions.absencesActions.loaded(json.encode(absencesJson));
    store.actions.absencesActions
        .loaded(json.decode(json.encode(absencesJson)) as Map<String, dynamic>);

    expect(store.state.absencesState.absences, hasLength(2));
    expect(store.state.absencesState.absences.first.absences, hasLength(4));
    expect(store.state.absencesState.absences.first.reason, contains('fit'));
    expect(store.state.absencesState.statistic!.delayed, 0);
    expect(store.state.absencesState.canEdit, isTrue);
  });

  test('parse calendar days and merge additional pages', () {
    store.actions.calendarActions.loaded(calendarPageOne);
    store.actions.calendarActions.loaded(calendarPageTwo);

    expect(store.state.calendarState.days, hasLength(2));

    final firstDay = store.state.calendarState.days[UtcDateTime(2022, 9, 28)]!;
    expect(firstDay.hours, hasLength(1));
    expect(firstDay.hours.single.subject, 'Projekttag');
    expect(firstDay.hours.single.timeSpans, hasLength(2));
    expect(firstDay.hours.single.homeworkExams.single.name, 'Arbeitsblatt');

    final secondDay =
        store.state.calendarState.days[UtcDateTime(2022, 9, 29)]!;
    expect(secondDay.hours.single.subject, 'Mathematik');
  });

  test('parse grades list, details, and observations', () {
    store.actions.gradesActions.loaded(
      SubjectsLoadedPayload(
        (b) => b
          ..data = subjectsPayload
          ..semester = Semester.first.toBuilder(),
      ),
    );

    expect(store.state.gradesState.subjects, hasLength(2));
    expect(store.state.gradesState.hasGrades, isTrue);
    expect(
      store.state.gradesState.subjects.first.basicGrades(Semester.first),
      hasLength(1),
    );

    store.actions.gradesActions.detailsLoaded(
      SubjectDetailLoadedPayload(
        (b) => b
          ..data = subjectDetailsPayload
          ..subject = store.state.gradesState.subjects.first.toBuilder()
          ..semester = Semester.first.toBuilder(),
      ),
    );

    final subject = store.state.gradesState.subjects.first;
    expect(subject.detailEntries(Semester.first), hasLength(2));
    expect(subject.grades[Semester.first]!.single.name, 'Schularbeit 1');
    expect(subject.observations[Semester.first], hasLength(1));
    expect(subject.observations[Semester.first]!.single.note, 'Gut vorbereitet');
  });

  test('parse profile', () {
    store.actions.profileActions.loaded(profilePayload);

    expect(
      store.state.profileState,
      ProfileState(
        (b) => b
          ..name = 'Debertol Michael'
          ..email = 'st-debmic-03@vinzentinum.it'
          ..username = 'st-debmic-03'
          ..roleName = 'Schüler/in'
          ..sendNotificationEmails = false,
      ),
    );
  });
}

final Map<String, Object?> absencesJson = <String, Object?>{
  'absences': <Object>[
    <String, Object?>{
      'group': <Object>[
        <String, Object?>{
          'id': 3044,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 5,
        },
        <String, Object?>{
          'id': 3032,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 4,
        },
        <String, Object?>{
          'id': 3026,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 3,
        },
        <String, Object?>{
          'id': 3012,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-02',
          'hour': 2,
        },
      ],
      'date': '2021-02-02',
      'note': null,
      'reason': 'Laura ist noch immer nicht ganz fit',
      'reason_signature': null,
      'reason_timestamp': null,
      'reason_user': 1768,
      'justified': 1,
    },
    <String, Object?>{
      'group': <Object>[
        <String, Object?>{
          'id': 2985,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-01',
          'hour': 5,
        },
        <String, Object?>{
          'id': 3002,
          'minutes': 50,
          'minutes_begin': 0,
          'minutes_end': 0,
          'date': '2021-02-01',
          'hour': 4,
        },
      ],
      'date': '2021-02-01',
      'note': null,
      'reason':
          'Laura fühlt sich nicht ganz wohl, sie bleibt sicherheitshalber zu Hause',
      'reason_signature': null,
      'reason_timestamp': null,
      'reason_user': 1768,
      'justified': 1,
    },
  ],
  'futureAbsences': <Object>[],
  'canEdit': true,
  'statistics': <String, Object?>{
    'counter': '',
    'counterForSchool': '',
    'percentage': '',
    'justified': 0,
    'notJustified': 0,
    'delayed': 0,
  },
};

final Map<String, dynamic> calendarPageOne = <String, dynamic>{
  '2022-09-28': <String, Object?>{
    '1': <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          'isLesson': 1,
          'hour': 1,
          'lesson': <String, Object?>{
            'hour': 1,
            'toHour': 2,
            'date': '2022-09-28',
            'subject': <String, Object?>{'name': 'Projekttag'},
            'teachers': <Object>[
              <String, Object?>{'firstName': 'Tom', 'lastName': 'Smith'},
            ],
            'rooms': <Object>[],
            'homeworkExams': <Object>[
              <String, Object?>{
                'deadline': '2022-09-28',
                'hasGradeGroupSubmissions': false,
                'hasGrades': false,
                'homework': 1,
                'id': 5,
                'name': 'Arbeitsblatt',
                'online': false,
                'typeId': 500,
                'typeName': 'Hausaufgabe',
              },
            ],
            'lessonContents': <Object>[],
            'timeStartObject': <String, Object?>{'h': '07', 'm': '40'},
            'timeEndObject': <String, Object?>{'h': '08', 'm': '35'},
            'linkedHours': <Object>[
              <String, Object?>{
                'date': '2022-09-28',
                'timeStartObject': <String, Object?>{'h': '08', 'm': '35'},
                'timeEndObject': <String, Object?>{'h': '09', 'm': '25'},
              },
            ],
          },
        },
      },
    },
  },
};

final Map<String, dynamic> calendarPageTwo = <String, dynamic>{
  '2022-09-29': <String, Object?>{
    '1': <String, Object?>{
      '1': <String, Object?>{
        '1': <String, Object?>{
          'isLesson': 1,
          'hour': 3,
          'lesson': <String, Object?>{
            'hour': 3,
            'toHour': 3,
            'date': '2022-09-29',
            'subject': <String, Object?>{'name': 'Mathematik'},
            'teachers': <Object>[
              <String, Object?>{'firstName': 'Anna', 'lastName': 'Rossi'},
            ],
            'rooms': <Object>[
              <String, Object?>{'name': 'Raum 2'},
            ],
            'homeworkExams': <Object>[],
            'lessonContents': <Object>[],
            'timeStartObject': <String, Object?>{'h': '10', 'm': '15'},
            'timeEndObject': <String, Object?>{'h': '11', 'm': '05'},
            'linkedHours': <Object>[],
          },
        },
      },
    },
  },
};

final Map<String, Object?> subjectsPayload = <String, Object?>{
  'subjects': <Object>[
    <String, Object?>{
      'subject': <String, Object?>{'id': 1, 'name': 'Deutsch'},
      'grades': <Object>[
        <String, Object?>{
          'grade': '7.50',
          'weight': 100,
          'date': '2021-02-03',
          'cancelled': 0,
          'type': 'Schularbeit',
        },
      ],
    },
    <String, Object?>{
      'subject': <String, Object?>{'id': 2, 'name': 'Mathematik'},
      'grades': <Object>[],
    },
  ],
};

final Map<String, Object?> subjectDetailsPayload = <String, Object?>{
  'grades': <Object>[
    <String, Object?>{
      'id': 12,
      'grade': '7.50',
      'weight': 100,
      'date': '2021-02-03',
      'cancelled': false,
      'typeName': 'Schularbeit',
      'created': 'am 4. 2. erstellt',
      'name': 'Schularbeit 1',
      'description': 'Kapitel 1',
      'competences': <Object>[
        <String, Object?>{
          'typeName': 'Textverständnis',
          'grade': '4',
        },
      ],
    },
  ],
  'observations': <Object>[
    <String, Object?>{
      'typeName': 'Beobachtung',
      'cancelled': 0,
      'created': 'Am 5. März 2021',
      'note': 'Gut vorbereitet',
      'date': '2021-03-05',
    },
  ],
};

final Map<String, Object?> profilePayload = <String, Object?>{
  'name': 'Debertol Michael',
  'email': 'st-debmic-03@vinzentinum.it',
  'username': 'st-debmic-03',
  'roleName': 'Schüler/in',
  'notificationsEnabled': false,
};
