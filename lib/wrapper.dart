// Copyright (C) 2021 Michael Debertol
// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/demo.dart';
import 'package:dr/diagnostics_network.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/privacy_log.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:mutex/mutex.dart';

typedef AddNetworkProtocolItem = void Function(NetworkProtocolItem item);

class UnexpectedLogoutException implements Exception {}

class AppRequestException implements Exception {
  const AppRequestException({
    required this.message,
    this.isTimeout = false,
    this.isConnectionIssue = false,
  });

  final String message;
  final bool isTimeout;
  final bool isConnectionIssue;

  @override
  String toString() => message;
}

class Wrapper {
  static bool _networkActivityEnabled = true;
  final cookieJar = DefaultCookieJar();
  late final Dio dio;
  final bool allowInsecureConnections;
  String get loginAddress => "${baseAddress}api/auth/login";
  String get baseAddress => "$url/v2/";
  String? user, pass, _url;
  bool demoMode = false;
  bool _appInForeground = _networkActivityEnabled;
  final Set<CancelToken> _activeRequestTokens = <CancelToken>{};
  bool get isAppInForeground => _appInForeground;

  void pauseNetworkActivity() {
    _networkActivityEnabled = false;
    _appInForeground = false;
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
    for (final token in _activeRequestTokens.toList()) {
      token.cancel('App moved to the background');
    }
    _activeRequestTokens.clear();
  }

  void resumeNetworkActivity() {
    _networkActivityEnabled = true;
    _appInForeground = true;
    _scheduleSessionRefresh();
  }

  Wrapper({this.allowInsecureConnections = false}) {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(DiagnosticsInterceptor());
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (!_appInForeground) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'App is in the background',
        ));
      } else {
        final token = options.cancelToken ?? CancelToken();
        options.cancelToken = token;
        _activeRequestTokens.add(token);
        handler.next(options);
      }
    }, onResponse: (response, handler) {
      _activeRequestTokens.remove(response.requestOptions.cancelToken);
      handler.next(response);
    }, onError: (error, handler) {
      _activeRequestTokens.remove(error.requestOptions.cancelToken);
      handler.next(error);
    }));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.userAgent =
          "Digitales-Register-App $appVersion; https://github.com/Tobias-Bucci/digitales_register";
      return client;
    };
    //dio.interceptors.add(DebugInterceptor());
  }

  String? get url => _url;
  set url(String? value) {
    if (value != _url) {
      // we should already be logged out, but why not double check
      logout(hard: true);
    }
    _url = value;
  }

  Future<bool> get loggedIn => _loggedIn;
  // This future will be not completed if a login is in progress
  Future<bool> _loggedIn = Future.value(false);
  VoidCallback? onLogout, onConfigLoaded, onRelogin;
  AddNetworkProtocolItem? onAddProtocolItem;
  late bool safeMode;

  bool noInternet = false;
  Future<bool> refreshNoInternet() async {
    if (!_appInForeground) return noInternet;
    final address = url != null ? baseAddress : "https://digitalesregister.it";
    return noInternet = await cannotConnectTo(address);
  }

  String? error;

  DateTime lastInteraction = DateTime.now();
  DateTime? _serverLogoutTime;
  Timer? _sessionRefreshTimer;
  late Config config;
  Future<dynamic> login(
    String? user,
    String? pass,
    String? tfaCode,
    String? url, {
    VoidCallback? logout,
    VoidCallback? configLoaded,
    VoidCallback? relogin,
    AddNetworkProtocolItem? addProtocolItem,
  }) async {
    if (user == 'demo' && pass == 'demo' && (url?.trim().isEmpty ?? true)) {
      demoMode = true;
      appClock.setDemoMode(true);
      this.url = '';
      _loggedIn = Future.value(true);
      this.user = user;
      this.pass = pass;
      await initializeDemoStore();
      config = Config(
        (b) => b
          ..autoLogoutSeconds = 300
          ..currentSemesterMaybe = 1
          ..fullName = 'Demo'
          ..imgSource = ''
          ..isStudentOrParent = true
          ..userId = 1,
      );
      configLoaded?.call();
      return;
    } else {
      demoMode = false;
      appClock.setDemoMode(false);
    }

    noInternet = false;
    if (logout != null) {
      onLogout = logout;
    } else {
      assert(onLogout != null);
    }
    if (configLoaded != null) {
      onConfigLoaded = configLoaded;
    } else {
      assert(onConfigLoaded != null);
    }
    if (relogin != null) {
      onRelogin = relogin;
    } else {
      assert(onRelogin != null);
    }
    if (addProtocolItem != null) {
      onAddProtocolItem = addProtocolItem;
    } else {
      assert(onAddProtocolItem != null);
    }
    this.url = url;
    if (!allowInsecureConnections &&
        (this.url?.isNotEmpty ?? false) &&
        Uri.parse(this.url!).scheme != 'https') {
      _loggedIn = Future.value(false);
      error =
          "Es konnte keine sichere HTTPS-Verbindung hergestellt werden. Bitte pruefe die eingegebene Adresse.";
      return null;
    }
    final loggedInCompleter = Completer<bool>();
    _loggedIn = loggedInCompleter.future;
    Map response;
    _clearCookies();
    try {
      response = getMap(
        (await _runRequest(
          "login",
          () => dio.post<dynamic>(
            loginAddress,
            data: {
              "username": user,
              "password": pass,
              if (tfaCode != null) "two_factor": tfaCode,
            },
          ),
        ))
            .data,
      )!;
    } catch (e) {
      loggedInCompleter.complete(false);
      privacyLog('technical_operation');
      if (_mapRequestError(e).isConnectionIssue || await refreshNoInternet()) {
        noInternet = true;
      }
      error = _mapRequestError(e).message;
      return null;
    }
    if (getBool(response["loggedIn"]) ?? false) {
      privacyLog('technical_operation');
      lastInteraction = DateTime.now();
      this.user = user;
      this.pass = pass;
      error = null;
      try {
        await _loadConfig();
      } on UnexpectedLogoutException {
        if (!loggedInCompleter.isCompleted) {
          loggedInCompleter.complete(false);
        }
        privacyLog('technical_operation');
        error =
            "Die Sitzung wurde direkt nach dem Login beendet. Das passiert oft, wenn dasselbe Konto gleichzeitig auf mehreren Geräten verwendet wird.";
        _serverLogoutTime = null;
        _sessionRefreshTimer?.cancel();
        _clearCookies();
        return null;
      } catch (_) {
        if (!loggedInCompleter.isCompleted) {
          loggedInCompleter.complete(false);
        }
        rethrow;
      }
      loggedInCompleter.complete(true);
      _serverLogoutTime =
          DateTime.now().add(Duration(seconds: config.autoLogoutSeconds));
      _scheduleSessionRefresh();
      onConfigLoaded!();
    } else {
      privacyLog('technical_operation');
      loggedInCompleter.complete(false);
      error = 'login.credentialsRejected';
      switch (getString(response["error"])) {
        case "two_factor_needed":
          final tfaCode = await _request2FA();
          if (tfaCode != null) {
            return login(user, pass, tfaCode, url);
          }
          return;
        case "two_factor_wrong":
          final tfaCode = await _request2FA(wasWrong: true);
          if (tfaCode != null) {
            return login(user, pass, tfaCode, url);
          }
          return;
      }
    }
    return response;
  }

  Future<String?> _request2FA({bool wasWrong = false}) {
    return showDialog(
      context: navigatorKey!.currentContext!,
      builder: (context) {
        final textInputController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) => InfoDialog(
            title: Text(context.l10n
                .text(wasWrong ? 'login.invalid2FA' : 'login.require2FA')),
            content: TextField(
              controller: textInputController,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.text('privacyConsent.cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  textInputController.value.text,
                ),
                child: Text(context.l10n.text('login.confirm2FA')),
              ),
            ],
          ),
        );
      },
    );
  }

  AppRequestException _mapRequestError(Object error) {
    if (error is AppRequestException) {
      return error;
    }
    if (error is TimeoutException) {
      return const AppRequestException(
        message: 'error.timeout',
        isTimeout: true,
        isConnectionIssue: true,
      );
    }
    if (error is DioException) {
      final isTimeout = error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout;
      final isConnectionIssue =
          isTimeout || error.type == DioExceptionType.connectionError;
      return AppRequestException(
        message: isTimeout ? 'error.timeout' : 'error.network',
        isTimeout: isTimeout,
        isConnectionIssue: isConnectionIssue,
      );
    }
    return const AppRequestException(
      message: 'error.generic',
    );
  }

  bool _isTransientRequestError(Object error) {
    final mapped = _mapRequestError(error);
    return mapped.isConnectionIssue;
  }

  Future<T> _runRequest<T>(
    String operation,
    Future<T> Function() request, {
    bool allowSingleRetry = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    var didRetry = false;
    while (true) {
      if (!_appInForeground) {
        throw const AppRequestException(message: 'App is in the background');
      }
      try {
        final result = await runZoned(request,
            zoneValues: {#diagnosticRetry: didRetry ? 1 : 0});
        stopwatch.stop();
        logPerformanceEvent(
          "network_request",
          <String, Object?>{
            "operation": operation,
            "elapsedMs": stopwatch.elapsedMilliseconds,
            "retried": didRetry,
          },
        );
        return result;
      } catch (error) {
        if (allowSingleRetry && !didRetry && _isTransientRequestError(error)) {
          didRetry = true;
          diagnostics.update('request_retry_count', 1);
          diagnostics.safeLog('request_retry');
          logPerformanceEvent(
            "network_retry",
            <String, Object?>{
              "operation": operation,
              "reason": _mapRequestError(error).message,
            },
          );
          continue;
        }
        stopwatch.stop();
        logPerformanceEvent(
          "network_failure",
          <String, Object?>{
            "operation": operation,
            "elapsedMs": stopwatch.elapsedMilliseconds,
            "error": _mapRequestError(error).message,
          },
        );
        throw _mapRequestError(error);
      }
    }
  }

  Future<dynamic> changePass(
      String url, String user, String oldPass, String newPass) async {
    this.url = fixupUrl(url);
    if (!allowInsecureConnections && Uri.parse(this.url!).scheme != 'https') {
      _loggedIn = Future.value(false);
      error =
          "Es konnte keine sichere HTTPS-Verbindung hergestellt werden. Bitte pruefe die eingegebene Adresse.";
      return null;
    }
    Map response;
    _clearCookies();
    try {
      response = getMap(
        (await _runRequest(
          "change_password",
          () => dio.post<dynamic>(
            "${baseAddress}api/auth/setNewPassword",
            data: {
              "username": user,
              "oldPassword": oldPass,
              "newPassword": newPass,
            },
          ),
        ))
            .data,
      )!;
    } catch (e) {
      _loggedIn = Future.value(false);
      privacyLog('technical_operation');
      error = _mapRequestError(e).message;
      return null;
    }
    if (response["error"] != null) {
      error = 'error.generic';
    } else {
      _loggedIn = Future.value(false);
      this.user = user;
      pass = newPass;
      error = null;
    }
    return response;
  }

  Future<void> _loadConfig() async {
    final response = await _runRequest(
      "load_config",
      () => dio.get<String>(baseAddress),
      allowSingleRetry: true,
    );
    final source = response.data;
    if (source == null) {
      throw const AppRequestException(
        message: "Die Konfigurationsseite konnte nicht geladen werden.",
      );
    }
    if (_isLoginPage(source)) {
      logPerformanceEvent("config_login_page", <String, Object?>{
        "statusCode": response.statusCode,
        "contentType": response.headers.value(Headers.contentTypeHeader),
        "path": response.realUri.path,
      });
      throw UnexpectedLogoutException();
    }
    diagnostics.values({
      'parser': 'authentication',
      'feature': 'authentication',
      'operation': 'parse',
      'response_format': 'html'
    });
    config = tryParse(source, parseConfig);
  }

  static Config parseConfig(String source) {
    return tryParse(source, (source) {
      if (_isLoginPage(source)) {
        throw const FormatException(
          "Received login redirect page instead of the expected config page.",
        );
      }

      final id = _readUserId(source);
      final fullName = _readFullName(source);
      final imgSource = _readImgSource(source);
      final autoLogout = _readAutoLogoutSeconds(source);
      final currentSemesterMaybe = _readCurrentSemester(source);
      final isStudentOrParent = _readIsStudentOrParent(source);
      return Config(
        (b) => b
          ..userId = id
          ..autoLogoutSeconds = autoLogout
          ..fullName = fullName
          ..imgSource = imgSource
          ..currentSemesterMaybe = currentSemesterMaybe
          ..isStudentOrParent = isStudentOrParent,
      );
    });
  }

  static bool _isLoginRedirectPage(String source) {
    return RegExp(
      r'^[\s\n]*<script type="text/javascript">\n?\s*window\.location = "https://.+\.digitalesregister.it/v2/login";\n?\s*</script>[\s\n]*$',
    ).hasMatch(source);
  }

  static bool _isLoginPage(String source) {
    return _isLoginRedirectPage(source) ||
        (RegExp(r'<html\b', caseSensitive: false).hasMatch(source) &&
            RegExp(r'<title\b[^>]*>\s*Login\s*</title>', caseSensitive: false)
                .hasMatch(source));
  }

  static String _readAssignmentValue(String source, String key) {
    final marker = "$key=";
    final start = source.indexOf(marker);
    if (start < 0) {
      throw FormatException("Missing '$marker' in config page.");
    }
    final valueStart = start + marker.length;
    final end = source.indexOf(";", valueStart);
    if (end < 0) {
      throw FormatException("Missing ';' after '$marker' in config page.");
    }
    return source.substring(valueStart, end).trim();
  }

  static String _readConfigValue(String source, String key) {
    final marker = "$key: ";
    final start = source.indexOf(marker);
    if (start < 0) {
      throw FormatException("Missing '$marker' in config page.");
    }
    final valueStart = start + marker.length;
    final end = source.indexOf(",", valueStart);
    if (end < 0) {
      throw FormatException("Missing ',' after '$marker' in config page.");
    }
    return source.substring(valueStart, end).trim();
  }

  static String _readRequiredSubstring(
    String source,
    String startMarker,
    String endMarker,
  ) {
    final start = source.indexOf(startMarker);
    if (start < 0) {
      throw FormatException("Missing '$startMarker' in config page.");
    }
    final valueStart = start + startMarker.length;
    final end = source.indexOf(endMarker, valueStart);
    if (end < 0) {
      throw FormatException(
        "Missing '$endMarker' after '$startMarker' in config page.",
      );
    }
    return source.substring(valueStart, end).trim();
  }

  static bool _readIsStudentOrParent(String source) {
    return !source.contains("var isStudentOrParent=0;");
  }

  static int? _readCurrentSemester(String source) {
    if (source.contains("semesterWechsel=1")) return 2;
    if (source.contains("semesterWechsel=2")) {
      return 1;
    } else {
      return null;
    }
  }

  static int _readAutoLogoutSeconds(String source) {
    return int.parse(_readConfigValue(source, "auto_logout_seconds"));
  }

  static int _readUserId(String source) {
    return int.parse(_readAssignmentValue(source, "currentUserId"));
  }

  static String _readAfterImgId(String source) {
    return source
        .substring(source.indexOf("navigationProfilePicture") +
            "navigationProfilePicture".length)
        .trim();
  }

  static String _readFullName(String source) {
    final afterImgId = _readAfterImgId(source);
    return _readRequiredSubstring(afterImgId, ">", "<");
  }

  static String _readImgSource(String source) {
    final afterImgId = _readAfterImgId(source);
    return _readRequiredSubstring(afterImgId, 'src="', '"');
  }

  final _loginMutex = Mutex();
  DateTime? _lastUnexpectedLogout;

  Future<bool> ensureLoggedIn({
    bool isRetryAfterUnexpectedLogout = false,
    bool forceRelogin = false,
  }) async {
    await _loginMutex.acquire();
    try {
      // If we somehow did not yet notice that we were logged out set the flag now
      if (_serverLogoutTime != null &&
          DateTime.now().isAfter(_serverLogoutTime!)) {
        _loggedIn = Future.value(false);
      }
      if (forceRelogin) {
        privacyLog('technical_operation');
        _loggedIn = Future.value(false);
        _lastUnexpectedLogout = DateTime.now();
      } else if (isRetryAfterUnexpectedLogout) {
        // If we noticed an unexpected logout, we set the loggedIn flag here and try logging in again.
        // Since this has the potential of ending up in an infinite loop we only attempt a login following an unexpected logout
        // at most once every minute.
        if (_lastUnexpectedLogout
                ?.add(const Duration(minutes: 1))
                .isAfter(DateTime.now()) ??
            false) {
          privacyLog('technical_operation');
          privacyLog('technical_operation');
        } else {
          privacyLog('technical_operation');
          _loggedIn = Future.value(false);
          _lastUnexpectedLogout = DateTime.now();
        }
      }

      if (!await _loggedIn) {
        if (user != null && pass != null) {
          await login(user, pass, null, url);
          if (!await _loggedIn) {
            if (noInternet) {
              await actions.noInternet(true);
            } else {
              logout(hard: true, logoutForcedByServer: true);
            }
            return false;
          } else {
            onRelogin!();
          }
        } else {
          if (noInternet) {
            await actions.noInternet(true);
          }
          return false;
        }
      }
    } finally {
      _loginMutex.release();
    }
    return true;
  }

  Future<dynamic> send(
    String url, {
    Map<String, Object?> args = const <String, Object?>{},
    String method = "POST",
    bool isRetryAfterUnexpectedLogout = false,
    bool forceRelogin = false,
    int unexpectedLogoutRetryCount = 0,
  }) async {
    if (!_appInForeground) return null;
    if (demoMode) {
      diagnostics.resetRequest();
      diagnostics.update('data_source', 'local');
      return await getDemoResponse(url, args);
    }
    assert(!url.startsWith("/"));

    if (!await ensureLoggedIn(
      isRetryAfterUnexpectedLogout: isRetryAfterUnexpectedLogout,
      forceRelogin: forceRelogin,
    )) {
      privacyLog('technical_operation');
      return null;
    }
    if (!_appInForeground) return null;

    dynamic responseData;
    try {
      final response = await _runRequest(
        "$method $url",
        () => method == "POST"
            ? dio.post<dynamic>(
                baseAddress + url,
                data: args,
              )
            : method == "GET"
                ? dio.get<dynamic>(
                    baseAddress + url,
                  )
                : throw Exception(
                    "invalid method: $method; expected POST or GET",
                  ),
        allowSingleRetry: method == "GET",
      );
      responseData = response.data;
    } on Exception catch (e) {
      await _handleError(e);
      onAddProtocolItem!(NetworkProtocolItem((b) => b
        ..address = DiagnosticSanitizer.endpoint(url)
        ..response = responseData == null ? 'failed' : 'completed'
        ..parameters = '[redacted]'));
      return null;
    }
    onAddProtocolItem!(NetworkProtocolItem((b) => b
      ..address = DiagnosticSanitizer.endpoint(url)
      ..response = responseData == null ? 'failed' : 'completed'
      ..parameters = '[redacted]'));

    // returned if we were logged out (there should be whitespace at both ends, but the editor is removing it):
    //	<script type="text/javascript">
    //window.location = "https://vinzentinum.digitalesregister.it/v2/login";
    //</script>

    if (responseData is String && _isLoginPage(responseData)) {
      // This is a very frequently reported bug, but I don't have an idea as to why this is happening.
      // Possible causes might be that the user's time is off, or the user might be trying to log in from a different device at the same time.

      // First try a normal background relogin, then one forced relogin.
      // If the server still keeps redirecting us to login, fail this request quietly
      // instead of surfacing an exception in the UI.
      if (unexpectedLogoutRetryCount >= 2) {
        privacyLog('technical_operation');
        error = "Die Sitzung konnte nicht automatisch erneuert werden.";
        _loggedIn = Future.value(false);
        return null;
      }

      // Retry the request.
      return send(
        url,
        args: args,
        method: method,
        isRetryAfterUnexpectedLogout: true,
        forceRelogin: unexpectedLogoutRetryCount >= 1,
        unexpectedLogoutRetryCount: unexpectedLogoutRetryCount + 1,
      );
    }
    return responseData;
  }

  Future<dynamic> sendBytes(
    String url, {
    required List<int> bytes,
    String contentType = "application/octet-stream",
    String fileName = "upload.bin",
    bool isRetryAfterUnexpectedLogout = false,
    bool forceRelogin = false,
    int unexpectedLogoutRetryCount = 0,
  }) async {
    if (!_appInForeground) return null;
    if (demoMode) {
      return await getDemoBytesResponse(
        url,
        bytes: bytes,
        contentType: contentType,
        fileName: fileName,
      );
    }
    assert(!url.startsWith("/"));

    if (!await ensureLoggedIn(
      isRetryAfterUnexpectedLogout: isRetryAfterUnexpectedLogout,
      forceRelogin: forceRelogin,
    )) {
      privacyLog('technical_operation');
      return null;
    }
    if (!_appInForeground) return null;

    dynamic responseData;
    try {
      final formData = FormData.fromMap(
        <String, Object>{
          "file": MultipartFile.fromBytes(
            bytes,
            filename: fileName,
            contentType: DioMediaType.parse(contentType),
          ),
        },
      );
      final response = await _runRequest(
        "POST $url",
        () => dio.post<dynamic>(
          baseAddress + url,
          data: formData,
        ),
      );
      responseData = response.data;
    } on Exception catch (e) {
      await _handleError(e);
      onAddProtocolItem!(NetworkProtocolItem((b) => b
        ..address = DiagnosticSanitizer.endpoint(url)
        ..response = responseData == null ? 'failed' : 'completed'
        ..parameters = '[redacted]'));
      return null;
    }
    onAddProtocolItem!(NetworkProtocolItem((b) => b
      ..address = DiagnosticSanitizer.endpoint(url)
      ..response = responseData == null ? 'failed' : 'completed'
      ..parameters = '[redacted]'));

    if (responseData is String && _isLoginRedirectPage(responseData)) {
      if (unexpectedLogoutRetryCount >= 2) {
        privacyLog('technical_operation');
        error = "Die Sitzung konnte nicht automatisch erneuert werden.";
        _loggedIn = Future.value(false);
        return null;
      }
      return sendBytes(
        url,
        bytes: bytes,
        contentType: contentType,
        fileName: fileName,
        isRetryAfterUnexpectedLogout: true,
        forceRelogin: unexpectedLogoutRetryCount >= 1,
        unexpectedLogoutRetryCount: unexpectedLogoutRetryCount + 1,
      );
    }
    return responseData;
  }

  Future<void> _handleError(Exception e) async {
    if (!_appInForeground) return;
    privacyLog('technical_operation');
    final requestError = _mapRequestError(e);
    if (requestError.isConnectionIssue || await refreshNoInternet()) {
      noInternet = true;
      _loggedIn = Future.value(false);
      await actions.noInternet(true);
      error = "Keine Internetverbindung";
    } else {
      error = requestError.toString();
    }
  }

  void _scheduleSessionRefresh() {
    _sessionRefreshTimer?.cancel();
    if (!_appInForeground || demoMode || _serverLogoutTime == null) {
      return;
    }
    var delay = _serverLogoutTime!
        .subtract(const Duration(seconds: 25))
        .difference(DateTime.now());
    if (delay.isNegative) {
      delay = Duration.zero;
    }
    _sessionRefreshTimer = Timer(
      delay,
      () => unawaited(_refreshSession()),
    );
  }

  Future<void> _refreshSession() async {
    if (!_appInForeground) return;
    if (!await _loggedIn) return;
    if (demoMode) return;
    if (_serverLogoutTime == null) return;

    Map? result;
    try {
      result = getMap(
        await send(
          "api/auth/extendSession",
          args: <String, Object?>{
            "lastAction": lastInteraction.millisecondsSinceEpoch ~/ 1000,
          },
        ),
      );
    } catch (error) {
      privacyLog('technical_operation');
      logPerformanceEvent("session_refresh_failed", <String, Object?>{
        "reason": error.runtimeType.toString(),
        "forcedLogout": true,
      });
      logout(hard: safeMode, logoutForcedByServer: true);
      return;
    }
    if (result == null) {
      logPerformanceEvent(
        "session_refresh_failed",
        <String, Object?>{"forcedLogout": true},
      );
      logout(hard: safeMode, logoutForcedByServer: true);
      return;
    }
    if (result["forceLogout"] == true) {
      logPerformanceEvent(
        "session_refresh_forced_logout",
      );
      logout(hard: safeMode, logoutForcedByServer: true);
      return;
    }
    _serverLogoutTime = DateTime.fromMillisecondsSinceEpoch(
      (result["newExpiration"] as int) * 1000,
    );
    _scheduleSessionRefresh();
  }

  void interaction() {
    lastInteraction = DateTime.now();
  }

  void logout({required bool hard, bool logoutForcedByServer = false}) {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
    if (_appInForeground && !logoutForcedByServer && _url != null) {
      unawaited(dio.get<dynamic>("${baseAddress}logout"));
    }
    if (hard) {
      if (logoutForcedByServer) {
        onLogout!();
      }
      _url = user = pass = null;
      _serverLogoutTime = null;
    }
    logPerformanceEvent(
      "logout",
      <String, Object?>{
        "hard": hard,
        "forcedByServer": logoutForcedByServer,
      },
    );
    _loggedIn = Future.value(false);
    _clearCookies();
  }

  void _clearCookies() {
    cookieJar.deleteAll();
  }
}
