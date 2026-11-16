import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _sources() => [
      Directory('lib/polls'),
      Directory('lib/ui/polls'),
    ]
        .expand((directory) => directory.listSync(recursive: true))
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

String _code(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('polls cannot reach analytics or diagnostics', () {
    final sources = _sources().toList();
    expect(sources, isNotEmpty);
    for (final file in sources) {
      final text = _code(file);
      for (final forbidden in [
        'analytics_service',
        'product_analytics',
        'firebase',
        'diagnostics_service',
        'privacy_consent',
        'RouteSettings',
        'pushNamed',
      ]) {
        expect(text.contains(forbidden), isFalse,
            reason: '${file.path} mentions $forbidden');
      }
    }
  });

  test('no device, account or school data goes into a vote', () {
    for (final file in _sources()) {
      final text = _code(file);
      for (final forbidden in [
        'username',
        'school',
        'device_info',
        'deviceInfo',
        'advertising',
        'platformDevice',
        'cookie_jar',
        'flutter_secure_storage',
      ]) {
        expect(text.contains(forbidden), isFalse,
            reason: '${file.path} mentions $forbidden');
      }
    }
  });

  test('the installation ID is read only to vote', () {
    // obtain() is the only way to the ID; the vote is its only caller.
    final callers = _sources()
        .where((file) => _code(file).contains('installationId.obtain()'))
        .map((file) => file.path.replaceAll(r'\', '/'))
        .toList();
    expect(callers, ['lib/polls/server_polls.dart']);
    final controller = _code(File('lib/polls/server_polls.dart'));
    final vote = controller.substring(controller.indexOf('Future<void> vote('));
    expect(vote.contains('installationId.obtain()'), isTrue);
    final beforeVote =
        controller.substring(0, controller.indexOf('Future<void> vote('));
    expect(beforeVote.contains('installationId.obtain()'), isFalse);

    final api = _code(File('lib/polls/poll_api.dart'));
    final fetch = api.substring(api.indexOf('Future<PollFetchResult> fetch('),
        api.indexOf('Future<PollVoteResult> vote('));
    expect(fetch.contains('voter'), isFalse);
    expect(fetch.contains('installation'), isFalse);
  });
}
