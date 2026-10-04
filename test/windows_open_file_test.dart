import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file/open_file.dart';
import 'package:open_file/src/platform/windows_open_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('digitales_register/windows_file_open');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Windows paths reach the shell handler unchanged', () async {
    const path = r'C:\Users\Test\Prüfung mit Leerzeichen #1.pdf';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'open');
      expect(call.arguments, {'path': path});
      return {'type': 0, 'message': 'done'};
    });
    expect((await openWindowsFile(path)).type, ResultType.done);
    if (Platform.isWindows) {
      expect((await OpenFile.open(path)).type, ResultType.done);
    }
  });

  test('Windows errors and missing associations remain failures', () async {
    for (final code in [-1, -2, -3, -4]) {
      messenger.setMockMethodCallHandler(channel, (_) async => {'type': code});
      expect((await openWindowsFile('C:\\file.pdf')).type,
          OpenResult.fromJson({'type': code}).type);
    }
  });

  test('missing handler and invalid replies cannot report success', () async {
    expect((await openWindowsFile('C:\\file.pdf')).type, ResultType.error);
    for (final reply in [
      null,
      {},
      {'type': 42},
      {'type': '0'},
      {'type': 0.0}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => reply);
      expect((await openWindowsFile('C:\\file.pdf')).type, ResultType.error);
    }
  });
}
