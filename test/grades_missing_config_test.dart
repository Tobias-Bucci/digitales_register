import 'dart:async';

import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

/// A saved login first signs in offline; the server config, which holds the
/// student id, arrives only with the online sign-in. Grade loads started in
/// between crashed on `config!` (Crashlytics 0a322133 and d0db287d, #23).
class _PendingSignIn extends Wrapper {
  final signIn = Completer<bool>();
  // Requests for a student's grades; the semester switch carries no id.
  final requests = <Map<String, Object?>>[];

  @override
  Future<bool> get loggedIn => signIn.future;

  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    if (args.containsKey('studentId')) requests.add(args);
    return null;
  }
}

final _config = Config((c) => c
  ..userId = 42
  ..autoLogoutSeconds = 300
  ..fullName = ''
  ..imgSource = ''
  ..isStudentOrParent = true);

final _subject = Subject((s) => s
  ..id = 1
  ..name = 'Mathe');

AppState _signedInWithoutConfig() => AppState((b) => b
  ..loginState.loggedIn = true
  ..loginState.username = 'test');

void main() {
  tearDown(resetTestState);

  test('grade list load without config fails instead of throwing', () async {
    final session = _PendingSignIn()..signIn.complete(false);
    await bootstrapTestEnvironment(wrapperOverride: session);
    final store = createStore(
        initialState: _signedInWithoutConfig(), withMiddleware: true);
    await store.actions.gradesActions.load(Semester.first);
    expect(session.requests, isEmpty);
    expect(store.state.gradesState.loading, isFalse);
  });

  test('grade details load without config returns instead of throwing',
      () async {
    final session = _PendingSignIn()..signIn.complete(false);
    await bootstrapTestEnvironment(wrapperOverride: session);
    final store = createStore(
        initialState: _signedInWithoutConfig(), withMiddleware: true);
    await store.actions.gradesActions
        .loadDetails(LoadSubjectDetailsPayload((b) => b
          ..semester = Semester.first.toBuilder()
          ..subject.replace(_subject)));
    expect(session.requests, isEmpty);
  });

  test('grade load waits for a running sign-in and uses its student id',
      () async {
    final session = _PendingSignIn();
    await bootstrapTestEnvironment(wrapperOverride: session);
    final store = createStore(
        initialState: _signedInWithoutConfig(), withMiddleware: true);
    final pending = store.actions.gradesActions.load(Semester.first);
    await Future<void>.delayed(Duration.zero);
    expect(session.requests, isEmpty);
    await store.actions.setConfig(_config);
    session.signIn.complete(true);
    await pending;
    expect(session.requests.single['studentId'], 42);
  });
}
