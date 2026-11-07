import 'dart:async';

import 'package:dr/app_language_controller.dart';
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

  ServerNotificationSelection get _selection => ServerNotificationSelection(
        platform: _platform!,
        appVersion: _version!,
        language: _language ?? appLanguageController.language.code,
      );

  Future<int?> _sync() => repository.sync(_selection);

  /// Asks for the texts in [language] from now on.
  void setLanguage(String language) {
    if (language == _language) return;
    final first = _language == null;
    _language = language;
    if (!first) poller.selectionChanged();
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

/// The one instance of this process.
final ServerNotificationService serverNotifications =
    ServerNotificationService();
