import 'dart:io';
import 'package:flutter/foundation.dart';

/// One production policy shared by all Firebase telemetry adapters.
class TelemetryCapabilities {
  const TelemetryCapabilities(this.platform, {this.web = false});
  final TargetPlatform platform;
  final bool web;
  factory TelemetryCapabilities.current() => TelemetryCapabilities(
      Platform.isAndroid
          ? TargetPlatform.android
          : Platform.isIOS
              ? TargetPlatform.iOS
              : Platform.isMacOS
                  ? TargetPlatform.macOS
                  : Platform.isWindows
                      ? TargetPlatform.windows
                      : TargetPlatform.linux,
      web: kIsWeb);
  bool get supportsAnalytics =>
      !web &&
      {TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS}
          .contains(platform);
  bool get supportsCrashlytics => supportsAnalytics;
}
