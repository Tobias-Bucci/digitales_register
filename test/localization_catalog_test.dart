import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four catalogs cover every key with matching placeholders', () {
    final catalogs = <String, Map<String, dynamic>>{
      for (final language in ['de', 'it', 'en', 'lld'])
        language:
            jsonDecode(File('assets/locales/$language.json').readAsStringSync())
                as Map<String, dynamic>,
    };
    final reference = catalogs['de']!;
    Set<String> placeholders(String value) =>
        RegExp(r'\{([a-zA-Z]+)\}').allMatches(value).map((m) => m[1]!).toSet();
    for (final entry in catalogs.entries) {
      expect(entry.value.keys.toSet(), reference.keys.toSet(),
          reason: entry.key);
      for (final key in reference.keys) {
        expect(entry.value[key], isA<String>(), reason: '${entry.key}: $key');
        expect((entry.value[key] as String).trim(), isNotEmpty,
            reason: '${entry.key}: $key');
        expect(placeholders(entry.value[key] as String),
            placeholders(reference[key] as String),
            reason: '${entry.key}: $key');
      }
    }
    for (final key in reference.keys.where((k) => k.startsWith('privacy'))) {
      if ((reference[key] as String).length > 20) {
        expect(catalogs['lld']![key], isNot(reference[key]), reason: key);
      }
    }
  });
}
