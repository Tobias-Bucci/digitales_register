import 'package:dr/course_materials.dart';
import 'package:dr/external_links.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

// #141: links in the course materials were not shown or did not open.
CourseMaterialEntry _entry(Map<String, Object?> json) =>
    CourseMaterialEntry.fromJson({
      'id': 1,
      'courseContentId': 2,
      'title': 'Material',
      'hidden': 0,
      ...json,
    });

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(() async {
    externalLinkLauncherOverride = null;
    await resetTestState();
  });

  group('which entries are links', () {
    test('an entry of the type link', () {
      final entry = _entry(
          {'type': 'link', 'link': 'https://example.org/a', 'file': null});
      expect(entry.isLink, isTrue);
      expect(entry.linkTarget, 'https://example.org/a');
    });

    test('an address without a file, whatever the type is called', () {
      for (final type in ['url', 'weblink', '', 'file']) {
        final entry =
            _entry({'type': type, 'link': 'www.example.org/a', 'file': null});
        expect(entry.isLink, isTrue, reason: type);
        expect(entry.linkTarget, 'www.example.org/a', reason: type);
      }
    });

    test('a file stays a file even if it also has an address', () {
      final entry = _entry({
        'type': 'file',
        'link': 'https://example.org/a',
        'file': 'f_1.pdf',
      });
      expect(entry.isLink, isFalse);
      expect(entry.linkTarget, isNull);
    });

    test('a link whose address is only in its title', () {
      final entry = _entry({
        'type': 'link',
        'link': null,
        'title': 'Video: https://example.org/watch?v=1.',
      });
      expect(entry.isLink, isTrue);
      expect(entry.linkTarget, 'https://example.org/watch?v=1');
    });

    test('an entry without a file whose title is an address', () {
      final entry = _entry(
          {'type': 'file', 'file': null, 'title': '(WWW.Example.org/x)'});
      expect(entry.isLink, isTrue);
      expect(entry.linkTarget, 'WWW.Example.org/x');
    });

    test('an empty link of the type link is still a link, without target', () {
      final entry = _entry({'type': 'link', 'link': '   ', 'title': 'Video'});
      expect(entry.isLink, isTrue);
      expect(entry.linkTarget, isNull);
    });

    test('a link without a title is named by its address', () {
      final entry =
          _entry({'type': 'link', 'link': 'https://example.org', 'title': ''});
      expect(entry.displayTitle, 'https://example.org');
    });

    test('a saved link from the cache is still a link', () {
      final entry = _entry({'type': 'url', 'link': 'https://example.org'});
      final restored = CourseMaterialEntry.fromJson(entry.toJson());
      expect(restored.isLink, isTrue);
      expect(restored.linkTarget, 'https://example.org');
    });

    test('links are not dropped while parsing a topic', () {
      final topic = CourseMaterialTopic.fromJson({
        'id': 1,
        'title': 'Links',
        'number': 1,
        'entries': [
          {'id': 1, 'type': 'link', 'link': 'https://a.org', 'hidden': 0},
          {'id': 2, 'type': 'url', 'link': 'b.org/x', 'hidden': 0},
          {'id': 3, 'type': 'link', 'link': 'https://c.org', 'hidden': 1},
        ],
      });
      expect(topic.entries.map((e) => e.id), [1, 2]);
      expect(topic.entries.every((e) => e.isLink), isTrue);
    });
  });

  group('opening a link', () {
    late List<Uri> launched;
    setUp(() {
      launched = [];
      externalLinkLauncherOverride = (uri) async {
        launched.add(uri);
        return true;
      };
    });

    Future<CourseMaterialOpenResult> open(Map<String, Object?> json) =>
        openCourseMaterialEntryWithStatus(_entry(json));

    test('opens the address in the browser', () async {
      expect(await open({'type': 'link', 'link': 'https://example.org/a'}),
          CourseMaterialOpenResult.opened);
      expect(launched, [Uri.parse('https://example.org/a')]);
    });

    test('an address without a scheme opens with https', () async {
      expect(await open({'type': 'link', 'link': 'www.school.it/x'}),
          CourseMaterialOpenResult.opened);
      expect(launched, [Uri.parse('https://www.school.it/x')]);
    });

    test('an address in the title opens', () async {
      expect(
          await open({
            'type': 'link',
            'title': 'Siehe https://example.org/b',
          }),
          CourseMaterialOpenResult.opened);
      expect(launched, [Uri.parse('https://example.org/b')]);
    });

    for (final unsafe in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'intent://x#Intent;end',
      'mailto:a@b.org',
      'https://school.it@evil.example',
      'not a link',
      '',
    ]) {
      test('"$unsafe" fails without being opened', () async {
        expect(await open({'type': 'link', 'link': unsafe, 'title': 'X'}),
            CourseMaterialOpenResult.failed);
        expect(launched, isEmpty);
      });
    }

    test('a browser that refuses is a failure', () async {
      externalLinkLauncherOverride = (_) async => false;
      expect(await open({'type': 'link', 'link': 'https://example.org'}),
          CourseMaterialOpenResult.failed);
    });
  });
}
