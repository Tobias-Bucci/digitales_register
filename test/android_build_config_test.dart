import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracked Gradle properties do not pin a machine-specific JDK', () {
    final properties = File('android/gradle.properties')
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'));

    for (final line in properties) {
      expect(line, isNot(startsWith('org.gradle.java.home')));
      final value = line.substring(line.indexOf('=') + 1).trim();
      expect(value, isNot(matches(RegExp(r'^([A-Za-z]:[\\/]|/|~)'))),
          reason: 'absolute path in "$line"');
    }
  });
}
