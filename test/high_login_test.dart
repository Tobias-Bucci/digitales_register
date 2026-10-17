import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart' as middleware;
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

class TestLoginWrapper extends Wrapper {
  // Connectivity probing is a separate service; keep these tests deterministic.
  @override
  Future<bool> refreshNoInternet() async => noInternet = false;
}

class ThrowingLoginWrapper extends TestLoginWrapper {
  @override
  Future<dynamic> login(
      String? user, String? pass, String? tfaCode, String? url,
      {void Function()? logout,
      Future<void>? Function()? configLoaded,
      void Function()? relogin,
      AddNetworkProtocolItem? addProtocolItem}) async {
    throw StateError('Unexpected session initialization failure');
  }
}

const configPage = '''
<script>var currentUserId=3539;
var config = { auto_logout_seconds: 300, };</script>
<img id="navigationProfilePicture" src="profile.png">Test User<
''';

class LoginAdapter implements HttpClientAdapter {
  Object? configFailure;
  bool rejected = false;
  bool malformedCredentials = false;
  Exception? credentialFailure;
  int loginRequests = 0;
  final configGate = Completer<void>();
  final configRequested = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('api/auth/login')) {
      loginRequests++;
      if (credentialFailure != null) throw credentialFailure!;
      return ResponseBody.fromString(
          malformedCredentials ? '{' : jsonEncode({'loggedIn': !rejected}), 200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'set-cookie': ['session=test; Path=/']
          });
    }
    if (options.path.endsWith('/v2/')) {
      if (!configRequested.isCompleted) configRequested.complete();
      await configGate.future;
      final failure = configFailure;
      if (failure is Exception) throw failure;
      return ResponseBody.fromString(
          failure is String ? failure : configPage, 200,
          headers: {
            Headers.contentTypeHeader: ['text/html']
          });
    }
    // Post-login data loads are independent of session construction.
    return ResponseBody.fromString('null', 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  test('middleware catches unexpected initialization errors exactly once',
      () async {
    final session = ThrowingLoginWrapper()..safeMode = false;
    session.dio.httpClientAdapter = LoginAdapter();
    middleware.wrapper = session;
    final store = createStore(withMiddleware: true);
    var failures = 0;
    final subscription = store
        .actionStream(LoginActionsNames.loginFailed)
        .listen((_) => failures++);
    addTearDown(subscription.cancel);
    await store.actions.loginActions.login(LoginPayload((b) => b
      ..user = 'user'
      ..pass = 'password'
      ..url = testServerUrl
      ..fromStorage = false));
    expect(store.state.loginState.loading, false);
    expect(store.state.loginState.loggedIn, false);
    expect(store.state.loginState.errorMsg, isNotEmpty);
    expect(await session.loggedIn, false);
    expect(session.user, isNull);
    expect(session.pass, isNull);
    expect(failures, 1);
  });

  for (final failure in <Object>[
    '',
    '{invalid JSON',
    '<html>unexpected data</html>',
    const FormatException('config parsing'),
    TimeoutException('config timeout'),
    DioException(
        requestOptions: RequestOptions(path: 'config'),
        type: DioExceptionType.connectionError),
    DioException(
        requestOptions: RequestOptions(path: 'config'),
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: RequestOptions(path: 'config'), statusCode: 500)),
  ]) {
    test('config failure ends loading and retry succeeds: $failure', () async {
      final session = TestLoginWrapper()..safeMode = false;
      final adapter = LoginAdapter()..configFailure = failure;
      session.dio.httpClientAdapter = adapter;
      middleware.wrapper = session;
      addTearDown(() => session.logout(hard: true));
      final store = createStore(withMiddleware: true);
      var failures = 0;
      final subscription = store
          .actionStream(LoginActionsNames.loginFailed)
          .listen((_) => failures++);
      addTearDown(subscription.cancel);
      final payload = LoginPayload((b) => b
        ..user = 'user'
        ..pass = 'password'
        ..url = testServerUrl
        ..fromStorage = false);
      final pending = store.actions.loginActions.login(payload);
      await adapter.configRequested.future;
      expect(store.state.loginState.loading, true);
      adapter.configGate.complete();
      await pending;
      expect(store.state.loginState.loading, false);
      expect(store.state.loginState.loggedIn, false);
      expect(store.state.loginState.errorMsg, isNotEmpty);
      expect(await session.loggedIn, false);
      expect(session.sessionRefreshScheduled, false);
      expect(await session.cookieJar.loadForRequest(Uri.parse(testServerUrl)),
          isEmpty);
      expect(failures, 1);
      adapter.configFailure = null;
      await store.actions.loginActions.login(payload);
      expect(store.state.loginState.loading, false);
      expect(store.state.loginState.loggedIn, true);
      expect(store.state.loginState.errorMsg, isNull);
      expect(await session.loggedIn, true);
      expect(failures, 1);
      expect(adapter.loginRequests, 2);
    });
  }

  for (final mode in ['rejected', 'invalid JSON', 'offline', 'timeout']) {
    test('credential failure dispatches failure and ends loading: $mode',
        () async {
      final adapter = LoginAdapter()
        ..rejected = mode == 'rejected'
        ..malformedCredentials = mode == 'invalid JSON'
        ..credentialFailure = mode == 'offline'
            ? DioException(
                requestOptions: RequestOptions(path: 'login'),
                type: DioExceptionType.connectionError)
            : mode == 'timeout'
                ? TimeoutException('login timeout')
                : null;
      adapter.configGate.complete();
      final session = TestLoginWrapper()..safeMode = false;
      session.dio.httpClientAdapter = adapter;
      middleware.wrapper = session;
      final store = createStore(withMiddleware: true);
      var failures = 0;
      final subscription = store
          .actionStream(LoginActionsNames.loginFailed)
          .listen((_) => failures++);
      addTearDown(subscription.cancel);
      await store.actions.loginActions.login(LoginPayload((b) => b
        ..user = 'user'
        ..pass = 'password'
        ..url = testServerUrl
        ..fromStorage = false));
      expect(store.state.loginState.loading, false);
      expect(store.state.loginState.loggedIn, false);
      expect(store.state.loginState.errorMsg, isNotEmpty);
      expect(failures, 1);
      expect(await session.loggedIn, false);
    });
  }

  test('stored credentials retain offline access after config network failure',
      () async {
    final adapter = LoginAdapter()
      ..configFailure = DioException(
          requestOptions: RequestOptions(path: 'config'),
          type: DioExceptionType.receiveTimeout);
    adapter.configGate.complete();
    final session = TestLoginWrapper()..safeMode = false;
    session.dio.httpClientAdapter = adapter;
    middleware.wrapper = session;
    final store = createStore(withMiddleware: true);
    await store.actions.loginActions.login(LoginPayload((b) => b
      ..user = 'user'
      ..pass = 'password'
      ..url = testServerUrl
      ..fromStorage = true));
    expect(store.state.loginState.loading, false);
    expect(store.state.loginState.loggedIn, true);
    expect(store.state.noInternet, true);
    expect(await session.loggedIn, false);
    expect(session.sessionRefreshScheduled, false);
  });

  for (final mode in [
    'success',
    'credentials rejected',
    'malformed credentials',
    'callback failure'
  ]) {
    test('wrapper session outcome: $mode', () async {
      final adapter = LoginAdapter()
        ..rejected = mode == 'credentials rejected'
        ..malformedCredentials = mode == 'malformed credentials';
      adapter.configGate.complete();
      final session = TestLoginWrapper()..dio.httpClientAdapter = adapter;
      addTearDown(() => session.logout(hard: true));
      var configs = 0;
      await session.login('user', 'pass', null, testServerUrl,
          logout: () {},
          relogin: () {},
          addProtocolItem: (_) {}, configLoaded: () async {
        configs++;
        if (mode == 'callback failure')
          throw StateError('session initialization');
      });
      expect(await session.loggedIn, mode == 'success');
      expect(session.sessionRefreshScheduled, mode == 'success');
      expect(configs, mode == 'success' || mode == 'callback failure' ? 1 : 0);
    });
  }
}
