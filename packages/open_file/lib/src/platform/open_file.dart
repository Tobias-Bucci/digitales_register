import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_file/src/common/open_result.dart';

// ignore: avoid_classes_with_only_static_members
class OpenFile {
  static const MethodChannel _channel = MethodChannel('open_file');

  ///linuxDesktopName like 'xdg'/'gnome'
  static Future<OpenResult> open(String filePath,
      {String? type, String? uti, String linuxDesktopName = "xdg"}) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      late final int resultCode;
      if (Platform.isMacOS || Platform.isWindows) {
        final process = await Process.start("open", [filePath]);
        resultCode = await process.exitCode;
      } else if (Platform.isLinux) {
        final process =
            await Process.start("$linuxDesktopName-open", [filePath]);
        resultCode = await process.exitCode;
      } else {
        throw UnsupportedError("Unsupported platform");
      }
      return OpenResult(
          type: resultCode == 0 ? ResultType.done : ResultType.error,
          message: resultCode == 0
              ? "done"
              : "there are some errors when open $filePath");
    }

    final map = <String, String?>{
      "file_path": filePath,
      "type": type,
      "uti": uti,
    };
    final rawResult = await _channel.invokeMethod<String>('open_file', map);
    final resultMap = json.decode(rawResult ?? '{"message":"error","type":-4}')
        as Map<String, dynamic>;
    return OpenResult.fromJson(resultMap);
  }
}
