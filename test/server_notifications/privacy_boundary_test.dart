import 'dart:io';

import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<File> _sources() => [
      Directory('lib/server_notifications'),
      Directory('lib/ui/server_notifications'),
    ]
        .expand((directory) => directory.listSync(recursive: true))
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

void main() {
  test('the feature cannot reach analytics or send events', () {
    final sources = _sources().toList();
    expect(sources, isNotEmpty);
    for (final file in sources) {
      final text = file.readAsStringSync();
      for (final forbidden in [
        'analytics_service',
        'product_analytics',
        'firebase',
        'diagnostics_service',
        'privacy_consent',
        '/events',
        "'POST'",
      ]) {
        expect(text.contains(forbidden), isFalse,
            reason: '${file.path} mentions $forbidden');
      }
    }
  });

  test('its routes have no name, so no screen event can come from them', () {
    final center =
        File('lib/ui/server_notifications/server_notification_center.dart')
            .readAsStringSync();
    expect(center.contains('RouteSettings'), isFalse);
    expect(center.contains('pushNamed'), isFalse);
  });

  test('it uses no identifier of the user, account or device', () {
    final api = File('lib/server_notifications/server_notification_api.dart')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join();
    for (final forbidden in ['username', 'school', 'deviceId', 'cookie_jar']) {
      expect(api.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('a real response of the production API parses', () {
    // Captured 2026-11-07 with one read-only GET.
    final page = ServerNotificationPage.parse({
      'schema_version': 1,
      'server_time': '2026-11-07T15:51:53Z',
      'poll_after_seconds': 303,
      'next_cursor': null,
      'notifications': <Object?>[],
    });
    expect(page.pollAfterSeconds, 303);
    expect(page.notifications, isEmpty);
    expect(page.nextCursor, isNull);
  });
}
