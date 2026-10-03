import 'dart:convert';
import 'dart:io';

import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'login fails gracefully when the config request returns a full login page',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        if (request.uri.path == '/v2/api/auth/login' &&
            request.method == 'POST') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(json.encode({'loggedIn': true}));
        } else if (request.uri.path == '/v2/' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('''
<!DOCTYPE html>
<html lang="de"><head><title>Login</title></head>
<body><form action="/v2/login"></form></body></html>
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final wrapper = Wrapper(allowInsecureConnections: true);
      final result = await wrapper.login(
        'user',
        'pass',
        null,
        'http://127.0.0.1:${server.port}',
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {},
      );

      expect(result, isNull);
      expect(await wrapper.loggedIn, isFalse);
      expect(wrapper.error,
          contains('Die Sitzung wurde direkt nach dem Login beendet.'));
    },
  );

  test(
    'login fails gracefully when the config page redirects back to login',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        if (request.uri.path == '/v2/api/auth/login' &&
            request.method == 'POST') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            json.encode(<String, Object?>{'loggedIn': true}),
          );
        } else if (request.uri.path == '/v2/' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.html;
          request.response.write('''
<script type="text/javascript">
window.location = "https://vinzentinum.digitalesregister.it/v2/login";
</script>
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final wrapper = Wrapper(allowInsecureConnections: true);
      final result = await wrapper.login(
        'user',
        'pass',
        null,
        'http://127.0.0.1:${server.port}',
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {},
      );

      expect(result, isNull);
      expect(await wrapper.loggedIn, isFalse);
      expect(
        wrapper.error,
        contains('Die Sitzung wurde direkt nach dem Login beendet.'),
      );
    },
  );

  test(
    'send refreshes the session when the server redirects to login',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var loginRequests = 0;
      var messageRequests = 0;

      server.listen((request) async {
        if (request.uri.path == '/v2/api/auth/login' &&
            request.method == 'POST') {
          loginRequests++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            json.encode(<String, Object?>{'loggedIn': true}),
          );
        } else if (request.uri.path == '/v2/' && request.method == 'GET') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(_configPageSource);
        } else if (request.uri.path == '/v2/api/message/getMyMessages' &&
            request.method == 'POST') {
          messageRequests++;
          if (messageRequests <= 2) {
            request.response.headers.contentType = ContentType.html;
            request.response.write(_redirectSource);
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(json.encode(<Object>[]));
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final wrapper = Wrapper(allowInsecureConnections: true);
      await wrapper.login(
        'user',
        'pass',
        null,
        'http://127.0.0.1:${server.port}',
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {},
      );

      final result = await wrapper.send('api/message/getMyMessages');

      expect(result, isA<List<dynamic>>());
      expect(result as List<dynamic>, isEmpty);
      expect(loginRequests, 3);
      expect(messageRequests, 3);
    },
  );

  test('requests stop while the app is in the background', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var messageRequests = 0;
    server.listen((request) async {
      if (request.uri.path == '/v2/api/auth/login') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'loggedIn': true}));
      } else if (request.uri.path == '/v2/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_configPageSource);
      } else if (request.uri.path == '/v2/api/message/getMyMessages') {
        messageRequests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode(<Object>[]));
      }
      await request.response.close();
    });
    final wrapper = Wrapper(allowInsecureConnections: true);
    await wrapper.login(
      'user',
      'pass',
      null,
      'http://127.0.0.1:${server.port}',
      logout: () {},
      configLoaded: () {},
      relogin: () {},
      addProtocolItem: (_) {},
    );

    wrapper.pauseNetworkActivity();
    expect(await wrapper.send('api/message/getMyMessages'), isNull);
    expect(messageRequests, 0);
    expect(Wrapper().isAppInForeground, isFalse);
    wrapper.resumeNetworkActivity();
    expect(await wrapper.send('api/message/getMyMessages'), isEmpty);
    expect(messageRequests, 1);
  });

  test('archive uses the configured school URL and accepts empty HTTP success',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final payloads = <Map<String, dynamic>>[];
    server.listen((request) async {
      if (request.uri.path == '/v2/api/auth/login') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(json.encode({'loggedIn': true}));
      } else if (request.uri.path == '/v2/' && request.method == 'GET') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_configPageSource);
      } else if (request.uri.path == '/v2/api/message/archiveMessage' &&
          request.method == 'POST') {
        final payload = json.decode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        payloads.add(payload);
        if (payload['archiveType'] == 1) {
          request.response.headers.contentType = ContentType.json;
          request.response.write('null');
        } else {
          request.response.statusCode = HttpStatus.noContent;
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final wrapper = Wrapper(allowInsecureConnections: true);
    addTearDown(() {
      wrapper.pauseNetworkActivity();
      Wrapper().resumeNetworkActivity();
    });
    await wrapper.login('user', 'pass', null, 'http://127.0.0.1:${server.port}',
        logout: () {},
        configLoaded: () {},
        relogin: () {},
        addProtocolItem: (_) {});
    for (final archiveType in [1, 2]) {
      final response = await wrapper.send('api/message/archiveMessage',
          args: {'messageId': 1, 'archiveType': archiveType},
          acceptEmptyResponse: true);
      expect(response, isNotNull);
    }
    expect(payloads, [
      {'messageId': 1, 'archiveType': 1},
      {'messageId': 1, 'archiveType': 2},
    ]);
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
  <img id="navigationProfilePicture" src="https://vinzentinum.digitalesregister.it/v2/theme/icons/profile_empty.png">
  Tobias Bucci
</body>
</html>
''';

const String _redirectSource = '''
<script type="text/javascript">
window.location = "https://vinzentinum.digitalesregister.it/v2/login";
</script>
''';
