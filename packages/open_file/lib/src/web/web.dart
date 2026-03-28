import 'dart:async';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html';

Future<bool> open(String uri) {
  return window
      .resolveLocalFileSystemUrl(uri)
      .then((_) => true)
      .catchError((e) => false);
}
