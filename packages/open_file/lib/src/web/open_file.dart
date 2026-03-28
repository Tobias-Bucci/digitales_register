import 'dart:async';

import 'package:open_file/open_file.dart';

import 'web.dart' as web;

// ignore: avoid_classes_with_only_static_members
class OpenFile {
  OpenFile._();

  static Future<OpenResult> open(String? filePath,
      {String? type,
      String? uti,
      String linuxDesktopName = "xdg",
      bool linuxByProcess = false}) async {
    final opened = await web.open("file://$filePath");
    return OpenResult(
        type: opened ? ResultType.done : ResultType.error,
        message: opened ? "done" : "there are some errors when open $filePath");
  }
}
