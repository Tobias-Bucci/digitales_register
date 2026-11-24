import 'package:dr/host_platform.dart';
import 'package:flutter/foundation.dart';

/// One production policy shared by all Firebase telemetry adapters.
class TelemetryCapabilities {
  const TelemetryCapabilities(this.platform, {this.web = false});
  final TargetPlatform platform;
  final bool web;
  factory TelemetryCapabilities.current() => TelemetryCapabilities(
      HostPlatform.isAndroid
          ? TargetPlatform.android
          : HostPlatform.isIOS
              ? TargetPlatform.iOS
              : HostPlatform.isMacOS
                  ? TargetPlatform.macOS
                  : HostPlatform.isWindows
                      ? TargetPlatform.windows
                      : TargetPlatform.linux,
      web: kIsWeb);
  // Android and iOS only, as the privacy policy says (#162). macOS has no
  // Firebase configuration; it stays off there even if one is added.
  bool get supportsAnalytics =>
      !web && {TargetPlatform.android, TargetPlatform.iOS}.contains(platform);
  bool get supportsCrashlytics => supportsAnalytics;
}
