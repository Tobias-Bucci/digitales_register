import 'dart:async';

import 'package:dr/host_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  // The suite was written against Windows: its mocks cover the Windows
  // storage and notification paths. Pin the platform checks to Windows so a
  // Linux or macOS host (CI) runs the same code paths. A test that needs
  // another platform sets HostPlatform.debugOverride itself and restores it.
  HostPlatform.debugOverride = HostOperatingSystem.windows;
  await testMain();
}
