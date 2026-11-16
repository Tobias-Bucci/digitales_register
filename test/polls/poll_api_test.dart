import 'dart:convert';

import 'package:dr/polls/poll_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../server_notifications/support.dart';

const _poll = '3d6f0c2e-9b1a-4c55-8e2f-6a7b8c9d0e1f';
const _voter = '6f1c1d2e-3a4b-4c5d-8e9f-0a1b2c3d4e5f';
const _optionB = 'c8e2a4f6-1b3d-4a5c-9e7f-0a1b2c3d4e5f';

class _Server {
  final List<http.Request> requests = [];
  http.Response Function(http.Request) answer = (_) => http.Response('', 500);

  late final PollApi api = PollApi(
    baseUri: baseUri,
    client: MockClient((request) async {
      requests.add(request);
      return answer(request);
    }),
  );
}

void main() {
  group('reading a poll', () {
    test('sends no identifier, only the language', () async {
      final server = _Server()
        ..answer = (_) => jsonResponse(fixture('poll-open'));
      final result = await server.api.fetch(_poll, language: 'it');
      expect(result, isA<PollFetched>());
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(),
          'https://api.digitalesregister.com/api/v1/polls/$_poll?lang=it');
      expect(request.body, isEmpty);
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')));
      expect(request.toString() + request.headers.toString(),
          isNot(contains(_voter)));
      expect(request.followRedirects, isFalse);
    });

    test('404 means gone, anything else failed', () async {
      final server = _Server()
        ..answer = (_) => jsonResponse({'error': {}}, status: 404);
      expect(await server.api.fetch(_poll, language: 'de'), isA<PollGone>());
      for (final response in [
        http.Response('', 500),
        http.Response('not json', 200),
        jsonResponse({'schema_version': 2}),
        jsonResponse(fixture('poll-open')..['poll'] = {'id': 'other'}),
      ]) {
        server.answer = (_) => response;
        expect(await server.api.fetch(_poll, language: 'de'),
            isA<PollFetchFailed>());
      }
    });

    test('a state of another poll is refused', () async {
      final other = fixture('poll-open');
      (other['poll'] as Map)['id'] = '00000000-0000-4000-8000-000000000001';
      final server = _Server()..answer = (_) => jsonResponse(other);
      expect(await server.api.fetch(_poll, language: 'de'),
          isA<PollFetchFailed>());
    });
  });

  group('voting', () {
    test('sends option, voter and format, nothing else', () async {
      final server = _Server()
        ..answer = (_) => jsonResponse(fixture('vote-receipt'));
      final result = await server.api
          .vote(_poll, optionId: _optionB, installationId: _voter);
      final request = server.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/polls/$_poll/vote');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'option_id': _optionB,
        'voter': _voter,
        'schema_version': 1,
      });
      final recorded = result as PollVoteRecorded;
      expect(recorded.optionId, _optionB);
      expect(recorded.alreadyVoted, isFalse);
      expect(recorded.results!.totalVotes, 7);
    });

    test('409 already_voted is success with the first choice', () async {
      final body = fixture('vote-already-voted-409');
      final server = _Server()..answer = (_) => jsonResponse(body, status: 409);
      final result = await server.api
          .vote(_poll, optionId: _optionB, installationId: _voter);
      final recorded = result as PollVoteRecorded;
      expect(recorded.optionId, body['option_id']);
      expect(recorded.optionId, isNot(_optionB));
      expect(recorded.alreadyVoted, isTrue);
    });

    test('410 closed, 404 gone, everything else failed', () async {
      final server = _Server();
      Future<PollVoteResult> vote(http.Response response) {
        server.answer = (_) => response;
        return server.api.vote(_poll, optionId: 'a', installationId: _voter);
      }

      expect(
          await vote(jsonResponse(fixture('error-poll-closed'), status: 410)),
          isA<PollVoteClosed>());
      expect(await vote(jsonResponse({}, status: 404)), isA<PollVoteGone>());
      for (final response in [
        jsonResponse(fixture('error-rate-limited'), status: 429),
        jsonResponse({
          'error': {'code': 'unsupported_client'}
        }, status: 400),
        jsonResponse({
          'error': {'code': 'something_new'}
        }, status: 409),
        jsonResponse({
          'error': {'code': 'whatever'}
        }, status: 426),
        http.Response('', 503),
        http.Response('<html>', 200),
      ]) {
        expect(await vote(response), isA<PollVoteFailed>(),
            reason: '${response.statusCode} ${response.body}');
      }
    });

    test('a network failure is a failed vote, not an exception', () async {
      final api = PollApi(
        baseUri: baseUri,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await api.vote(_poll, optionId: 'a', installationId: _voter),
          isA<PollVoteFailed>());
      expect(await api.fetch(_poll, language: 'de'), isA<PollFetchFailed>());
    });
  });
}
