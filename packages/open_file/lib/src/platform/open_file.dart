import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_file/src/common/open_result.dart';
import 'package:open_file/src/platform/linux_open_file.dart';
import 'package:open_file/src/platform/windows_open_file.dart';

// ignore: avoid_classes_with_only_static_members
class OpenFile {
  static const MethodChannel _channel = MethodChannel('open_file');

  /// Replaces [Platform.operatingSystem] in tests so the platform dispatch
  /// can be exercised on any host.
  @visibleForTesting
  static String? debugOperatingSystemOverride;

  ///linuxDesktopName like 'xdg'/'gnome'
  static Future<OpenResult> open(String filePath,
      {String? type, String? uti, String linuxDesktopName = "xdg"}) async {
    final os = debugOperatingSystemOverride ?? Platform.operatingSystem;
    if (os != 'ios' && os != 'android') {
      late final int resultCode;
      if (os == 'windows') {
        return openWindowsFile(filePath);
      } else if (os == 'macos') {
        final process = await Process.start("open", [filePath]);
        resultCode = await process.exitCode;
      } else if (os == 'linux') {
        return openLinuxFile(filePath);
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
