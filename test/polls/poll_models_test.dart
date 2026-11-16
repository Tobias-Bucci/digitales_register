import 'package:dr/polls/poll_models.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../server_notifications/support.dart';
import 'legacy/server_notification_links_before_polls.dart' as old_links;
import 'legacy/server_notification_models_before_polls.dart' as old;

const _pollId = '3d6f0c2e-9b1a-4c55-8e2f-6a7b8c9d0e1f';
const _webVote = 'https://www.digitalesregister.com/umfrage/$_pollId';

void main() {
  group('(a) poll announcement with the external fallback link', () {
    test('this version reads the poll and keeps the web link', () {
      final page = ServerNotificationPage.parse(fixture('list-poll'));
      expect(page.rejectedCount, 0);
      final item = page.notifications.single;
      final poll = item.poll!;
      expect(poll.id, _pollId);
      expect(poll.type, 'single_choice');
      expect(poll.question, 'Welche Funktion wünschst du dir als Nächstes?');
      expect(poll.options.map((o) => o.label),
          ['Stundenplan-Widget', 'Notenrechner', 'Dunkles App-Symbol']);
      expect(poll.closesAt, DateTime.utc(2026, 11, 30, 22));
      expect(poll.showResults, isTrue);
      expect((item.link! as ExternalNotificationLink).uri.toString(), _webVote);
      expect(item.type.icon, 'poll');
    });

    test('a cached poll announcement survives a round trip', () {
      final item = ServerNotificationPage.parse(fixture('list-poll'))
          .notifications
          .single;
      final copy = ServerNotification.tryParse(item.toJson())!;
      expect(copy.toJson(), item.toJson());
      expect(copy.poll!.options.length, 3);
    });
  });

  group('(b) unknown poll type', () {
    test('stays a plain announcement with its web link', () {
      final page =
          ServerNotificationPage.parse(fixture('list-poll-unknown-type'));
      expect(page.rejectedCount, 0);
      final item = page.notifications.single;
      expect(item.poll, isNull);
      expect((item.link! as ExternalNotificationLink).uri.toString(), _webVote);
      expect(item.title, isNotEmpty);
    });
  });

  group('(c) closed poll', () {
    test('parses with its final result, and cannot be voted', () {
      final state = ServerPollState.tryParse(fixture('poll-closed'))!;
      expect(state.open, isFalse);
      expect(state.poll.isClosedAt(DateTime.utc(2026, 11, 20, 10)), isTrue);
      final results = state.results!;
      expect(results.totalVotes, 12);
      final first = state.poll.options.first.id;
      expect(results.votesFor(first), 7);
      expect(results.percentFor(first), 58);
    });

    test('an open poll is open', () {
      final state = ServerPollState.tryParse(fixture('poll-open'))!;
      expect(state.open, isTrue);
      expect(state.results!.totalVotes, 7);
    });

    test('an unknown status means "cannot vote"', () {
      final json = fixture('poll-open')..['status'] = 'paused';
      expect(ServerPollState.tryParse(json)!.open, isFalse);
    });
  });

  group('(d) already voted 409', () {
    test('carries the first choice and the result', () {
      final body = fixture('vote-already-voted-409');
      expect((body['error'] as Map)['code'], 'already_voted');
      expect(body['option_id'], isA<String>());
      expect(ServerPollResults.tryParse(body['results'])!.totalVotes, 7);
    });
  });

  group('(e) payload with unknown extra fields', () {
    test('this version ignores them', () {
      final page =
          ServerNotificationPage.parse(fixture('future-list-extra-fields'));
      expect(page.rejectedCount, 0);
      final poll = page.notifications.single.poll!;
      expect(poll.options.first.label, 'Stundenplan-Widget');
    });
  });

  group('versions without polls (the model before #131)', () {
    // The fixtures of this issue, parsed by the announcement model that the
    // releases without poll support contain.
    for (final name in [
      'list-poll',
      'list-poll-unknown-type',
      'future-list-extra-fields',
    ]) {
      test('$name shows as an announcement with a working web link', () {
        final page = old.ServerNotificationPage.parse(fixture(name));
        expect(page.rejectedCount, 0, reason: name);
        final item = page.notifications.single;
        expect(item.title, isNotEmpty);
        expect(item.body, contains('App'));
        final link = item.link;
        expect(link, isA<old_links.ExternalNotificationLink>());
        expect((link! as old_links.ExternalNotificationLink).uri.toString(),
            _webVote);
      });
    }

    test('every list fixture still parses completely', () {
      for (final name in [
        'list-typical',
        'list-poll',
        'list-poll-unknown-type',
        'future-list-extra-fields',
      ]) {
        expect(old.ServerNotificationPage.parse(fixture(name)).rejectedCount, 0,
            reason: name);
      }
    });
  });

  group('broken poll payloads', () {
    Map<String, dynamic> withPoll(Object? poll) {
      final json = fixture('list-poll');
      final item = (json['notifications'] as List).single as Map;
      item['poll'] = poll;
      return json;
    }

    Map<String, dynamic> validPoll() =>
        (((fixture('list-poll')['notifications'] as List).single as Map)['poll']
            as Map<String, dynamic>);

    test('make it a plain announcement, never a lost one', () {
      final broken = <Object?>[
        'nope',
        42,
        <String, Object?>{},
        validPoll()..['id'] = 'not-a-uuid',
        validPoll()..['options'] = <Object?>[],
        validPoll()..['options'] = [validPoll()['options'][0]],
        validPoll()
          ..['options'] = [
            validPoll()['options'][0],
            validPoll()['options'][0],
          ],
        validPoll()..['closes_at'] = 'tomorrow',
        validPoll()..['show_results'] = 'yes',
        validPoll()..['question'] = '   ',
        validPoll()
          ..['options'] =
              List.generate(11, (i) => {'id': 'o$i', 'label': 'Option $i'}),
      ];
      for (final poll in broken) {
        final page = ServerNotificationPage.parse(withPoll(poll));
        expect(page.rejectedCount, 0, reason: '$poll');
        final item = page.notifications.single;
        expect(item.poll, isNull, reason: '$poll');
        expect(item.link, isA<ExternalNotificationLink>(), reason: '$poll');
      }
    });

    test('labels are plain text without control or bidi characters', () {
      final poll = validPoll()
        ..['question'] = 'Frage‮<b>?</b>\n'
        ..['options'] = [
          {'id': 'a', 'label': 'Ja\u0000'},
          {'id': 'b', 'label': 'Nein'},
        ];
      final parsed = ServerPoll.tryParse(poll)!;
      expect(parsed.question, 'Frage<b>?</b>');
      expect(parsed.options.first.label, 'Ja');
    });

    test('results with zero votes give zero percent', () {
      final results = ServerPollResults.tryParse({
        'total_votes': 0,
        'options': [
          {'id': 'a', 'votes': 0},
        ],
      })!;
      expect(results.percentFor('a'), 0);
      expect(results.percentFor('missing'), 0);
    });
  });
}
