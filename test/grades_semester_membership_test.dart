import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

Map<String, Object> _subject(int id, String name,
        {String date = '2026-01-15', String grade = '8'}) =>
    {
      'subject': {'id': id, 'name': name},
      'grades': [
        {
          'grade': grade,
          'weight': 100,
          'date': date,
          'cancelled': 0,
          'type': 'Test',
        },
      ],
      'absences': 1,
    };

Map<String, Object> _detail({String date = '2026-01-15'}) => {
      'grades': [
        {
          'grade': '8',
          'weight': 100,
          'date': date,
          'cancelled': 0,
          'typeName': 'Test',
          'created': 'x',
          'name': 'Detail',
          'description': '',
          'id': 7,
          'competences': <Object>[],
        },
      ],
      'observations': <Object>[],
    };

Future<void> _load(
  Store<AppState, AppStateBuilder, AppActions> store,
  Semester semester,
  List<Map<String, Object>> subjects,
) {
  return store.actions.gradesActions.loaded(
    SubjectsLoadedPayload(
      (b) => b
        ..semester.replace(semester)
        ..data = {'subjects': subjects},
    ),
  );
}

Subject? _byName(Store<AppState, AppStateBuilder, AppActions> store, String n) {
  for (final subject in store.state.gradesState.subjects) {
    if (subject.name == n) return subject;
  }
  return null;
}

class _SemesterServer extends Wrapper {
  _SemesterServer(this.subjectsBySemester);

  final Map<int, List<Map<String, Object>>> subjectsBySemester;
  int current = 1;
  final requests = <int>[];

  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    if (url.startsWith('?semesterWechsel=')) {
      current = int.parse(url.split('=').last);
      return '';
    }
    if (url == 'api/student/all_subjects') {
      requests.add(current);
      return <String, dynamic>{'subjects': subjectsBySemester[current]};
    }
    return null;
  }
}

void main() {
  tearDown(resetTestState);

  test('U08 a second semester refresh keeps first-only subjects and grades',
      () async {
    final store = createStore();
    await _load(store, Semester.first,
        [_subject(1, 'First-only'), _subject(2, 'Shared')]);
    await _load(store, Semester.second, [_subject(2, 'Shared')]);

    final firstOnly = _byName(store, 'First-only')!;
    expect(firstOnly.gradesAll.keys, [Semester.first]);
    expect(firstOnly.gradesAll[Semester.first], hasLength(1));
    expect(firstOnly.absences[Semester.first], 1);
    expect(firstOnly.basicGrades(Semester.all), hasLength(1));
    final shared = _byName(store, 'Shared')!;
    expect(shared.gradesAll.keys,
        unorderedEquals([Semester.first, Semester.second]));
    await store.dispose();
  });

  test('first-only and second-only subjects both survive alternating refreshes',
      () async {
    final store = createStore();
    final first = [_subject(1, 'First-only'), _subject(2, 'Shared')];
    final second = [
      _subject(2, 'Shared', date: '2026-03-01'),
      _subject(3, 'Second-only', date: '2026-03-01'),
    ];
    await _load(store, Semester.first, first);
    await _load(store, Semester.second, second);
    // Switch back and forth: no refresh may drop the other semester's data.
    await _load(store, Semester.first, first);
    await _load(store, Semester.second, second);

    expect(store.state.gradesState.subjects.map((s) => s.name),
        unorderedEquals(['First-only', 'Shared', 'Second-only']));
    expect(_byName(store, 'First-only')!.gradesAll.keys, [Semester.first]);
    expect(_byName(store, 'Second-only')!.gradesAll.keys, [Semester.second]);
    expect(_byName(store, 'Shared')!.basicGrades(Semester.all), hasLength(2));
    await store.dispose();
  });

  test('a subject dropped from one semester keeps its other semester data',
      () async {
    final store = createStore();
    await _load(store, Semester.first, [_subject(2, 'Shared')]);
    await _load(store, Semester.second,
        [_subject(2, 'Shared', date: '2026-03-01')]);
    await store.actions.gradesActions.detailsLoaded(
      SubjectDetailLoadedPayload(
        (b) => b
          ..data = _detail(date: '2026-03-01')
          ..semester.replace(Semester.second)
          ..subject.replace(_byName(store, 'Shared')!),
      ),
    );
    await store.actions.gradesActions.detailsLoaded(
      SubjectDetailLoadedPayload(
        (b) => b
          ..data = _detail()
          ..semester.replace(Semester.first)
          ..subject.replace(_byName(store, 'Shared')!),
      ),
    );

    // The school removed the course for the second semester only.
    await _load(store, Semester.second,
        [_subject(4, 'Replacement', date: '2026-03-01')]);

    final shared = _byName(store, 'Shared')!;
    expect(shared.gradesAll.keys, [Semester.first]);
    expect(shared.grades.keys, [Semester.first]);
    expect(shared.observations.keys, [Semester.first]);
    expect(shared.absences.keys, [Semester.first]);
    expect(shared.lastFetchedDetailed!.keys, [Semester.first]);
    expect(shared.basicGrades(Semester.second), isNull);
    await store.dispose();
  });

  test('a subject that belongs to no semester anymore is removed', () async {
    final store = createStore();
    await _load(store, Semester.first,
        [_subject(1, 'First-only'), _subject(2, 'Shared')]);
    await _load(store, Semester.second, [_subject(2, 'Shared')]);
    await _load(store, Semester.first, [_subject(2, 'Shared')]);

    expect(store.state.gradesState.subjects.map((s) => s.name), ['Shared']);
    await store.dispose();
  });

  test('grades of a new school year reset the subjects of the old year',
      () async {
    final store = createStore();
    await _load(store, Semester.first, [
      _subject(1, 'Old first-only', date: '2025-11-01'),
      _subject(2, 'Shared', date: '2025-11-01'),
    ]);
    await _load(store, Semester.second, [
      _subject(2, 'Shared', date: '2026-03-01'),
      _subject(3, 'Old second-only', date: '2026-03-01'),
    ]);

    await _load(store, Semester.first, [
      _subject(2, 'Shared', date: '2026-10-05'),
      _subject(5, 'New', date: '2026-10-05'),
    ]);

    expect(store.state.gradesState.subjects.map((s) => s.name),
        unorderedEquals(['Shared', 'New']));
    final shared = _byName(store, 'Shared')!;
    expect(shared.gradesAll.keys, [Semester.first]);
    expect(shared.basicGrades(Semester.all)!.single.date.year, 2026);
    await store.dispose();
  });

  test('a semester without grades does not trigger a school year reset',
      () async {
    final store = createStore();
    await _load(store, Semester.first,
        [_subject(1, 'First-only', date: '2025-11-01')]);
    await _load(store, Semester.second, [
      {
        'subject': {'id': 2, 'name': 'Empty'},
        'grades': <Object>[],
        'absences': 0,
      },
    ]);

    expect(store.state.gradesState.subjects.map((s) => s.name),
        unorderedEquals(['First-only', 'Empty']));
    await store.dispose();
  });

  test('switching accounts still replaces the whole subject universe',
      () async {
    final store = createStore();
    await _load(store, Semester.first, [_subject(1, 'Other account')]);
    await store.actions.mountAppState(AppState());
    await _load(store, Semester.second, [_subject(2, 'Mine')]);

    expect(store.state.gradesState.subjects.map((s) => s.name), ['Mine']);
    await store.dispose();
  });

  test('first-only subjects do not keep the second semester cache stale',
      () async {
    final server = _SemesterServer({
      1: [_subject(1, 'First-only'), _subject(2, 'Shared')],
      2: [_subject(2, 'Shared', date: '2026-03-01')],
    });
    await bootstrapTestEnvironment(wrapperOverride: server);
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'test'
        ..config.replace(Config((c) => c
          ..userId = 1
          ..autoLogoutSeconds = 300
          ..fullName = ''
          ..imgSource = ''
          ..isStudentOrParent = true))),
    );

    // Newly added subjects carry no fetch timestamp yet, so it takes two
    // loads until every semester is cached.
    await store.actions.gradesActions.load(Semester.all);
    await store.actions.gradesActions.load(Semester.all);
    server.requests.clear();
    await store.actions.gradesActions.load(Semester.all);

    expect(server.requests, isEmpty);
    expect(_byName(store, 'First-only'), isNotNull);
    await store.dispose();
  });
}
