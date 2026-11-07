import 'dart:convert';
import 'dart:io';

import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const selection = ServerNotificationSelection(
  platform: 'android',
  appVersion: '1.17.4',
  language: 'de',
);

final baseUri = Uri.parse('https://api.digitalesregister.com');

/// The public contract's fixtures are the test data.
String fixtureText(String name) =>
    File('contract/fixtures/$name.json').readAsStringSync();

Map<String, dynamic> fixture(String name) =>
    jsonDecode(fixtureText(name)) as Map<String, dynamic>;

String contractText() =>
    File('contract/public.openapi.yaml').readAsStringSync();

/// One notification as the server sends it.
Map<String, dynamic> item({
  String id = '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731',
  int revision = 1,
  int attention = 1,
  String title = 'Titel',
  String body = 'Text',
  bool critical = false,
  String icon = 'info',
  String color = '#2F6FB5',
  String publishedAt = '2026-10-22T19:00:00Z',
  String? expiresAt,
  Map<String, dynamic>? link,
}) =>
    {
      'id': id,
      'revision': revision,
      'attention_revision': attention,
      'title': title,
      'body': body,
      'type': {
        'key': 'info',
        'label': 'Information',
        'color': color,
        'icon': icon,
        'critical': critical,
      },
      'published_at': publishedAt,
      'expires_at': expiresAt,
      'link': link,
    };

ServerNotification parsed(Map<String, dynamic> json) =>
    ServerNotification.tryParse(json)!;

Map<String, dynamic> page(
  List<Map<String, dynamic>> items, {
  String? nextCursor,
  int pollAfter = 300,
  String serverTime = '2026-10-22T20:00:00Z',
}) =>
    {
      'schema_version': 1,
      'server_time': serverTime,
      'poll_after_seconds': pollAfter,
      'next_cursor': nextCursor,
      'notifications': items,
    };

http.Response jsonResponse(
  Object? body, {
  int status = 200,
  String? etag,
  Map<String, String> headers = const {},
}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        'content-type': 'application/json',
        if (etag != null) 'etag': etag,
        ...headers,
      },
    );

/// In-memory storage that can be made to fail.
class FakeStorage implements ServerNotificationStorage {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('quota exceeded');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (failWrites) throw StateError('quota exceeded');
    values.remove(key);
  }
}

/// A server that answers from a queue and records what it was asked.
class FakeServer {
  final List<http.BaseRequest> requests = [];
  final List<http.Response Function(http.Request)> responses = [];

  void reply(http.Response response) => responses.add((_) => response);

  void replyList(List<Map<String, dynamic>> items, {String? etag}) =>
      reply(jsonResponse(page(items), etag: etag ?? 'W/"1"'));

  void replyNotModified() =>
      reply(http.Response('', 304, headers: {'etag': 'W/"1"'}));

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (responses.isEmpty) throw StateError('no reply queued');
    return responses.removeAt(0)(request);
  });

  ServerNotificationApi get api =>
      ServerNotificationApi(baseUri: baseUri, client: client);
}

ServerNotificationRepository repositoryFor(
  FakeServer server,
  FakeStorage storage, {
  DateTime Function()? now,
  bool Function()? mayStoreCaches,
}) =>
    ServerNotificationRepository(
      api: server.api,
      storage: storage,
      now: now ?? (() => DateTime.utc(2026, 10, 22, 20)),
      mayStoreCaches: mayStoreCaches ?? (() => true),
    );
