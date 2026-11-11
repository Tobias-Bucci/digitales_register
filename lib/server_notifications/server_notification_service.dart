import 'dart:async';

import 'package:dr/app_language_controller.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_poller.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Connects the repository and the poller to the app's lifecycle.
///
/// Everything here fails open: a missing configuration, an unsupported
/// platform or an unreachable server leaves the app exactly as usable as
/// without this feature. It needs neither a login nor analytics consent, and it
/// never sends events.
class ServerNotificationService with WidgetsBindingObserver {
  ServerNotificationService({
    ServerNotificationRepository? repository,
    Uri? baseUri,
    String? platform,
    bool? enabledByBuild,
    Future<String> Function()? appVersion,
    http.Client? client,
    ServerNotificationPollPolicy policy = const ServerNotificationPollPolicy(),
  })  : repository = repository ?? ServerNotificationRepository(),
        _baseUri = baseUri ?? configuredServerNotificationBaseUri,
        _platform = platform ?? serverNotificationPlatform(),
        _enabledByBuild = enabledByBuild ?? serverNotificationsEnabledByBuild,
        _appVersion = appVersion ?? _packageVersion,
        _client = client {
    poller = ServerNotificationPoller(fetch: _sync, policy: policy);
  }

  static Future<String> _packageVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  final ServerNotificationRepository repository;
  late final ServerNotificationPoller poller;
  final Uri? _baseUri;
  final String? _platform;
  final bool _enabledByBuild;
  final Future<String> Function() _appVersion;
  final http.Client? _client;

  String? _version;
  String? _language;
  bool _started = false;

  /// Whether a login exists, so that links into the app can work.
  bool Function() isLoggedIn = () => false;

  /// Whether this build can use the feature at all.
  bool get enabled => _enabledByBuild && _baseUri != null && _platform != null;

  /// Begins fetching. Calling it again does nothing.
  Future<void> start() async {
    if (_started || !enabled) return;
    _started = true;
    try {
      _version = normalizeServerNotificationVersion(await _appVersion());
      if (_version == null) return;
      repository.api =
          ServerNotificationApi(baseUri: _baseUri!, client: _client);
      await repository.load();
      final binding = WidgetsBinding.instance;
      binding.addObserver(this);
      poller
        ..setActive(_isForeground(binding.lifecycleState))
        ..start();
    } catch (_) {
      // Without notifications the app works as before.
    }
  }

  /// The `lang` of the next request: the app's language, never the device's.
  String get _serverLanguage => serverNotificationLanguage(
      _language ?? appLanguageController.language.code);

  ServerNotificationSelection get _selection => ServerNotificationSelection(
        platform: _platform!,
        appVersion: _version!,
        language: _serverLanguage,
      );

  Future<int?> _sync() => repository.sync(_selection);

  /// Asks for the texts in [language], an [AppLanguage.code], from now on.
  /// Fetches again only when that changes what the server is asked for.
  void setLanguage(String language) {
    final before = _serverLanguage;
    _language = language;
    if (_serverLanguage != before) poller.selectionChanged();
  }

  /// Updates on request of the user, within the limits of the poller.
  void refresh() {
    if (_started) poller.refresh();
  }

  /// Only `hidden`, `paused` and `detached` mean nobody can see the app.
  /// `inactive` is a desktop window without focus, or a brief transition.
  static bool _isForeground(AppLifecycleState? state) => switch (state) {
        AppLifecycleState.hidden ||
        AppLifecycleState.paused ||
        AppLifecycleState.detached =>
          false,
        _ => true,
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    poller.setActive(_isForeground(state));
  }

  void dispose() {
    poller.stop();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    repository.dispose();
  }
}

/// The `lang` sent for the app language [code].
///
/// The server reads only the primary subtag and answers anything it has no
/// texts for in German. Ladin (`lld`, locale `de-LLD` in the app) asks for
/// German outright: that is the language the app's Ladin builds on and the one
/// the register profile gets for Ladin too, and it does not depend on how a
/// server treats a tag it does not know.
String serverNotificationLanguage(String code) =>
    code == AppLanguage.lld.code ? AppLanguage.de.code : code;

/// The one instance of this process.
final ServerNotificationService serverNotifications =
    ServerNotificationService();
