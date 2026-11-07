import 'dart:io';

import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('contract fixtures', () {
    test('every list fixture parses completely', () {
      final lists = Directory('contract/fixtures')
          .listSync()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.startsWith('list-'))
          .map((name) => name.replaceAll('.json', ''))
          .toList();
      expect(lists, isNotEmpty);
      for (final name in lists) {
        final result = ServerNotificationPage.parse(fixture(name));
        expect(result.rejectedCount, 0, reason: name);
      }
    });

    test('typical fixture keeps all fields', () {
      final result = ServerNotificationPage.parse(fixture('list-typical'));
      expect(result.pollAfterSeconds, 300);
      expect(result.nextCursor, isNull);
      expect(result.serverTime, DateTime.utc(2026, 10, 22, 20));
      final [first, second, third] = result.notifications;
      expect(first.id, '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731');
      expect(first.revision, 3);
      expect(first.attentionRevision, 2);
      expect(first.type.critical, isTrue);
      expect(first.type.colorValue, 0xFFE9A23B);
      expect(first.link, isA<InternalNotificationLink>());
      expect(second.link, isA<ExternalNotificationLink>());
      expect(second.expiresAt, DateTime.utc(2026, 11, 20, 8, 30));
      expect(second.body, contains('\n'));
      expect(third.link, isNull);
    });

    test('the cursor of page 1 is kept verbatim', () {
      final result = ServerNotificationPage.parse(fixture('list-page-1'));
      expect(result.nextCursor, fixture('list-page-1')['next_cursor']);
    });

    test('a cached notification survives a round trip', () {
      final original = ServerNotificationPage.parse(fixture('list-typical'))
          .notifications
          .first;
      final copy = ServerNotification.tryParse(original.toJson())!;
      expect(copy.toJson(), original.toJson());
    });
  });

  group('allowlists match the published contract', () {
    final contract = contractText();

    test('every route key of the contract is known and has a destination', () {
      final section = contract.substring(contract.indexOf('App route key:'));
      final keys = RegExp('`([a-zA-Z]+)`')
          .allMatches(section.substring(0, section.indexOf('- type: object')))
          .map((match) => match[1]!)
          .toSet();
      expect(keys, hasLength(12));
      expect(serverNotificationRouteKeys, keys);
      expect(serverNotificationDestinations.keys.toSet(), keys);
    });

    test('every icon of the contract is mapped', () {
      final section = contract.substring(contract.indexOf('allowlisted icon'));
      final names = RegExp('`([a-z]+)`')
          .allMatches(section.substring(0, section.indexOf('New')))
          .map((match) => match[1]!)
          .toSet();
      expect(names, hasLength(9));
      expect(serverNotificationIcons.keys.toSet(), names);
    });

    test('an unknown icon gets the fallback', () {
      expect(serverNotificationIcon('skull'), serverNotificationFallbackIcon);
      expect(serverNotificationIcon('<svg>'), serverNotificationFallbackIcon);
      expect(serverNotificationIcon('wrench'), Icons.build_outlined);
    });
  });

  group('schema validation', () {
    test('unknown fields are ignored at every level', () {
      final json = page([
        {
          ...item(),
          'future': {'nested': true},
          'type': {...item()['type'] as Map, 'shape': 'round'},
        }
      ])
        ..['also_new'] = 1;
      final result = ServerNotificationPage.parse(json);
      expect(result.notifications, hasLength(1));
      expect(result.rejectedCount, 0);
    });

    test('a newer schema is refused as unsupported', () {
      expect(
        () => ServerNotificationPage.parse(page([])..['schema_version'] = 2),
        throwsA(isA<ServerNotificationSchemaException>()
            .having((e) => e.unsupportedVersion, 'unsupported', isTrue)),
      );
    });

    for (final entry in <String, Object?>{
      'not an object': <Object?>[],
      'no version': page([])..remove('schema_version'),
      'text version': page([])..['schema_version'] = '1',
      'bad server_time': page([])..['server_time'] = 'yesterday',
      'local server_time': page([])..['server_time'] = '2026-10-22T20:00:00',
      'no poll_after_seconds': page([])..remove('poll_after_seconds'),
      'zero poll_after_seconds': page([])..['poll_after_seconds'] = 0,
      'list is no list': page([])..['notifications'] = 'many',
      'empty cursor': page([])..['next_cursor'] = '',
      'numeric cursor': page([])..['next_cursor'] = 5,
    }.entries) {
      test('a broken envelope is refused: ${entry.key}', () {
        expect(() => ServerNotificationPage.parse(entry.value),
            throwsA(isA<ServerNotificationSchemaException>()));
      });
    }

    test('one malformed entry does not cost the others', () {
      final result = ServerNotificationPage.parse(page([
        item(),
        {'id': 'nonsense'},
        item(id: '5f0e2c1a-7f4d-4b52-9d43-2a6c0f3e1b10')..remove('title'),
        item(id: '2c9a7e44-1d6b-4c3f-8a55-73e1b9d0c2f4', attention: 0),
      ]));
      expect(result.notifications, hasLength(1));
      expect(result.rejectedCount, 3);
    });

    test('a bad link costs only the link', () {
      final link = {'kind': 'external', 'target': 'http://example.com'};
      final parsedItem = ServerNotification.tryParse(item(link: link));
      expect(parsedItem, isNotNull);
      expect(parsedItem!.link, isNull);
    });

    test('a bad color falls back, a bad expiry refuses the entry', () {
      expect(ServerNotification.tryParse(item(color: 'red'))!.type.colorValue,
          isNull);
      expect(ServerNotification.tryParse(item(expiresAt: 'soon')), isNull);
    });

    test('ids are compared case-insensitively', () {
      final upper = item(id: '8A3B64CD-8F53-42F1-AE2B-4D9D095FA731');
      expect(parsed(upper).id, '8a3b64cd-8f53-42f1-ae2b-4d9d095fa731');
    });
  });

  group('plain text', () {
    test('markup stays literal', () {
      const payload = '<script>alert(1)</script><b>x</b>';
      expect(parsed(item(title: payload, body: payload)).body, payload);
    });

    test('control and direction characters are removed', () {
      final hostile = String.fromCharCodes(
          [0x61, 0x00, 0x07, 0x202E, 0x62, 0x2066, 0x200F, 0x63]);
      expect(parsed(item(body: hostile)).body, 'abc');
    });

    test('line breaks stay in the body, not in the title', () {
      expect(parsed(item(body: 'a\r\nb')).body, 'a\nb');
      expect(parsed(item(title: 'a\nb')).title, 'a b');
    });

    test('overlong text is cut, by characters', () {
      expect(parsed(item(title: 'ä' * 500)).title.length, 120);
      expect(parsed(item(body: 'x' * 5000)).body.length, 2000);
    });

    test('text that is empty after cleaning refuses the entry', () {
      final invisible = String.fromCharCode(0x202E);
      expect(ServerNotification.tryParse(item(title: invisible)), isNull);
    });
  });

  group('links', () {
    test('accepts plain public https addresses', () {
      for (final url in [
        'https://example.com',
        'https://example.com/a/b?x=1#y',
        'https://sub.example.co.uk:8443/path',
        'https://xn--bcher-kva.example/',
      ]) {
        expect(validateExternalNotificationUrl(url), isNotNull, reason: url);
      }
    });

    test('refuses everything else', () {
      for (final url in [
        '',
        'http://example.com',
        'HTTPS://example.com',
        'javascript:alert(1)',
        'data:text/html,x',
        'file:///etc/passwd',
        'ftp://example.com',
        'https://user:pass@example.com',
        'https://example.com@evil.example',
        'https://127.0.0.1/',
        'https://[::1]/',
        'https://localhost/',
        'https://intranet/',
        'https://exa mple.com/',
        'https://exämple.com/',
        'https://example.com\\@evil.example',
        'https://example.com:0/',
        'https://example.com:99999/',
        'https://${'a' * 2100}.com',
      ]) {
        expect(validateExternalNotificationUrl(url), isNull, reason: url);
      }
    });

    test('unknown internal targets and kinds are no link', () {
      for (final link in [
        {'kind': 'internal', 'target': 'admin'},
        {'kind': 'internal', 'target': '/settings'},
        {'kind': 'deep', 'target': 'settings'},
        {'kind': 'internal'},
        'settings',
      ]) {
        expect(ServerNotificationLink.tryParse(link), isNull);
      }
    });

    test('every allowed internal target is accepted', () {
      for (final key in serverNotificationRouteKeys) {
        final link = ServerNotificationLink.tryParse(
            {'kind': 'internal', 'target': key});
        expect((link! as InternalNotificationLink).routeKey, key);
      }
    });
  });

  group('configuration', () {
    test('the default is the HTTPS production origin', () {
      expect(configuredServerNotificationBaseUri.toString(),
          'https://api.digitalesregister.com');
    });

    test('only plain https is accepted', () {
      expect(parseServerNotificationBaseUrl('https://example.com'), isNotNull);
      expect(parseServerNotificationBaseUrl('https://example.com/prefix'),
          isNotNull);
      for (final value in [
        'http://example.com',
        'example.com',
        '',
        'https://',
        'https://u:p@example.com',
        'https://example.com?x=1',
      ]) {
        expect(parseServerNotificationBaseUrl(value), isNull, reason: value);
      }
    });

    test('each platform has its contract value, macOS has none', () {
      expect(serverNotificationPlatform(web: true), 'web');
      for (final entry in {
        TargetPlatform.android: 'android',
        TargetPlatform.iOS: 'ios',
        TargetPlatform.windows: 'windows',
        TargetPlatform.linux: 'linux',
        TargetPlatform.macOS: null,
        TargetPlatform.fuchsia: null,
      }.entries) {
        expect(serverNotificationPlatform(web: false, platform: entry.key),
            entry.value);
      }
    });

    test('app versions lose build metadata and stay semantic', () {
      for (final entry in {
        '1.17.4': '1.17.4',
        '1.17.4+55': '1.17.4',
        '1.17.4.55': '1.17.4',
        ' 2.0.0 ': '2.0.0',
        '2.0.0-beta.1': '2.0.0-beta.1',
        '2.0.0-beta.1+12': '2.0.0-beta.1',
      }.entries) {
        expect(normalizeServerNotificationVersion(entry.key), entry.value);
      }
    });

    test('what the server refuses is not sent', () {
      for (final value in [
        '',
        '1',
        '1.2',
        'v1.2.3',
        '01.2.3',
        'abc',
        '1.2.x'
      ]) {
        expect(normalizeServerNotificationVersion(value), isNull,
            reason: value);
      }
    });
  });
}
