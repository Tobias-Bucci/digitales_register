// Copyright (C) 2026 Tobias Bucci

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() {
    store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
    );
  });

  test('dashboard parsing can deduplicate identical entries', () {
    store.actions.dashboardActions.loaded(
      DaysLoadedPayload(
        (b) => b
          ..future = false
          ..markNewOrChangedEntries = false
          ..deduplicateEntries = true
          ..data = <Object>[
            <String, Object?>{
              'date': '2026-03-28',
              'items': <Object>[
                <String, Object?>{
                  'id': 1,
                  'type': 'lessonHomework',
                  'title': 'Arbeitsblatt',
                  'subtitle': 'Mathematik',
                  'label': 'Mathematik',
                  'warning': false,
                  'checkable': true,
                  'checked': false,
                  'deleteable': false,
                },
                <String, Object?>{
                  'id': 1,
                  'type': 'lessonHomework',
                  'title': 'Arbeitsblatt',
                  'subtitle': 'Mathematik',
                  'label': 'Mathematik',
                  'warning': false,
                  'checkable': true,
                  'checked': false,
                  'deleteable': false,
                },
              ],
            },
          ],
      ),
    );

    expect(store.state.dashboardState.allDays, hasLength(1));
    expect(store.state.dashboardState.allDays!.single.homework, hasLength(1));
    expect(
      store.state.dashboardState.allDays!.single.homework.single.title,
      'Arbeitsblatt',
    );
  });

  test('grade parsing keeps semester data separate', () {
    store.actions.gradesActions.loaded(
      SubjectsLoadedPayload(
        (b) => b
          ..semester = Semester.first.toBuilder()
          ..data = <String, Object?>{
            'subjects': <Object>[
              <String, Object?>{
                'subject': <String, Object?>{'id': 1, 'name': 'Deutsch'},
                'grades': <Object>[
                  <String, Object?>{
                    'grade': '8.00',
                    'weight': 100,
                    'date': '2026-02-01',
                    'cancelled': 0,
                    'type': 'Schularbeit',
                  },
                ],
              },
            ],
          },
      ),
    );

    store.actions.gradesActions.loaded(
      SubjectsLoadedPayload(
        (b) => b
          ..semester = Semester.second.toBuilder()
          ..data = <String, Object?>{
            'subjects': <Object>[
              <String, Object?>{
                'subject': <String, Object?>{'id': 1, 'name': 'Deutsch'},
                'grades': <Object>[
                  <String, Object?>{
                    'grade': '7.50',
                    'weight': 100,
                    'date': '2026-03-01',
                    'cancelled': 0,
                    'type': 'Test',
                  },
                ],
              },
            ],
          },
      ),
    );

    final subject = store.state.gradesState.subjects.single;
    expect(subject.gradesAll[Semester.first], hasLength(1));
    expect(subject.gradesAll[Semester.second], hasLength(1));
    expect(subject.gradesAll[Semester.first]!.single.grade, 800);
    expect(subject.gradesAll[Semester.second]!.single.grade, 750);
  });

  test('setConfig aligns the visible semester with the server semester', () {
    store.actions.setConfig(
      Config(
        (b) => b
          ..userId = 1
          ..autoLogoutSeconds = 300
          ..fullName = 'Test User'
          ..imgSource = 'https://example.com/profile.png'
          ..isStudentOrParent = true
          ..currentSemesterMaybe = 2,
      ),
    );

    expect(store.state.gradesState.semester, Semester.second);
  });

  test('profile parsing keeps notification setting as bool', () {
    store.actions.profileActions.loaded(
      <String, Object?>{
        'name': 'Anna Rossi',
        'email': 'anna@example.com',
        'username': 'anna',
        'roleName': 'Schüler/in',
        'notificationsEnabled': 1,
      },
    );

    expect(store.state.profileState.sendNotificationEmails, isTrue);
    expect(store.state.profileState.username, 'anna');
  });
}
