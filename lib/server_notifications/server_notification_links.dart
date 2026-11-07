import 'package:flutter/foundation.dart';

const _urlMaxLength = 2048;

/// The app routes a notification may link to. Everything else is treated as
/// no link, so an unknown key from a newer server cannot do anything.
const serverNotificationRouteKeys = <String>{
  'homework',
  'grades',
  'absences',
  'calendar',
  'examCalendar',
  'classRegister',
  'courseMaterials',
  'homeworkSummary',
  'certificate',
  'messages',
  'settings',
  'profile',
};

final _hostLabel = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
final _alphabeticTld = RegExp(r'^[a-z]{2,}$');

bool _validHost(String host) {
  final labels = host.split('.');
  if (labels.length < 2) return false;
  final tld = labels.last;
  if (!_alphabeticTld.hasMatch(tld) && !tld.startsWith('xn--')) return false;
  return labels.every(_hostLabel.hasMatch);
}

/// The URI of [value] if it is an absolute HTTPS URL to a public DNS name, with
/// no credentials, in printable ASCII. Mirrors what the server accepts, so
/// that a compromised or stale response gains nothing.
Uri? validateExternalNotificationUrl(String value) {
  if (value.isEmpty || value.length > _urlMaxLength) return null;
  if (value.contains('\\') ||
      value.codeUnits.any((unit) => unit <= 0x20 || unit >= 0x7F)) {
    return null;
  }
  if (!value.startsWith('https://')) return null;
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
  if (value.substring(8).split(RegExp('[/?#]')).first.contains('@')) {
    return null;
  }
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
  return _validHost(uri.host.toLowerCase()) ? uri : null;
}

/// A validated link. Anything else never gets this far.
@immutable
sealed class ServerNotificationLink {
  const ServerNotificationLink();

  /// Null if there is no link or it fails validation.
  static ServerNotificationLink? tryParse(Object? json) {
    if (json is! Map) return null;
    final target = json['target'];
    if (target is! String) return null;
    switch (json['kind']) {
      case 'internal':
        return serverNotificationRouteKeys.contains(target)
            ? InternalNotificationLink(target)
            : null;
      case 'external':
        final uri = validateExternalNotificationUrl(target);
        return uri == null ? null : ExternalNotificationLink(uri);
      default:
        return null;
    }
  }

  Map<String, Object?> toJson();
}

class InternalNotificationLink extends ServerNotificationLink {
  const InternalNotificationLink(this.routeKey);

  final String routeKey;

  @override
  Map<String, Object?> toJson() => {'kind': 'internal', 'target': routeKey};
}

class ExternalNotificationLink extends ServerNotificationLink {
  const ExternalNotificationLink(this.uri);

  final Uri uri;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'external', 'target': uri.toString()};
}
