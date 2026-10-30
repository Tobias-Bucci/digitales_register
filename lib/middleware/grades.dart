// Copyright (C) 2021 Michael Debertol
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

part of 'middleware.dart';

final _gradesMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(GradesActionsNames.setSemester, _setSemester)
      ..add(GradesActionsNames.load, _loadGrades)
      ..add(GradesActionsNames.loadDetails, _loadGradesDetails)
      ..add(
        GradesActionsNames.loadCancelledDescription,
        _loadCancelledDescription,
      );

final _gradesLock = SemesterLock((s) async {
  await wrapper.send("?semesterWechsel=${s.n}");
});

const String _subjects = "api/student/all_subjects";
const String _subjectsDetail = "api/student/subject_detail";
const String _grade = "api/student/entry/getGrade";

Future<void> _setSemester(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Semester> action,
) async {
  await next(action);
  await api.actions.gradesActions.load(action.payload);
}

Future<void> _loadGrades(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Semester> action,
) async {
  if (api.state.noInternet) return;

  final semesters = _semestersFor(action.payload);
  final staleSemesters = semesters
      .where((semester) => !_hasFreshBasicGrades(api.state, semester))
      .toList();
  if (staleSemesters.isEmpty) {
    unawaited(AnalyticsService.product
        .event('cache_result', {'feature': 'grades', 'result': 'hit'}));
    await submitAcademicSummary(api.state);
    return;
  }

  final session = _Session.capture();
  await next(action);
  await _doForSemester(session, staleSemesters, (s) async {
    final product = AnalyticsService.product;
    final localOwner = jsonEncode([wrapper.url, api.state.loginState.username]);
    final epoch = product.sessionEpoch;
    final stopwatch = Stopwatch()..start();
    final dynamic data = await session.send(
      _subjects,
      args: {"studentId": api.state.config!.userId},
    );
    if (data == null) {
      if (product.isSession(epoch)) {
        unawaited(product.event('refresh_result', {
          'feature': 'grades',
          'result': 'failed',
          'data_source': 'unknown',
          'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
        }));
      }
      await api.actions.gradesActions.loadFailed();
      return;
    }
    product.gradeOwnership.mark(s.n.toString(), localOwner);
    try {
      await api.actions.gradesActions.loaded(
        SubjectsLoadedPayload(
          (b) => b
            ..data = data
            ..semester = s.toBuilder(),
        ),
      );
    } catch (_) {
      product.gradeOwnership.invalidate(s.n.toString());
      rethrow;
    }
    if (product.isSession(epoch)) {
      unawaited(product.event('refresh_result', {
        'feature': 'grades',
        'result': 'success',
        'data_source': wrapper.demoMode ? 'local' : 'remote',
        'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
      }));
    }
  });
}

Future<void> _loadGradesDetails(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<LoadSubjectDetailsPayload> action,
) async {
  final semesters = _semestersFor(action.payload.semester);
  await _rememberViewedGradeDetails(
      api.state, action.payload.subject.id, semesters);
  if (api.state.noInternet) return;
  final staleSemesters = semesters
      .where(
        (semester) => !_hasFreshDetailedGrades(
          api.state,
          action.payload.subject.id,
          semester,
        ),
      )
      .toList();
  if (staleSemesters.isEmpty) {
    return;
  }

  final session = _Session.capture();
  await next(action);

  await _doForSemester(session, staleSemesters, (s) async {
    dynamic data = await session.send(
      _subjectsDetail,
      args: {
        "studentId": api.state.config!.userId,
        "subjectId": action.payload.subject.id,
      },
    );
    if (data == null) {
      return;
    }
    if (data is String) {
      data = json.decode(data);
    }
    await api.actions.gradesActions.detailsLoaded(
      SubjectDetailLoadedPayload(
        (b) => b
          ..data = data
          ..semester = s.toBuilder()
          ..subject = action.payload.subject.toBuilder(),
      ),
    );
    await _rememberViewedGradeDetails(
        api.state, action.payload.subject.id, [s]);
    for (final grade in api.state.gradesState.subjects
        .firstWhere((s) => s.id == action.payload.subject.id)
        .grades[s]!
        .where((g) => g.cancelled && g.cancelledDescription == null)) {
      await api.actions.gradesActions.loadCancelledDescription(
        LoadGradeCancelledDescriptionPayload(
          (b) => b
            ..semester = s.toBuilder()
            ..grade = grade.toBuilder(),
        ),
      );
    }
  });
}

Future<void> _rememberViewedGradeDetails(
    AppState state, int? subjectId, Iterable<Semester> semesters) async {
  if (wrapper.url == null || wrapper.user == null || wrapper.demoMode) return;
  final subject =
      state.gradesState.subjects.where((s) => s.id == subjectId).firstOrNull;
  if (subject == null) return;
  final items = semesters
      .expand((semester) => subject.grades[semester] ?? <GradeDetail>[])
      .map((grade) => <String, Object?>{
            'type': 'grade',
            'objectId': grade.id,
            'timeSent': DateTime.now().toIso8601String()
          })
      .toList();
  if (items.isEmpty) return;
  await schoolNotificationOperation(
      () => schoolNotifications.markViewed(wrapper.url!, wrapper.user!, items));
}

List<Semester> _semestersFor(Semester semester) {
  return semester == Semester.all
      ? [Semester.first, Semester.second]
      : [semester];
}

Subject? _findSubject(AppState state, int? subjectId) {
  if (subjectId == null) {
    return null;
  }
  for (final subject in state.gradesState.subjects) {
    if (subject.id == subjectId) {
      return subject;
    }
  }
  return null;
}

bool _hasFreshBasicGrades(AppState state, Semester semester) {
  // Subjects that only belong to the other semester carry no timestamp for
  // this one and must not make it look stale forever.
  final subjects = state.gradesState.subjects
      .where((subject) => subject.gradesAll.containsKey(semester));
  if (subjects.isEmpty) {
    return false;
  }
  final timestamps = subjects.map((subject) => subject.lastFetchedBasic);
  if (timestamps.any(
    (fetched) => fetched == null || fetched[semester] == null,
  )) {
    return false;
  }
  return timestamps.every(
    (fetched) => _isFresh(fetched![semester], _gradesCacheTtl),
  );
}

bool _hasFreshDetailedGrades(
  AppState state,
  int? subjectId,
  Semester semester,
) {
  final subject = _findSubject(state, subjectId);
  if (subject == null) {
    return false;
  }
  return subject.grades[semester] != null &&
      subject.observations[semester] != null &&
      _isFresh(subject.lastFetchedDetailed?[semester], _gradesCacheTtl);
}

Future<void> _loadCancelledDescription(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<LoadGradeCancelledDescriptionPayload> action,
) async {
  if (api.state.noInternet) return;

  final session = _Session.capture();
  await next(action);
  await _doForSemester(session, [action.payload.semester], (s) async {
    final dynamic data = await session.send(
      _grade,
      args: {"gradeId": action.payload.grade.id},
    );
    if (data == null) {
      return;
    }
    await api.actions.gradesActions.cancelledDescriptionLoaded(
      GradeCancelledDescriptionLoadedPayload(
        (b) => b
          ..grade = action.payload.grade.toBuilder()
          ..semester = action.payload.semester.toBuilder()
          ..data = data,
      ),
    );
  });
}

Future<void> _doForSemester(
  _Session session,
  List<Semester> semesters,
  Future<void> Function(Semester s) f,
) async {
  final ordered = [...semesters];
  final current = _gradesLock.current;
  if (ordered.remove(current)) ordered.insert(0, current!);
  for (final semester in ordered) {
    await _gradesLock.synchronized(
      semester,
      () => f(semester),
      // A job that waited for its turn may belong to an account the app has
      // left: it must not switch the semester of whoever is signed in now.
      beforeSwitch: session.ensureCurrent,
    );
  }
}

typedef SemesterChangeCallback = Future<void> Function(Semester semester);

/// Serializes work that depends on the server-side semester selection.
///
/// Any number of callers may run concurrently for the [current] semester;
/// callers for another semester wait until it is idle and then switch. Every
/// caller's future completes with the result of its own work (or of a failed
/// switch), and failures always release the lock so later work can proceed.
class SemesterLock {
  /// The semester the server is known to be switched to, or `null` while it
  /// is unknown (initially, after [reset] and after a failed switch).
  Semester? current;
  int usersOfCurrent = 0;
  final SemesterChangeCallback semesterChangeCallback;
  SemesterLock(this.semesterChangeCallback);
  final _mutex = Mutex();
  final Map<Semester, List<Completer<void>>> waitlist = {};

  /// Runs [f] while the server is on [semester].
  ///
  /// [beforeSwitch] runs right before the server is switched, after any wait
  /// for other semesters. If it throws, nothing is switched and [f] does not
  /// run; the error reaches the caller and later callers proceed.
  Future<void> synchronized(
    Semester semester,
    Future<void> Function() f, {
    void Function()? beforeSwitch,
  }) async {
    await _enter(semester, beforeSwitch);
    try {
      await f();
    } finally {
      usersOfCurrent--;
      _wakeWaitersIfIdle();
    }
  }

  /// Forgets the known server semester, e.g. because the session changed.
  /// The next caller switches again.
  void reset() {
    current = null;
  }

  Future<void> _enter(Semester semester, void Function()? beforeSwitch) async {
    while (true) {
      final Future<void> turn;
      await _mutex.acquire();
      try {
        if (usersOfCurrent == 0 || semester == current) {
          if (semester != current) {
            try {
              beforeSwitch?.call();
            } catch (_) {
              _wakeWaitersIfIdle();
              rethrow;
            }
            current = null;
            try {
              await semesterChangeCallback(semester);
            } catch (_) {
              _wakeWaitersIfIdle();
              rethrow;
            }
            current = semester;
          }
          usersOfCurrent++;
          return;
        }
        final waiter = Completer<void>();
        (waitlist[semester] ??= []).add(waiter);
        turn = waiter.future;
      } finally {
        _mutex.release();
      }
      await turn;
    }
  }

  /// Lets the callers for the next waiting semester retry once nobody uses
  /// the current one anymore.
  void _wakeWaitersIfIdle() {
    if (usersOfCurrent != 0 || waitlist.isEmpty) return;
    final next = waitlist.keys.first;
    for (final waiter in waitlist.remove(next)!) {
      waiter.complete();
    }
  }
}
