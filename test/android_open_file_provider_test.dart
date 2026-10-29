import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Android side of open_file cannot run in Dart tests; these checks keep
// its sharing configuration from widening again.
const _plugin = 'packages/open_file/android/src/main';

void main() {
  test('FileProvider shares only the app directories', () {
    final paths = File('$_plugin/res/xml/filepaths.xml').readAsStringSync();
    final roots = RegExp(r'<([a-z-]+-path)\b')
        .allMatches(paths)
        .map((match) => match[1])
        .toSet();
    expect(roots, {
      'external-cache-path',
      'external-files-path',
      'files-path',
      'cache-path',
    });
  });

  test('viewers get read access only through the viewing intent', () {
    final source = File(
            '$_plugin/java/com/crazecoder/openfile/OpenFilePlugin.java')
        .readAsStringSync();
    expect(source, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
    expect(source, isNot(contains('grantUriPermission(')));
    expect(source, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
  });
}
