import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the harmless .voltbl warning is silenced in the Windows build',
      () {
    final options = RegExp(r'/ignore:(\d+)')
        .allMatches(File('windows/runner/CMakeLists.txt').readAsStringSync())
        .map((match) => match.group(1));
    expect(options, ['4078']);
    expect(
      File('windows/CMakeLists.txt').readAsStringSync(),
      isNot(contains('/ignore:')),
    );
  });
}
