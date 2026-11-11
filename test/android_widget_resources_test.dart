import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _widgetKinds = [
  'dashboard',
  'today',
  'grades',
  'school_bag',
  'preparation',
];

String _attribute(String xml, String name) {
  final match = RegExp('android:$name="([^"]*)"').firstMatch(xml);
  expect(match, isNotNull, reason: 'missing android:$name');
  return match!.group(1)!;
}

Map<String, String> _strings(String folder) {
  final xml = File('$_res/$folder/strings.xml').readAsStringSync();
  return {
    for (final match in RegExp(r'<string name="(\w+)"([^>]*)>([^<]*)</string>')
        .allMatches(xml))
      if (!match.group(2)!.contains('translatable="false"'))
        match.group(1)!: match.group(3)!,
  };
}

void main() {
  test('each widget has its own picker preview and description', () {
    final german = _strings('values');
    final previews = <String>{};
    for (final kind in _widgetKinds) {
      final info = File('$_res/xml/${kind}_widget_info.xml').readAsStringSync();

      final previewLayout = _attribute(info, 'previewLayout');
      expect(previewLayout, '@layout/widget_preview_$kind');
      expect(previews.add(previewLayout), isTrue);
      final layout =
          File('$_res/layout/widget_preview_$kind.xml').readAsStringSync();
      // A preview has no adapter, so it must show static rows.
      final views = RegExp(r'<([A-Za-z.]+)[\s>]')
          .allMatches(layout)
          .map((match) => match.group(1))
          .toSet();
      expect(
          views.difference(
              {'FrameLayout', 'LinearLayout', 'TextView', 'ImageView'}),
          isEmpty,
          reason: kind);
      expect(layout, contains('widget_item_background'), reason: kind);

      // minSdk is below 31, where launchers only read previewImage.
      final previewImage = _attribute(info, 'previewImage');
      expect(previewImage, '@drawable/widget_preview_image_$kind');
      expect(File('$_res/drawable/widget_preview_image_$kind.xml').existsSync(),
          isTrue);

      expect(
          _attribute(info, 'initialLayout'), isNot('@layout/widget_collection'),
          reason: 'a new $kind widget must not be titled Dashboard');

      final description = _attribute(info, 'description');
      expect(description, '@string/widget_${kind}_description');
      expect(german['widget_${kind}_description'],
          isNot(german['widget_${kind}_title']));
    }
  });

  test('every widget receiver has its own label', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final receivers = RegExp(r'<receiver\b[^>]*>[\s\S]*?</receiver>')
        .allMatches(manifest)
        .map((match) => match.group(0)!)
        .where((receiver) => receiver.contains('android.appwidget.provider'))
        .toList();
    expect(receivers, hasLength(_widgetKinds.length));
    final labels = receivers.map((receiver) => _attribute(receiver, 'label'));
    expect(labels.toSet(), hasLength(_widgetKinds.length));
    for (final label in labels) {
      expect(label, startsWith('@string/widget_'));
    }
  });

  test('widget strings exist in German, Italian and English', () {
    final german = _strings('values');
    for (final folder in ['values-it', 'values-en']) {
      expect(_strings(folder).keys.toSet(), german.keys.toSet(),
          reason: folder);
    }
    for (final value in german.values) {
      expect(value, isNot(matches(RegExp(r'oeffn|Eintraeg|schuetz'))));
    }
  });
}
