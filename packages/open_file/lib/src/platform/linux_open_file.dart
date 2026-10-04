import 'package:flutter/services.dart';
import 'package:open_file/src/common/open_result.dart';

/// Implemented by the Linux runner using OpenURI.OpenFile and a Unix FD.
Future<OpenResult> openLinuxFile(String path) async {
  try {
    final result =
        await const MethodChannel('digitales_register/linux_file_open')
            .invokeMapMethod<String, dynamic>('open', {'path': path});
    if (result == null ||
        result['type'] is! int ||
        !const [0, -1, -2, -3, -4].contains(result['type'])) {
      return OpenResult(
          type: ResultType.error, message: 'Invalid portal response');
    }
    return OpenResult.fromJson(result);
  } catch (error) {
    return OpenResult(type: ResultType.error, message: error.toString());
  }
}
