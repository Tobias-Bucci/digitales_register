import 'dart:io';

import 'package:dr/school_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux and Windows offer no system notifications', () {
    expect(schoolNotificationsSupported(),
        Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    if (Platform.isLinux || Platform.isWindows) {
      expect(SchoolNotificationService().supported, isFalse);
    }
  });
}
