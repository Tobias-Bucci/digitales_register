import 'dart:async';
import 'package:dr/app_state.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_harness.dart';

class _DelayedGrades extends Wrapper {
  final requested = Completer<void>();
  final release = Completer<void>();
  int requests = 0;
  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    if (url == 'api/student/all_subjects') {
      requests++;
      if (!requested.isCompleted) requested.complete();
      await release.future;
      return <String, dynamic>{'subjects': <dynamic>[]};
    }
    return null;
  }
}

void main() {
  tearDown(resetTestState);
  test('grades load future waits for both semester responses', () async {
    final session = _DelayedGrades();
    await bootstrapTestEnvironment(wrapperOverride: session);
    final state = AppState((b) => b
      ..loginState.loggedIn = true
      ..loginState.username = 'test'
      ..config.replace(Config((c) => c
        ..userId = 1
        ..autoLogoutSeconds = 300
        ..fullName = ''
        ..imgSource = ''
        ..isStudentOrParent = true)));
    final store = createStore(initialState: state, withMiddleware: true);
    var finished = false;
    final pending = store.actions.gradesActions
        .load(Semester.all)
        .then((_) => finished = true);
    await session.requested.future;
    expect(finished, isFalse);
    session.release.complete();
    await pending;
    expect(session.requests, 2);
    expect(store.state.gradesState.loading, isFalse);
  });
}
