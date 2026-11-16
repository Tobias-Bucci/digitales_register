import 'dart:async';
import 'dart:convert';

import 'package:dr/polls/poll_models.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

@immutable
sealed class PollFetchResult {
  const PollFetchResult();
}

class PollFetched extends PollFetchResult {
  const PollFetched(this.state);
  final ServerPollState state;
}

/// `404`: the poll was deleted or has not started. Nothing can be voted.
class PollGone extends PollFetchResult {
  const PollGone();
}

/// Offline, a server error or a body this app cannot read.
class PollFetchFailed extends PollFetchResult {
  const PollFetchFailed();
}

@immutable
sealed class PollVoteResult {
  const PollVoteResult();
}

/// The vote is on the server. After a `409` [optionId] is the choice stored
/// with the first vote, which may differ from the one just sent.
class PollVoteRecorded extends PollVoteResult {
  const PollVoteRecorded({
    required this.optionId,
    required this.results,
    required this.alreadyVoted,
  });

  final String optionId;
  final ServerPollResults? results;
  final bool alreadyVoted;
}

/// `410`: the poll closed.
class PollVoteClosed extends PollVoteResult {
  const PollVoteClosed();
}

/// `404`: the poll is gone.
class PollVoteGone extends PollVoteResult {
  const PollVoteGone();
}

/// Everything else, `429` included: "voting is not possible right now".
class PollVoteFailed extends PollVoteResult {
  const PollVoteFailed({this.status});
  final int? status;
}

/// The public poll endpoints. Reading sends no identifier at all; only
/// [vote] sends the installation ID, because voting is what needs it.
class PollApi {
  PollApi({
    required this.baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client;

  final Uri baseUri;
  final Duration timeout;
  http.Client? _client;

  http.Client get _http => _client ??= http.Client();

  static const _maxBodyBytes = 256 * 1024;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$base$path', queryParameters: query);
  }

  Future<http.Response?> _send(http.BaseRequest request) async {
    // An HTTPS request must not end up somewhere else.
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    try {
      final streamed = await _http.send(request).timeout(timeout);
      final length = streamed.contentLength;
      if (length != null && length > _maxBodyBytes) return null;
      final response =
          await http.Response.fromStream(streamed).timeout(timeout);
      return response.bodyBytes.length > _maxBodyBytes ? null : response;
    } on Exception {
      return null;
    }
  }

  Object? _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// The poll in [language], with its result if voters may see it.
  Future<PollFetchResult> fetch(String pollId,
      {required String language}) async {
    final response = await _send(
        http.Request('GET', _uri('/api/v1/polls/$pollId', {'lang': language})));
    if (response == null) return const PollFetchFailed();
    if (response.statusCode == 404) return const PollGone();
    if (response.statusCode != 200) return const PollFetchFailed();
    final state = ServerPollState.tryParse(_json(response));
    if (state == null || state.poll.id != pollId) {
      return const PollFetchFailed();
    }
    return PollFetched(state);
  }

  /// Casts this installation's vote. `409 already_voted` is success.
  Future<PollVoteResult> vote(
    String pollId, {
    required String optionId,
    required String installationId,
  }) async {
    final request = http.Request('POST', _uri('/api/v1/polls/$pollId/vote'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'option_id': optionId,
        'voter': installationId,
        'schema_version': 1,
      });
    final response = await _send(request);
    if (response == null) return const PollVoteFailed();
    final status = response.statusCode;
    if (status == 200 || status == 409) {
      final body = _json(response);
      final chosen = body is Map ? body['option_id'] : null;
      final code = body is Map && body['error'] is Map
          ? (body['error'] as Map)['code']
          : null;
      if (chosen is String && (status == 200 || code == 'already_voted')) {
        return PollVoteRecorded(
          optionId: chosen,
          results:
              ServerPollResults.tryParse(body is Map ? body['results'] : null),
          alreadyVoted: status == 409,
        );
      }
      return PollVoteFailed(status: status);
    }
    if (status == 410) return const PollVoteClosed();
    if (status == 404) return const PollVoteGone();
    return PollVoteFailed(status: status);
  }

  void close() => _client?.close();
}
