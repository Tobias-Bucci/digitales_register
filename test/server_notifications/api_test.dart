import 'dart:async';

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

Matcher failure(ServerNotificationFailureKind kind, {int? status}) =>
    throwsA(isA<ServerNotificationFailure>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.status, 'status', status ?? anything));

void main() {
  late FakeServer server;

  setUp(() => server = FakeServer());

  group('request', () {
    test('sends exactly the contract parameters and nothing identifying',
        () async {
      server.replyList([]);
      await server.api.fetch(selection);
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.origin, 'https://api.digitalesregister.com');
      expect(request.url.path, '/api/v1/notifications');
      expect(request.url.queryParameters, {
        'platform': 'android',
        'app_version': '1.17.4',
        'lang': 'de',
        'limit': '100',
      });
      expect(
          request.headers.keys.map((k) => k.toLowerCase()).toSet(), {'accept'});
    });

    test('a path in the base URL is kept', () async {
      server.replyList([]);
      await ServerNotificationApi(
        baseUri: Uri.parse('https://example.com/register/'),
        client: server.client,
      ).fetch(selection);
      expect(server.requests.single.url.path, '/register/api/v1/notifications');
    });

    test('redirects are not followed', () async {
      server.reply(
          http.Response('', 302, headers: {'location': 'http://example.com/'}));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.permanent, status: 302));
      expect(server.requests.single.followRedirects, isFalse);
    });
  });

  group('ETag and 304', () {
    test('sends the validator and reports 304 as unchanged', () async {
      server.replyNotModified();
      final result = await server.api.fetch(selection, etag: 'W/"abc"');
      expect(result, isA<ServerNotificationsNotModified>());
      expect(server.requests.single.headers['If-None-Match'], 'W/"abc"');
    });

    test('returns the first page validator unchanged', () async {
      server.reply(jsonResponse(fixture('list-typical'), etag: 'W/"xyz"'));
      final result =
          await server.api.fetch(selection) as ServerNotificationsFetched;
      expect(result.etag, 'W/"xyz"');
      expect(result.pollAfterSeconds, 300);
    });

    test('a 304 nobody asked for is a failure, not an empty list', () async {
      server.replyNotModified();
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.transient, status: 304));
    });
  });

  group('cursor pagination', () {
    test('follows next_cursor to the end and returns the whole set', () async {
      final first = fixture('list-page-1');
      server
        ..reply(jsonResponse(first, etag: 'W/"page1"'))
        // The real server hashes the cursor into the ETag of later pages.
        ..reply(jsonResponse(fixture('list-page-2'), etag: 'W/"page2"'));
      final result = await server.api.fetch(selection, etag: 'W/"old"')
          as ServerNotificationsFetched;
      expect(result.notifications, hasLength(3));
      expect(result.etag, 'W/"page1"', reason: 'only page 1 is revalidated');
      expect(server.requests, hasLength(2));
      expect(server.requests[0].headers['If-None-Match'], 'W/"old"');
      expect(server.requests[1].headers.containsKey('If-None-Match'), isFalse);
      expect(server.requests[0].url.queryParameters.containsKey('cursor'),
          isFalse);
      expect(server.requests[1].url.queryParameters['cursor'],
          first['next_cursor']);
    });

    test('sorts newest first and removes duplicates across pages', () async {
      final older = item(
          id: '2c9a7e44-1d6b-4c3f-8a55-73e1b9d0c2f4',
          publishedAt: '2026-01-01T00:00:00Z');
      server
        ..reply(jsonResponse(page([older], nextCursor: 'next'), etag: 'W/"1"'))
        ..reply(jsonResponse(page([older, item()])));
      final result =
          await server.api.fetch(selection) as ServerNotificationsFetched;
      expect(result.notifications.map((n) => n.id), [
        '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731',
        '2c9a7e44-1d6b-4c3f-8a55-73e1b9d0c2f4',
      ]);
    });

    test('a failed later page fails the whole walk', () async {
      server
        ..reply(jsonResponse(page([item()], nextCursor: 'next')))
        ..reply(http.Response('', 500));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.transient, status: 500));
    });

    test('a cursor that repeats cannot loop forever', () async {
      server
        ..reply(jsonResponse(page([item()], nextCursor: 'same')))
        ..reply(jsonResponse(page([item()], nextCursor: 'same')));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.transient));
      expect(server.requests, hasLength(2));
    });

    test('too many pages fail instead of hiding the rest', () async {
      final endless = ServerNotificationApi(
        baseUri: baseUri,
        maxPages: 3,
        client: MockClient((request) async {
          final count = request.url.queryParameters['cursor'] ?? '0';
          return jsonResponse(page([item()], nextCursor: '$count+'));
        }),
      );
      await expectLater(endless.fetch(selection),
          failure(ServerNotificationFailureKind.transient));
    });

    test('a refused cursor restarts once, without validator', () async {
      server
        ..reply(jsonResponse(page([item()], nextCursor: 'stale')))
        ..reply(jsonResponse(fixture('error-invalid-cursor'), status: 400))
        ..reply(jsonResponse(page([item()]), etag: 'W/"2"'));
      final result = await server.api.fetch(selection, etag: 'W/"1"')
          as ServerNotificationsFetched;
      expect(result.notifications, hasLength(1));
      expect(
          server.requests.last.headers.containsKey('If-None-Match'), isFalse);
    });
  });

  group('failures', () {
    test('429 carries Retry-After', () async {
      server.reply(jsonResponse(fixture('error-rate-limited'),
          status: 429, headers: {'retry-after': '120'}));
      await expectLater(
        server.api.fetch(selection),
        throwsA(isA<ServerNotificationFailure>()
            .having((e) => e.kind, 'kind',
                ServerNotificationFailureKind.rateLimited)
            .having((e) => e.retryAfter, 'wait', const Duration(seconds: 120))),
      );
    });

    test('Retry-After that is not a number counts as absent', () {
      expect(parseRetryAfter('Wed, 21 Oct 2026 07:28:00 GMT'), isNull);
      expect(parseRetryAfter('-1'), isNull);
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter(' 5 '), const Duration(seconds: 5));
    });

    test('500 and 503 are transient, and 503 may carry Retry-After', () async {
      server
        ..reply(jsonResponse(fixture('error-internal'), status: 500))
        ..reply(http.Response('', 503, headers: {'retry-after': '30'}));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.transient, status: 500));
      await expectLater(
        server.api.fetch(selection),
        throwsA(isA<ServerNotificationFailure>()
            .having((e) => e.retryAfter, 'wait', const Duration(seconds: 30))),
      );
    });

    test('400 will not get better by retrying', () async {
      server
          .reply(jsonResponse(fixture('error-invalid-parameter'), status: 400));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.permanent, status: 400));
    });

    test('malformed bodies are transient failures', () async {
      for (final body in ['<html>', '{"schema_version":1}', '[]']) {
        server.reply(http.Response(body, 200));
        await expectLater(server.api.fetch(selection),
            failure(ServerNotificationFailureKind.transient));
      }
    });

    test('an unknown schema is permanent', () async {
      server.reply(jsonResponse(page([])..['schema_version'] = 2));
      await expectLater(server.api.fetch(selection),
          failure(ServerNotificationFailureKind.permanent));
    });

    test('offline is a transient failure', () async {
      final api = ServerNotificationApi(
        baseUri: baseUri,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(api.fetch(selection),
          failure(ServerNotificationFailureKind.transient));
    });

    test('a request that never ends times out', () async {
      final api = ServerNotificationApi(
        baseUri: baseUri,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(api.fetch(selection),
          failure(ServerNotificationFailureKind.transient));
    });

    test('an oversized body is refused', () async {
      final api = ServerNotificationApi(
        baseUri: baseUri,
        maxBodyBytes: 16,
        client: server.client,
      );
      server.reply(jsonResponse(page([item()])));
      await expectLater(api.fetch(selection),
          failure(ServerNotificationFailureKind.transient));
    });
  });
}
