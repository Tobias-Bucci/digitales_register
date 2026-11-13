// End-to-end check of the client against a running notification server.
//
// Skipped unless DR_NOTIFICATIONS_E2E_URL names the server's origin:
//
//   DR_NOTIFICATIONS_E2E_URL=https://api.digitalesregister.com \
//     flutter test test/server_notifications/live_contract_test.dart
//
// It only sends GET requests to the public API (a few dozen at most), so it is
// safe against production. A local server may use http://127.0.0.1:<port>;
// the app itself accepts only HTTPS, see parseServerNotificationBaseUrl.
import 'dart:convert';
import 'dart:io';

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final String? _configured = Platform.environment['DR_NOTIFICATIONS_E2E_URL'];

const _platforms = ['web', 'android', 'ios', 'windows', 'linux'];
const _version = '2.0.0';

final _weakEtag = RegExp(r'^W/"[^"]+"$');

Uri _list(
  Uri base, {
  required String platform,
  String lang = 'de',
  String? cursor,
  int? limit,
}) =>
    base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/api/v1/notifications',
      queryParameters: {
        'platform': platform,
        'app_version': _version,
        'lang': lang,
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
      },
    );

/// Every page of one selection, read without the client, so that the raw
/// responses can be checked against the contract.
Future<List<ServerNotificationPage>> _walk(
  http.Client client,
  Uri base, {
  required String platform,
  String lang = 'de',
  int? limit,
}) async {
  final pages = <ServerNotificationPage>[];
  String? cursor;
  do {
    final response = await client.get(
      _list(base, platform: platform, lang: lang, cursor: cursor, limit: limit),
      headers: {'Accept': 'application/json'},
    );
    expect(response.statusCode, 200, reason: response.body);
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(response.headers['cache-control'], 'no-cache');
    expect(response.headers['etag'], matches(_weakEtag));
    final page = ServerNotificationPage.parse(
        jsonDecode(utf8.decode(response.bodyBytes)));
    expect(page.rejectedCount, 0, reason: 'every entry must be valid');
    pages.add(page);
    cursor = page.nextCursor;
    expect(pages.length, lessThan(1000), reason: 'the walk must end');
  } while (cursor != null);
  return pages;
}

List<String> _ids(Iterable<ServerNotificationPage> pages) => [
      for (final page in pages)
        for (final item in page.notifications) item.id,
    ];

void main() {
  final configured = _configured;
  final skip = configured == null || configured.trim().isEmpty
      ? 'set DR_NOTIFICATIONS_E2E_URL to run against a server'
      : null;
  final base = Uri.parse(skip == null ? configured!.trim() : 'https://x.test');
  late http.Client client;

  setUp(() => client = http.Client());
  tearDown(() => client.close());

  ServerNotificationApi api() =>
      ServerNotificationApi(baseUri: base, client: client);

  ServerNotificationSelection selection(String platform,
          {String lang = 'de'}) =>
      ServerNotificationSelection(
          platform: platform, appVersion: _version, language: lang);

  group('live server', () {
    for (final platform in _platforms) {
      test('$platform: every page matches the contract, and the client agrees',
          () async {
        final pages = await _walk(client, base, platform: platform);
        final raw = _ids(pages);
        expect(raw.toSet(), hasLength(raw.length), reason: 'no duplicates');
        expect(pages.first.pollAfterSeconds, greaterThan(0));

        final fetched = await api().fetch(selection(platform));
        expect(fetched, isA<ServerNotificationsFetched>());
        fetched as ServerNotificationsFetched;
        expect(fetched.notifications.map((item) => item.id), raw,
            reason: 'newest first, as the server orders them');
        expect(fetched.etag, matches(_weakEtag));
      });
    }

    test('the validator of the first page gives 304 through the client',
        () async {
      final first = await api().fetch(selection('android'));
      expect(first, isA<ServerNotificationsFetched>());
      final etag = (first as ServerNotificationsFetched).etag;
      final second = await api().fetch(selection('android'), etag: etag);
      expect(second, isA<ServerNotificationsNotModified>());
    });

    test('pages of one item walk to the same set as pages of a hundred',
        () async {
      final big = _ids(await _walk(client, base, platform: 'android'));
      final small =
          _ids(await _walk(client, base, platform: 'android', limit: 1));
      expect(small, big);
    });

    test('every link and icon is one the client knows', () async {
      for (final platform in _platforms) {
        final response = await client.get(_list(base, platform: platform));
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
        for (final entry in body['notifications'] as List) {
          final json = entry as Map;
          final icon = (json['type'] as Map)['icon'];
          expect(serverNotificationIcons.keys, contains(icon));
          final link = json['link'];
          if (link == null) continue;
          expect(ServerNotificationLink.tryParse(link), isNotNull,
              reason: 'link $link of ${json['id']}');
        }
      }
    });

    test('every app language gets complete texts', () async {
      for (final lang in ['de', 'it', 'en']) {
        final pages =
            await _walk(client, base, platform: 'android', lang: lang);
        for (final item in pages.expand((page) => page.notifications)) {
          expect(item.title, isNotEmpty);
          expect(item.body, isNotEmpty);
        }
      }
    });

    test('a platform the API does not know is refused, not answered', () async {
      final response = await client.get(_list(base, platform: 'symbian'));
      expect(response.statusCode, 400);
      final error = (jsonDecode(response.body) as Map)['error'] as Map;
      expect(error['code'], 'invalid_parameter');
      expect(error['field'], 'platform');
      await expectLater(
        api().fetch(selection('symbian')),
        throwsA(isA<ServerNotificationFailure>().having(
            (failure) => failure.kind,
            'kind',
            ServerNotificationFailureKind.permanent)),
      );
    });
  }, skip: skip);
}
