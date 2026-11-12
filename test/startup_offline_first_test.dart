import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dr/middleware/middleware.dart' as middleware;
import 'package:dr/ui/launch/app_launch_animation.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

const _configPage = '''
<script>var currentUserId=3539;
var config = { auto_logout_seconds: 300, };</script>
<img id="navigationProfilePicture" src="profile.png">Test User<
''';

/// A school server that holds every sign-in until [release] completes, like a
/// server that takes up to its request timeouts to answer.
class _SlowSignInServer implements HttpClientAdapter {
  final release = Completer<void>();
  final signInRequested = Completer<void>();
  bool fail = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('api/auth/login')) {
      if (!signInRequested.isCompleted) signInRequested.complete();
      await release.future;
      if (fail) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.receiveTimeout);
      }
      return ResponseBody.fromString(jsonEncode({'loggedIn': true}), 200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'set-cookie': ['session=test; Path=/']
          });
    }
    if (options.path.endsWith('/v2/')) {
      return ResponseBody.fromString(_configPage, 200, headers: {
        Headers.contentTypeHeader: ['text/html']
      });
    }
    return ResponseBody.fromString('null', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

// Kept across the account load like the mocks of other start-up tests.
class _Session extends Wrapper with Mock {
  @override
  Future<bool> refreshNoInternet() async => noInternet = false;
}

Future<(_Session, _SlowSignInServer)> _savedLogin() async {
  final server = _SlowSignInServer();
  final session = _Session()..safeMode = false;
  session.dio.httpClientAdapter = server;
  await bootstrapTestEnvironment(
    wrapperOverride: session,
    storage: {
      'login': jsonEncode({
        'user': 'user',
        'pass': 'password',
        'url': testServerUrl,
        'otherAccounts': <Object>[],
      }),
    },
  );
  middleware.wrapper = session;
  appLaunchGate.resetForTest();
  addTearDown(() => session.logout(hard: true));
  return (session, server);
}

void main() {
  tearDown(resetTestState);

  test('a saved login uncovers its saved data before the server answers',
      () async {
    final (_, server) = await _savedLogin();
    final store = createStore(withMiddleware: true);

    final start = store.actions.start(null);
    await server.signInRequested.future;
    await appLaunchGate.opened.timeout(const Duration(seconds: 5));
    // Signed in from storage; the online sign-in is still waiting.
    expect(store.state.loginState.loggedIn, isTrue);
    expect(store.state.config, isNull);

    server.release.complete();
    await start;
    expect(store.state.loginState.loggedIn, isTrue);
    expect(store.state.config?.userId, 3539);
  });

  test('a saved login stays usable offline when the server times out',
      () async {
    final (_, server) = await _savedLogin();
    server.fail = true;
    final store = createStore(withMiddleware: true);

    final start = store.actions.start(null);
    await server.signInRequested.future;
    await appLaunchGate.opened.timeout(const Duration(seconds: 5));
    expect(store.state.loginState.loggedIn, isTrue);

    server.release.complete();
    await start;
    expect(store.state.loginState.loggedIn, isTrue);
    expect(store.state.noInternet, isTrue);
  });

  test('without a saved login the gate opens for the login page', () async {
    await bootstrapTestEnvironment();
    appLaunchGate.resetForTest();
    final store = createStore(withMiddleware: true);
    await store.actions.start(null);
    expect(appLaunchGate.isOpen, isTrue);
    expect(store.state.loginState.loggedIn, isFalse);
  });
}
