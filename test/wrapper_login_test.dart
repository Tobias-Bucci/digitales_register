// Copyright (C) 2026 Tobias Bucci

import 'dart:convert';
import 'dart:io';

import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

      final wrapper = Wrapper();
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
}
