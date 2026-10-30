import 'dart:async';

import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

const _timeout = Duration(seconds: 2);

class _GradesSession extends Wrapper {
  final requests = <String>[];
  Object? switchError;
  dynamic subjects = <String, dynamic>{'subjects': <dynamic>[]};

  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    requests.add(url);
    if (url.startsWith('?semesterWechsel')) {
      final error = switchError;
      switchError = null;
      if (error != null) throw error;
      return null;
    }
    if (url == 'api/student/all_subjects') return subjects;
    return null;
  }
}

void main() {
  group('SemesterLock', () {
    late List<Semester> switches;
    late Object? failNextSwitch;
    late SemesterLock lock;

    setUp(() {
      switches = [];
      failNextSwitch = null;
      lock = SemesterLock((s) async {
        switches.add(s);
        final error = failNextSwitch;
        failNextSwitch = null;
        if (error != null) throw error;
      });
    });

    Future<bool> runs(Semester semester) async {
      var ran = false;
      await lock
          .synchronized(semester, () async => ran = true)
          .timeout(_timeout);
      return ran;
    }

    test('a failed switch is released and retried by the next caller',
        () async {
      failNextSwitch = StateError('switch failed');
      await expectLater(
        lock.synchronized(Semester.first, () async {}).timeout(_timeout),
        throwsStateError,
      );
      expect(lock.current, isNull);
      expect(lock.usersOfCurrent, 0);

      expect(await runs(Semester.first), isTrue);
      expect(switches, [Semester.first, Semester.first]);
      expect(lock.current, Semester.first);
    });

    for (final (name, error) in [
      ('request', StateError('request failed')),
      ('parser', const FormatException('malformed grade')),
    ]) {
      test('a $name failure releases the lock for another semester', () async {
        await expectLater(
          lock
              .synchronized(Semester.first, () async => throw error)
              .timeout(_timeout),
          throwsA(same(error)),
        );
        expect(lock.usersOfCurrent, 0);

        expect(await runs(Semester.second), isTrue);
        expect(switches, [Semester.first, Semester.second]);
      });
    }

    test('queued callers settle when the running work fails', () async {
      final release = Completer<void>();
      final running = lock.synchronized(Semester.first, () async {
        await release.future;
        throw StateError('work failed');
      });
      await Future<void>.delayed(Duration.zero);
      var queuedRan = false;
      final queued =
          lock.synchronized(Semester.second, () async => queuedRan = true);
      await Future<void>.delayed(Duration.zero);
      expect(queuedRan, isFalse);

      release.complete();
      await expectLater(running.timeout(_timeout), throwsStateError);
      await queued.timeout(_timeout);
      expect(queuedRan, isTrue);
      expect(lock.waitlist, isEmpty);
    });

    test('a failed switch of a woken caller still wakes later semesters',
        () async {
      final release = Completer<void>();
      final running = lock.synchronized(Semester.first, () => release.future);
      await Future<void>.delayed(Duration.zero);
      final second = lock.synchronized(Semester.second, () async {});
      final all = <bool>[];
      final third = lock.synchronized(Semester.all, () async => all.add(true));
      await Future<void>.delayed(Duration.zero);

      failNextSwitch = StateError('switch failed');
      release.complete();
      await running.timeout(_timeout);
      await expectLater(second.timeout(_timeout), throwsStateError);
      await third.timeout(_timeout);
      expect(all, [true]);
      expect(lock.usersOfCurrent, 0);
      expect(lock.waitlist, isEmpty);
    });

    test('a caller that is refused before switching changes nothing', () async {
      final release = Completer<void>();
      final running = lock.synchronized(Semester.first, () => release.future);
      await Future<void>.delayed(Duration.zero);
      var refusedRan = false;
      final refused = lock.synchronized(
        Semester.second,
        () async => refusedRan = true,
        beforeSwitch: () => throw StateError('left the account'),
      );
      var laterRan = false;
      final later =
          lock.synchronized(Semester.all, () async => laterRan = true);
      await Future<void>.delayed(Duration.zero);

      release.complete();
      await running.timeout(_timeout);
      await expectLater(refused.timeout(_timeout), throwsStateError);
      await later.timeout(_timeout);

      expect(refusedRan, isFalse);
      expect(laterRan, isTrue);
      expect(switches, [Semester.first, Semester.all]);
      expect(lock.usersOfCurrent, 0);
      expect(lock.waitlist, isEmpty);
    });

    test('reset forces a new switch for the next session', () async {
      expect(await runs(Semester.first), isTrue);
      expect(await runs(Semester.first), isTrue);
      expect(switches, [Semester.first]);

      lock.reset();
      expect(await runs(Semester.first), isTrue);
      expect(switches, [Semester.first, Semester.first]);
    });
  });

  group('grades middleware', () {
    tearDown(resetTestState);

    AppState loggedIn() => AppState((b) => b
      ..loginState.loggedIn = true
      ..loginState.username = 'test'
      ..config.replace(Config((c) => c
        ..userId = 1
        ..autoLogoutSeconds = 300
        ..fullName = ''
        ..imgSource = ''
        ..isStudentOrParent = true)));

    test('a failed semester switch does not block later grade loads', () async {
      final session = _GradesSession()
        ..switchError = UnexpectedLogoutException();
      await bootstrapTestEnvironment(wrapperOverride: session);
      final store = createStore(initialState: loggedIn(), withMiddleware: true);
      addTearDown(store.dispose);

      await expectLater(
        store.actions.gradesActions.load(Semester.first).timeout(_timeout),
        throwsA(isA<UnexpectedLogoutException>()),
      );
      session.requests.clear();

      await store.actions.gradesActions.load(Semester.second).timeout(_timeout);
      expect(session.requests, [
        '?semesterWechsel=2',
        'api/student/all_subjects',
      ]);
      expect(store.state.gradesState.loading, isFalse);
    });

    test('malformed grade data does not block later grade loads', () async {
      final session = _GradesSession()..subjects = {'subjects': 'malformed'};
      await bootstrapTestEnvironment(wrapperOverride: session);
      final store = createStore(initialState: loggedIn(), withMiddleware: true);
      addTearDown(store.dispose);

      await expectLater(
        store.actions.gradesActions.load(Semester.first).timeout(_timeout),
        throwsA(anything),
      );
      session
        ..requests.clear()
        ..subjects = <String, dynamic>{'subjects': <dynamic>[]};

      await store.actions.gradesActions.load(Semester.second).timeout(_timeout);
      expect(session.requests, [
        '?semesterWechsel=2',
        'api/student/all_subjects',
      ]);
    });
  });
}
