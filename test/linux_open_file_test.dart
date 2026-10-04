import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file/open_file.dart';
import 'package:open_file/src/platform/linux_open_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('digitales_register/linux_file_open');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('passes local paths unchanged to the Linux runner', () async {
    const path = '/tmp/Prüfung mit Leerzeichen #1.pdf';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'open');
      expect(call.arguments, {'path': path});
      return {'type': 0, 'message': 'done'};
    });
    expect((await openLinuxFile(path)).type, ResultType.done);
  });

  test('OpenFile dispatches Linux calls to the portal handler', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'type': 0, 'message': 'done'});
    expect((await OpenFile.open('/tmp/file.txt')).type, ResultType.done);
  }, skip: !Platform.isLinux);

  test('preserves portal errors, cancellation and file errors', () async {
    for (final code in [-1, -2, -3, -4]) {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {'type': code, 'message': 'Opening failed'});
      final result = await openLinuxFile('/tmp/file.txt');
      expect(result.type, OpenResult.fromJson({'type': code}).type);
      expect(result.message, 'Opening failed');
    }
  });

  test('missing Linux handler returns an error without throwing', () async {
    expect((await openLinuxFile('/tmp/file.txt')).type, ResultType.error);
  });

  test('channel exceptions return an error without throwing', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) => Future<Object?>.error(
            PlatformException(code: 'portal_unavailable')));
    expect((await openLinuxFile('/tmp/file.txt')).type, ResultType.error);
  });

  test('malformed replies cannot be reported as success', () async {
    for (final reply in [
      null,
      <String, dynamic>{},
      {'type': 42},
      {'type': '0'}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => reply);
      expect((await openLinuxFile('/tmp/file.txt')).type, ResultType.error);
    }
  });
}
