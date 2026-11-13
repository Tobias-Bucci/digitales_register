import 'package:flutter/foundation.dart';

/// Default API origin. `--dart-define=DR_NOTIFICATIONS_BASE_URL=...` replaces
/// it at build time.
const defaultServerNotificationBaseUrl = 'https://api.digitalesregister.com';

/// `--dart-define=DR_NOTIFICATIONS_ENABLED=false` removes the feature from a
/// build: nothing is fetched and the bell is not shown.
const serverNotificationsEnabledByBuild =
    bool.fromEnvironment('DR_NOTIFICATIONS_ENABLED', defaultValue: true);

const _configuredBaseUrl = String.fromEnvironment(
  'DR_NOTIFICATIONS_BASE_URL',
  defaultValue: defaultServerNotificationBaseUrl,
);

/// The API origin as a URI, or null if [value] is not plain HTTPS. There is no
/// fallback to another address: a bad value turns the feature off.
Uri? parseServerNotificationBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

Uri? get configuredServerNotificationBaseUri =>
    parseServerNotificationBaseUrl(_configuredBaseUrl);

/// The `platform` value of this build, or null where the API has none.
String? serverNotificationPlatform({
  bool web = kIsWeb,
  TargetPlatform? platform,
}) {
  if (web) return 'web';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.fuchsia => null,
  };
}

final _semanticVersion = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$');

/// The `app_version` value for [raw], or null if it is no semantic version.
///
/// The server accepts and ignores build metadata (`1.17.4+55`), and it needs
/// three numbers. The build number is left out because nothing needs it, which
/// also keeps a `+` out of the URL. A Windows file version with a fourth number
/// (`1.17.4.55`) is reduced to its first three.
String? normalizeServerNotificationVersion(String raw) {
  var version = raw.trim().split('+').first;
  final parts = version.split('.');
  if (parts.length == 4 && parts.every((part) => int.tryParse(part) != null)) {
    version = parts.take(3).join('.');
  }
  return version.length <= 64 && _semanticVersion.hasMatch(version)
      ? version
      : null;
}

/// What the client tells the server about itself. Nothing else is sent.
@immutable
class ServerNotificationSelection {
  const ServerNotificationSelection({
    required this.platform,
    required this.appVersion,
    required this.language,
  });

  final String platform;
  final String appVersion;
  final String language;

  /// A stored `ETag` is only valid for the selection it was received for.
  String get cacheKey => '$platform|$appVersion|$language';

  @override
  bool operator ==(Object other) =>
      other is ServerNotificationSelection && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
