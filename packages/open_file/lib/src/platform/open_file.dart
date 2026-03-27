import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_file/src/common/open_result.dart';

class OpenFile {
  static const MethodChannel _channel = const MethodChannel('open_file');

  ///linuxDesktopName like 'xdg'/'gnome'
  static Future<OpenResult> open(String filePath,
      {String? type, String? uti, String linuxDesktopName = "xdg"}) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      int _result;
      if (Platform.isMacOS || Platform.isWindows) {
        final process = await Process.start("open", [filePath]);
        _result = await process.exitCode;
      } else if (Platform.isLinux) {
        final process =
            await Process.start("$linuxDesktopName-open", [filePath]);
        _result = await process.exitCode;
      } else {
        throw UnsupportedError("Unsupported platform");
      }
      return OpenResult(
          type: _result == 0 ? ResultType.done : ResultType.error,
          message: _result == 0
              ? "done"
              : "there are some errors when open $filePath");
    }

    Map<String, String?> map = {
      "file_path": filePath,
      "type": type,
      "uti": uti
    };
    final _result = await _channel.invokeMethod('open_file', map);
    Map resultMap = json.decode(_result);
    return OpenResult.fromJson(resultMap as Map<String, dynamic>);
  }
}
