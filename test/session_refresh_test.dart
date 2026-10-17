import 'dart:io';

import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'parse_webpage_test.dart' show source;

void main() {
  final now = DateTime.utc(2026, 3, 28);
  test('expiration accepts integral JSON numbers', () {
    final seconds =
        now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;
    expect(parseSessionExpiration(seconds, now).millisecondsSinceEpoch,
        seconds * 1000);
    expect(
        parseSessionExpiration(seconds.toDouble(), now).millisecondsSinceEpoch,
        seconds * 1000);
  });
  for (final value in <Object?>[
    null,
    '1234567890',
    -1,
    1,
    1234567890.5,
    double.nan,
    double.infinity,
    999999999999999999
  ]) {
    test('rejects invalid/old expiration $value', () {
      expect(() => parseSessionExpiration(value, now), throwsFormatException);
    });
  }
  for (final response in <String>[
    '{}',
    '{"newExpiration":null}',
    '{"newExpiration":"1234567890"}',
    '{"newExpiration":-1}',
    '{"newExpiration":1}',
    '{"forceLogout":true}',
    'http-error',
    'throwing-callback',
    'valid-int',
    'valid-double',
  ]) {
    test('refresh response $response terminates or schedules the session',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/auth/login')) {
          request.response.write('{"loggedIn":true}');
        } else if (request.uri.path == '/v2/') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(source);
        } else if (response == 'http-error') {
          request.response.statusCode = 500;
        } else if (response.startsWith('valid')) {
          final expiration =
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300;
          request.response.write(
              '{"newExpiration":$expiration${response == 'valid-double' ? '.0' : ''}}');
        } else {
          request.response.write(response);
        }
        await request.response.close();
      });
      final wrapper = Wrapper(allowInsecureConnections: true);
      wrapper.safeMode = true;
      wrapper.resumeNetworkActivity();
      var logouts = 0;
      await wrapper
          .login('user', 'password', null, 'http://127.0.0.1:${server.port}',
              logout: () {
        logouts++;
        if (response == 'throwing-callback')
          throw StateError('logout callback');
      }, configLoaded: () {}, relogin: () {}, addProtocolItem: (_) {});
      expect(await wrapper.loggedIn, true);
      expect(wrapper.sessionRefreshScheduled, true);
      await wrapper.refreshSessionNow();
      final valid = response.startsWith('valid');
      expect(wrapper.sessionRefreshScheduled, valid);
      expect(await wrapper.loggedIn, valid);
      expect(logouts, valid ? 0 : 1);
      wrapper.pauseNetworkActivity();
      wrapper.resumeNetworkActivity();
      wrapper.logout(hard: true, logoutForcedByServer: true);
    });
  }
}
