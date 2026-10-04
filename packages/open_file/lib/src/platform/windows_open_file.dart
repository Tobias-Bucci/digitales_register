import 'package:flutter/services.dart';
import 'package:open_file/src/common/open_result.dart';

/// Opens a local path through the Windows shell, without command-line parsing.
Future<OpenResult> openWindowsFile(String path) async {
  try {
    final reply =
        await const MethodChannel('digitales_register/windows_file_open')
            .invokeMapMethod<String, dynamic>('open', {'path': path});
    if (reply == null ||
        reply['type'] is! int ||
        ![0, -1, -2, -3, -4].contains(reply['type'])) {
      return OpenResult(
          type: ResultType.error, message: 'Invalid Windows reply');
    }
    return OpenResult.fromJson(reply);
  } catch (_) {
    return OpenResult(
        type: ResultType.error, message: 'Windows file open failed');
  }
}
