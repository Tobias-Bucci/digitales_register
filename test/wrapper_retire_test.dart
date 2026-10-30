// Copyright (C) 2026 Tobias Bucci
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

/// A school server that counts what a session does after the app has left it.
class _School {
  _School._(this.server);

  static Future<_School> start() async {
    final school = _School._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    school.server.listen(school._handle);
    return school;
  }

  final HttpServer server;
  final List<String> requests = <String>[];
  final List<String?> logoutCookies = <String?>[];

  /// Holds the login response until completed.
  Completer<void>? holdLogin;

  String get url => 'http://127.0.0.1:${server.port}';

  int count(String path) => requests.where((r) => r == path).length;

  Future<void> _handle(HttpRequest request) async {
    requests.add(request.uri.path);
    final response = request.response;
    if (request.uri.path == '/v2/api/auth/login') {
      await request.drain<void>();
      await holdLogin?.future;
      response.headers.contentType = ContentType.json;
      response.headers.add(HttpHeaders.setCookieHeader, 'sid=secret; Path=/');
      response.write(json.encode({'loggedIn': true}));
    } else if (request.uri.path == '/v2/' && request.method == 'GET') {
      response.headers.contentType = ContentType.html;
      response.write(_configPageSource);
    } else if (request.uri.path == '/v2/logout') {
      logoutCookies.add(request.headers.value(HttpHeaders.cookieHeader));
    } else if (request.uri.path == '/v2/api/message/getMyMessages') {
      response.headers.contentType = ContentType.json;
      response.write('[]');
    } else if (request.uri.path == '/v2/api/slow') {
      // Never answers on its own.
      await Future<void>.delayed(const Duration(seconds: 30));
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  Future<Wrapper> signIn({bool keepLoginHeld = false}) async {
    final wrapper = Wrapper(allowInsecureConnections: true);
    await wrapper.login('user', 'pass', null, url,
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {});
    return wrapper;
  }
}

void main() {
  late _School school;

  setUp(() async {
    await bootstrapTestEnvironment();
    // The widget test binding answers every HttpClient request with a 400.
    HttpOverrides.global = null;
    school = await _School.start();
    addTearDown(() => school.server.close(force: true));
  });

  tearDown(() {
    // The background switch is app-wide; never leak it into other tests.
    Wrapper().resumeNetworkActivity();
    resetTestState();
  });

  test('backgrounding the app stops every Wrapper instance, not just the newest',
      () {
    final old = Wrapper();
    final current = Wrapper();

    current.pauseNetworkActivity();

    expect(current.isAppInForeground, isFalse);
    expect(old.isAppInForeground, isFalse);
  });

  test('retiring a session ends its timer, credentials and requests',
      () async {
    final session = await school.signIn();
    expect(session.sessionRefreshScheduled, isTrue);
    final slow = session.send('api/slow');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    session.retire();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // The running request is cancelled instead of waiting for its timeout.
    expect(await slow.timeout(const Duration(seconds: 3)), isNull);
    expect(session.isRetired, isTrue);
    expect(session.sessionRefreshScheduled, isFalse);
    expect(session.user, isNull);
    expect(session.pass, isNull);
    expect(session.url, isNull);
    final before = school.requests.length;
    expect(await session.send('api/message/getMyMessages'), isNull);
    expect(await session.ensureLoggedIn(), isFalse);
    expect(school.requests.length, before);
  });

  test('retiring still ends the server session with its cookie', () async {
    final session = await school.signIn();

    session.retire();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(school.logoutCookies, hasLength(1));
    expect(school.logoutCookies.single, contains('sid=secret'));
  });

  test('retire is idempotent', () async {
    final session = await school.signIn();

    session.retire();
    session.retire();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(school.logoutCookies, hasLength(1));
  });

  test('a login finishing after retirement stays signed out and quiet',
      () async {
    school.holdLogin = Completer<void>();
    var configLoaded = 0;
    final session = Wrapper(allowInsecureConnections: true);
    final login = session.login('user', 'pass', null, school.url,
        logout: () {},
        configLoaded: () async {
          configLoaded++;
        },
        relogin: () {},
        addProtocolItem: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));

    session.retire();
    school.holdLogin!.complete();
    await login;

    expect(await session.loggedIn, isFalse);
    expect(session.user, isNull);
    expect(session.pass, isNull);
    expect(session.sessionRefreshScheduled, isFalse);
    expect(configLoaded, 0);
    expect(school.count('/v2/'), 0);
  });

  test('retiring a session while backgrounded sends no logout', () async {
    final session = await school.signIn();
    session.pauseNetworkActivity();

    session.retire();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(school.logoutCookies, isEmpty);
  });

  test('switching accounts retires the previous session', () async {
    final previous = await school.signIn();
    wrapper = previous;
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'user'
        ..url = school.url),
    );
    addTearDown(store.dispose);
    expect(previous.sessionRefreshScheduled, isTrue);

    await store.actions.loginActions.addAccount();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(wrapper, isNot(same(previous)));
    expect(previous.isRetired, isTrue);
    expect(previous.sessionRefreshScheduled, isFalse);
    expect(previous.user, isNull);
    // Only the current session may be paused: and then nothing else works.
    pauseNetworkRequests();
    expect(wrapper.isAppInForeground, isFalse);
    expect(previous.isAppInForeground, isFalse);
  });

  test('a hard logout retires the signed-out session', () async {
    final previous = await school.signIn();
    wrapper = previous;
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'user'
        ..url = school.url),
    );
    addTearDown(store.dispose);

    await store.actions.loginActions.logout(
      LogoutPayload((b) => b
        ..hard = true
        ..forced = false),
    );

    expect(wrapper, isNot(same(previous)));
    expect(previous.isRetired, isTrue);
    expect(previous.sessionRefreshScheduled, isFalse);
  });
}

const String _configPageSource = '''
<!DOCTYPE html>
<html>
<head>
  <script>
    var currentUserId=3539;
    var config = {
      auto_logout_seconds: 300,
    };
  </script>
</head>
<body>
  <img id="navigationProfilePicture" src="https://school.example/v2/theme/icons/profile_empty.png">
  Test User
</body>
</html>
''';
