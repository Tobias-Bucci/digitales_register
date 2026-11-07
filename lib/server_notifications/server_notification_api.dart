import 'dart:async';
import 'dart:convert';

import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// How a fetch failed, which decides when the next one may happen.
enum ServerNotificationFailureKind {
  /// Offline, timeout, `5xx` or a malformed body: retry with backoff.
  transient,

  /// `429`: wait for `Retry-After`.
  rateLimited,

  /// `4xx` or an unknown schema: the same request will fail again.
  permanent,
}

class ServerNotificationFailure implements Exception {
  const ServerNotificationFailure(this.kind, {this.retryAfter, this.status});

  final ServerNotificationFailureKind kind;
  final Duration? retryAfter;
  final int? status;

  @override
  String toString() => 'ServerNotificationFailure($kind, status: $status)';
}

@immutable
sealed class ServerNotificationFetchResult {
  const ServerNotificationFetchResult();
}

/// `304`: no page has changed.
class ServerNotificationsNotModified extends ServerNotificationFetchResult {
  const ServerNotificationsNotModified();
}

/// The complete applicable set, across all pages.
class ServerNotificationsFetched extends ServerNotificationFetchResult {
  const ServerNotificationsFetched({
    required this.notifications,
    required this.etag,
    required this.pollAfterSeconds,
    required this.serverTime,
  });

  final List<ServerNotification> notifications;
  final String? etag;
  final int pollAfterSeconds;
  final DateTime serverTime;
}

class _StaleCursor implements Exception {
  const _StaleCursor();
}

/// Reads the anonymous notifications endpoint.
///
/// Sends only the query parameters of the contract and the conditional header.
/// There are no cookies, no credentials and no identifiers, and this client
/// is separate from the one that talks to the school register.
class ServerNotificationApi {
  ServerNotificationApi({
    required this.baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxPages = 50,
    this.maxBodyBytes = 4 * 1024 * 1024,
  }) : _client = client;

  final Uri baseUri;
  final Duration timeout;

  /// Far above any real set. A server that never ends is a failure, because
  /// stopping quietly would hide the rest of the list.
  final int maxPages;
  final int maxBodyBytes;
  http.Client? _client;

  http.Client get _http => _client ??= http.Client();

  static const _pageSize = 100;

  Uri _uri(ServerNotificationSelection selection, String? cursor) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(
      path: '$basePath/api/v1/notifications',
      queryParameters: {
        'platform': selection.platform,
        'app_version': selection.appVersion,
        'lang': selection.language,
        if (cursor != null) 'cursor': cursor,
        'limit': '$_pageSize',
      },
    );
  }

  /// Fetches every page. [etag] applies to the first request only: it covers
  /// the whole collection, so `304` there means no page changed.
  ///
  /// Throws [ServerNotificationFailure]. Nothing is returned for a partial
  /// walk, so the caller can never mistake half a list for the full one.
  Future<ServerNotificationFetchResult> fetch(
    ServerNotificationSelection selection, {
    String? etag,
  }) async {
    try {
      return await _walk(selection, etag);
    } on _StaleCursor {
      // Walk once more from the start. The validator is of no use by now.
      try {
        return await _walk(selection, null);
      } on _StaleCursor {
        throw const ServerNotificationFailure(
            ServerNotificationFailureKind.transient);
      }
    }
  }

  Future<ServerNotificationFetchResult> _walk(
    ServerNotificationSelection selection,
    String? etag,
  ) async {
    final byId = <String, ServerNotification>{};
    final seenCursors = <String>{};
    String? cursor;
    String? firstEtag;
    ServerNotificationPage? first;
    for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
      final response =
          await _get(_uri(selection, cursor), pageIndex == 0 ? etag : null);
      if (response.statusCode == 304) {
        if (pageIndex == 0 && etag != null) {
          return const ServerNotificationsNotModified();
        }
        throw const ServerNotificationFailure(
            ServerNotificationFailureKind.transient,
            status: 304);
      }
      if (response.statusCode != 200) {
        _throwFor(response, walkingCursor: cursor != null);
      }
      final page = _parse(response);
      // Only the first page's validator is kept. Later pages have their own,
      // because the server hashes the cursor in, so they cannot be compared.
      if (pageIndex == 0) {
        firstEtag = response.headers['etag'];
        first = page;
      }
      for (final notification in page.notifications) {
        byId.putIfAbsent(notification.id, () => notification);
      }
      cursor = page.nextCursor;
      if (cursor == null) {
        return ServerNotificationsFetched(
          notifications: byId.values.toList()
            ..sort(ServerNotification.compareNewestFirst),
          etag: firstEtag,
          pollAfterSeconds: first!.pollAfterSeconds,
          serverTime: first.serverTime,
        );
      }
      if (!seenCursors.add(cursor)) {
        throw const ServerNotificationFailure(
            ServerNotificationFailureKind.transient);
      }
    }
    throw const ServerNotificationFailure(
        ServerNotificationFailureKind.transient);
  }

  Future<http.Response> _get(Uri uri, String? etag) async {
    final request = http.Request('GET', uri)
      // An HTTPS request must not end up somewhere else.
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (etag != null) request.headers['If-None-Match'] = etag;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      final length = streamed.contentLength;
      if (length != null && length > maxBodyBytes) {
        throw const ServerNotificationFailure(
            ServerNotificationFailureKind.transient);
      }
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on ServerNotificationFailure {
      rethrow;
    } on Exception {
      // Timeout, no network, TLS failure: the same to the caller.
      throw const ServerNotificationFailure(
          ServerNotificationFailureKind.transient);
    }
  }

  ServerNotificationPage _parse(http.Response response) {
    if (response.bodyBytes.length > maxBodyBytes) {
      throw const ServerNotificationFailure(
          ServerNotificationFailureKind.transient);
    }
    try {
      return ServerNotificationPage.parse(
          jsonDecode(utf8.decode(response.bodyBytes)));
    } on ServerNotificationSchemaException catch (error) {
      throw ServerNotificationFailure(
        error.unsupportedVersion
            ? ServerNotificationFailureKind.permanent
            : ServerNotificationFailureKind.transient,
        status: 200,
      );
    } on FormatException {
      throw const ServerNotificationFailure(
          ServerNotificationFailureKind.transient,
          status: 200);
    }
  }

  Never _throwFor(http.Response response, {required bool walkingCursor}) {
    final status = response.statusCode;
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    if (status == 429) {
      throw ServerNotificationFailure(ServerNotificationFailureKind.rateLimited,
          retryAfter: retryAfter, status: status);
    }
    if (status == 400 && walkingCursor) {
      throw const _StaleCursor();
    }
    final transient = status >= 500 || status == 408;
    throw ServerNotificationFailure(
      transient
          ? ServerNotificationFailureKind.transient
          : ServerNotificationFailureKind.permanent,
      retryAfter: retryAfter,
      status: status,
    );
  }
}

/// `Retry-After` in seconds, as the contract defines it. Anything else counts
/// as absent, and the backoff applies alone.
@visibleForTesting
Duration? parseRetryAfter(String? value) {
  final seconds = int.tryParse(value?.trim() ?? '');
  return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
}
