import 'dart:io';

import 'package:dr/host_platform.dart';
import 'package:dr/school_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux and Windows offer no system notifications', () {
    final original = HostPlatform.debugOverride;
    addTearDown(() => HostPlatform.debugOverride = original);
    for (final os in HostOperatingSystem.values) {
      HostPlatform.debugOverride = os;
      final expected = {
        HostOperatingSystem.android,
        HostOperatingSystem.iOS,
        HostOperatingSystem.macOS,
      }.contains(os);
      expect(schoolNotificationsSupported(), expected, reason: os.name);
    }
    for (final os in [HostOperatingSystem.linux, HostOperatingSystem.windows]) {
      HostPlatform.debugOverride = os;
      expect(SchoolNotificationService().supported, isFalse, reason: os.name);
    }
  });

  // Regression for #129: the replaced stock plugin stayed registered as a
  // new-intent listener with a null channel and crashed every notification
  // tap while the app was alive.
  test('Android plugin replacement unregisters the stock listeners', () {
    final source = File('android/app/src/main/kotlin/it/bucci/'
            'digitalesregister/SchoolLocalNotificationsPlugin.kt')
        .readAsStringSync();
    expect(
        source,
        contains(
            'engine.plugins.get(FlutterLocalNotificationsPlugin::class.java)'));
    expect(source, contains('SchoolLocalNotificationsPlugin(replaced)'));
    for (final removal in [
      'removeOnNewIntentListener(stale)',
      'removeRequestPermissionsResultListener(stale)',
      'removeActivityResultListener(stale)',
    ]) {
      expect(source, contains(removal));
    }
    for (final hook in [
      'override fun onAttachedToActivity(binding: ActivityPluginBinding) {\n'
          '        detachReplaced(binding)',
      'override fun onReattachedToActivityForConfigChanges('
          'binding: ActivityPluginBinding) {\n        detachReplaced(binding)',
    ]) {
      expect(source.replaceAll('\r\n', '\n'), contains(hook));
    }
  });
}
