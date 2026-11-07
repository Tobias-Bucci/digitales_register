import 'package:dr/reminder_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeReminderLink', () {
    test('empty input means no link', () {
      expect(normalizeReminderLink(''), '');
      expect(normalizeReminderLink('  \t\n '), '');
    });

    test('accepts http and https addresses as they are', () {
      for (final link in [
        'https://example.org',
        'http://example.org/menu?week=1#today',
        'https://localhost:8080/menu',
        'http://192.168.1.10/menu',
      ]) {
        expect(normalizeReminderLink(link), link);
      }
    });

    test('removes the surrounding whitespace', () {
      expect(
        normalizeReminderLink('  https://example.org/a \n'),
        'https://example.org/a',
      );
    });

    test('normalizes the spelling of the scheme and host', () {
      expect(
          normalizeReminderLink('HTTPS://Example.ORG'), 'https://example.org');
    });

    test('adds https:// to something that looks like a domain', () {
      expect(normalizeReminderLink('example.org'), 'https://example.org');
      expect(normalizeReminderLink('www.example.org/menu?a=1'),
          'https://www.example.org/menu?a=1');
      expect(normalizeReminderLink('example.org:8080/menu'),
          'https://example.org:8080/menu');
    });

    test('rejects other schemes', () {
      for (final link in [
        'javascript:alert(1)',
        'mailto:someone@example.org',
        'tel:+390471000000',
        'file:///etc/passwd',
        'ftp://example.org',
        'intent://example.org#Intent;end',
        'data:text/html,hello',
      ]) {
        expect(normalizeReminderLink(link), isNull, reason: link);
      }
    });

    test('rejects what is no address', () {
      for (final link in [
        'hello',
        'not a link',
        'https://',
        'http://?a=1',
        'https://exa mple.org',
        'https://.example.org',
        'https://example.org.',
        'https://example..org',
        '://example.org',
        '.org',
      ]) {
        expect(normalizeReminderLink(link), isNull, reason: link);
      }
    });

    test('rejects a user name that hides the real host', () {
      expect(normalizeReminderLink('https://school.it@example.org'), isNull);
      expect(normalizeReminderLink('https://a:b@example.org'), isNull);
    });

    test('never throws on malformed input', () {
      for (final link in [
        'http://[',
        'https://[::1',
        'https://example.org:99999999999',
        'https://%zz',
        '%',
        ':',
        '://',
        '\u0000',
        'https://\u{1F600}',
        'h' * 100000,
      ]) {
        expect(() => normalizeReminderLink(link), returnsNormally,
            reason: link);
      }
    });
  });
}
