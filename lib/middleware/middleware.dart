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
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dr/actions/absences_actions.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/actions/certificate_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/actions/notifications_actions.dart';
import 'package:dr/actions/profile_actions.dart';
import 'package:dr/actions/routing_actions.dart';
import 'package:dr/actions/save_pass_actions.dart';
import 'package:dr/actions/settings_actions.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/notification_background_service.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/serializers.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Action, Notification;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

part 'absences.dart';
part 'calendar.dart';
part 'certificate.dart';
part 'dashboard.dart';
part 'grades.dart';
part 'login.dart';
part 'messages.dart';
part 'notifications.dart';
part 'pass.dart';
part 'profile.dart';
part 'routing.dart';
part 'settings.dart';

late FlutterSecureStorage secureStorage;
final AppStatePersistenceService statePersistenceService =
    AppStatePersistenceService();

@visibleForTesting
Duration noInternetRetryInterval = const Duration(seconds: 5);

Timer? _noInternetRetryTimer;
bool _noInternetRetryInFlight = false;

@visibleForTesting
Wrapper wrapper = Wrapper();

List<Middleware<AppState, AppStateBuilder, AppActions>> middleware({
  @visibleForTesting bool includeErrorMiddleware = true,
}) =>
    [
      if (includeErrorMiddleware) _errorMiddleware,
      _saveStateMiddleware,
      (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
            ..add(LoginActionsNames.updateLogout, _tap)
            ..add(SettingsActionsNames.saveNoData, _saveNoData)
            ..add(AppActionsNames.deleteData, _deleteData)
            ..add(AppActionsNames.load, _load)
            ..add(AppActionsNames.start, _start)
            ..add(DashboardActionsNames.refresh, _refresh)
            ..add(AppActionsNames.refreshNoInternet, _refreshNoInternet)
            ..add(AppActionsNames.noInternet, _noInternet)
            ..add(LoginActionsNames.loggedIn, _loggedIn)
            ..add(AppActionsNames.restarted, _restarted)
            ..combine(_absencesMiddleware)
            ..combine(_calendarMiddleware)
            ..combine(_dashboardMiddleware)
            ..combine(_gradesMiddleware)
            ..combine(_loginMiddleware)
            ..combine(_notificationsMiddleware)
            ..combine(_passMiddleware)
            ..combine(routingMiddleware)
            ..combine(_certificateMiddleware)
            ..combine(_messagesMiddleware)
            ..combine(_profileMiddleware)
            ..combine(_settingsMiddleware))
          .build(),
    ];

NextActionHandler _errorMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          Future<void> handleError(dynamic e, StackTrace? trace) async {
            log("Error caught by error middleware",
                error: e, stackTrace: trace);
            var stackTrace = trace;
            try {
              stackTrace ??= e.stackTrace as StackTrace?;
            } catch (e) {
              // we can't get a stack trace
            }
            var error = e.toString();
            if (e is! ParseException) {
              // ParseExceptions will already provide a more precise stack trace
              error += "\n\n$stackTrace";
            }
            error +=
                "\n\nApp Version: $appVersion\nOS: ${Platform.operatingSystem}\nServer: ${api.state.url}";
            await navigatorKey?.currentState?.push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) {
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor: Colors.red,
                      title: const Text("Fehler!"),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        Center(
                          child: ElevatedButton(
                            onPressed: () async {
                              await launchUrl(
                                Uri.parse(
                                  "https://docs.google.com/forms/d/e/1FAIpQLScTmSAZzj0bjwX_8IHVx9dVTTVrncJJpZo_D20dF7mrnU_zdQ/viewform?usp=sf_link&entry.1875208362=${Uri.encodeQueryComponent(error)}",
                                ),
                              );
                            },
                            child: const Text("Entwickler benachrichtigen"),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            """
Ein Fehler ist aufgetreten.
${e is UnexpectedLogoutException ? """

Dieser Fehler kann auftreten, wenn zwei Geräte gleichzeitig auf dasselbe Konto zugreifen.
In diesem Fall kannst du versuchen, die App zu schließen und erneut zu öffnen.

Falls dies nicht zutrifft, bitte benachrichtige uns, damit wir diesen Fehler beheben können.""" : e is ParseException ? """

Beim Einlesen der Daten ist ein Fehler aufgetreten.
Bitte benachrichtige uns, damit wir diesen Fehler beheben können.
Bitte beachte, dass das Fehlerprotokoll möglicherweise private Daten enthält.""" : """

Eine Funktion wird eventuell noch nicht unterstützt.
Bitte benachrichtige uns, damit wir diesen Fehler beheben können:"""}

 --  Fehlerprotokoll: --

$error""",
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }

          if (action.name == AppActionsNames.error.name) {
            await handleError(action.payload, null);
          } else {
            try {
              await next(action);
            } catch (e, stackTrace) {
              await handleError(e, stackTrace);
            }
          }
        };

void _tap(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) {
  wrapper.interaction();
  // do not call next: this action is only to update the logout time
}

Future<void> _refreshNoInternet(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  final noInternet = await wrapper.refreshNoInternet();
  await api.actions.noInternet(noInternet);
}

void _cancelNoInternetRetry() {
  _noInternetRetryTimer?.cancel();
  _noInternetRetryTimer = null;
}

@visibleForTesting
void resetNoInternetRetryForTest() {
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  noInternetRetryInterval = const Duration(seconds: 5);
}

void _scheduleNoInternetRetry() {
  if (_noInternetRetryTimer != null) {
    return;
  }
  _noInternetRetryTimer = Timer(
    noInternetRetryInterval,
    () {
      _noInternetRetryTimer = null;
      unawaited(_runNoInternetRetry());
    },
  );
}

Future<void> _runNoInternetRetry() async {
  if (_noInternetRetryInFlight) {
    return;
  }
  _noInternetRetryInFlight = true;
  try {
    await actions.refreshNoInternet();
  } finally {
    _noInternetRetryInFlight = false;
    if (wrapper.noInternet) {
      _scheduleNoInternetRetry();
    }
  }
}

Future<void> _noInternet(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  final prevNoInternet = api.state.noInternet;
  await next(action);
  final noInternet = api.state.noInternet;
  if (prevNoInternet != noInternet) {
    if (noInternet) {
      _scheduleNoInternetRetry();
      showSnackBar("Keine Verbindung");

      wrapper.logout(
        hard: false,
        logoutForcedByServer: true,
      );
    } else {
      _cancelNoInternetRetry();
      await api.actions.dashboardActions.refresh();
    }
  }
}

Future<void> _load(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) async {
  // By resetting the wrapper we clear all cookies.
  // However we don't want to reset the wrapper in tests
  if (wrapper is! Mock) {
    wrapper = Wrapper();
  }
  await NotificationBackgroundService.handleAppPaused();
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  statePersistenceService.clear();
  wrapper.noInternet = api.state.noInternet;
  await next(action);
  if (!api.state.noInternet) _popAll();
  dynamic login;
  try {
    login = json.decode(await secureStorage.read(key: "login") ?? "{}");
  } catch (e) {
    login = const <Never, Never>{};
    showSnackBar("Fehler beim Laden der gespeicherten Daten");
    log("Failed to load login credentials", error: e);
    try {
      await secureStorage.deleteAll();
    } catch (e) {
      showSnackBar("Bitte versuche, die App neu zu installieren.");
    }
  }

  await _checkShowUnmaintainedAlert();

  final user = getString(login["user"]);
  final pass = getString(login["pass"]);
  final url = getString(login["url"]);
  final List<String> otherAccounts = List.from(
    (login["otherAccounts"] as List?)
            ?.map<String>((dynamic login) => login["user"] as String) ??
        <String>[],
  );
  await api.actions.loginActions.setAvailableAccounts(otherAccounts);
  if ((api.state.url != null && api.state.url != url) ||
      (api.state.loginState.username != null &&
          api.state.loginState.username != user)) {
    // TODO: Figure out when exactly we'd hit this code path and how to handle it better.
    await api.actions.savePassActions.delete();
    await api.actions.routingActions.showLogin();
  } else {
    if (user != null && pass != null) {
      await api.actions.loginActions.login(
        LoginPayload((b) => b
          ..user = user
          ..pass = pass
          ..url = url
          ..fromStorage = true),
      );
    } else {
      await api.actions.routingActions.showLogin();
    }
  }
}

Future<void> _refresh(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<void> action) async {
  await next(action);
  await Future.wait([
    api.actions.dashboardActions.load(api.state.dashboardState.future),
    api.actions.notificationsActions.load(),
  ]);
}

Future<void> _loggedIn(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<LoggedInPayload> action) async {
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    statePersistenceService.clear();
  }
  if (action.payload.fromStorage) {
    // If we logged in with saved credentials password saving must be enabled.
    wrapper.safeMode = false;
  }
  if (!api.state.settingsState.noPasswordSaving &&
      !action.payload.fromStorage) {
    await api.actions.savePassActions.save();
  }
  deletedData = false;
  final key = getStorageKey(action.payload.username, wrapper.loginAddress);
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    log("loading state");
    final state = await _readFromStorage(key);
    if (state != null) {
      try {
        final serializedState =
            serializers.deserialize(json.decode(state) as Object);
        if (serializedState is SettingsState) {
          await api.actions.mountAppState(
            api.state.rebuild(
              (b) => b
                ..settingsState.replace(
                  // Override the previous password saving setting with whatever the user chose this time.
                  serializedState.rebuild(
                    (b) => b.noPasswordSaving =
                        api.state.settingsState.noPasswordSaving,
                  ),
                )
                ..settingsState.languageCode =
                    api.state.settingsState.languageCode,
            ),
          );
        } else if (serializedState is AppState) {
          final currentState = api.state;
          await api.actions.mountAppState(
            serializedState.rebuild(
              (b) => b
                ..loginState.replace(currentState.loginState)
                ..noInternet = currentState.noInternet
                ..config = currentState.config?.toBuilder()
                ..dashboardState.future = true
                ..gradesState.semester.replace(
                      currentState.gradesState.semester == Semester.all
                          ? serializedState.gradesState.semester
                          : currentState.gradesState.semester,
                    )
                // Override the previous password saving setting with whatever the user chose this time.
                ..settingsState.noPasswordSaving =
                    api.state.settingsState.noPasswordSaving
                ..settingsState.languageCode =
                    api.state.settingsState.languageCode,
            ),
          );
        }

        // next not at the beginning: bug fix (serialization)
        await next(action);

        await api.actions.settingsActions
            .saveNoPass(api.state.settingsState.noPasswordSaving);
      } catch (e) {
        showSnackBar("Fehler beim Laden der gespeicherten Daten");
        log("Failed to load data", error: e);
        await next(action);
      }
    } else {
      await next(action);
    }

    _popAll();
  } else {
    await next(action);
  }

  final notificationsEnabled = await NotificationBackgroundService.setEnabled(
    enabled: api.state.settingsState.pushNotificationsEnabled,
    triggerImmediatePoll: false,
  );
  if (!notificationsEnabled &&
      api.state.settingsState.pushNotificationsEnabled) {
    showSnackBar(
      "Benachrichtigungen sind nicht erlaubt und wurden deaktiviert.",
    );
    await api.actions.settingsActions.pushNotificationsEnabled(false);
  }

  for (final callback in api.state.loginState.callAfterLogin) {
    callback();
  }
  if (!action.payload.offlineOnly) {
    await Future.wait([
      api.actions.dashboardActions.load(api.state.dashboardState.future),
      api.actions.notificationsActions.load(),
      api.actions.profileActions.load(),
    ]);
  }
}

// This is to avoid saving data in an action right after deleting data,
// which would restore it.
@visibleForTesting
bool deletedData = false;

NextActionHandler _saveStateMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          await next(action);
          if (api.state.loginState.loggedIn &&
              api.state.loginState.username != null) {
            final immediately = action.name == AppActionsNames.saveState.name;
            if (immediately) {
              await statePersistenceService.flush(
                state: api.state,
                deletedData: deletedData,
                server: wrapper.loginAddress,
                writer: _writeToStorage,
                keyFactory: getStorageKey,
              );
            } else {
              statePersistenceService.schedule(
                state: api.state,
                deletedData: deletedData,
                server: wrapper.loginAddress,
                writer: _writeToStorage,
                keyFactory: getStorageKey,
              );
            }
          }
        };

String getStorageKey(String? user, String server) {
  // This is safe because the default Map in dart is a LinkedHashMap, which mantains
  // a stable ordering of its items.
  return json.encode({"username": user, "server_url": server});
}

String escapeKey(String key) {
  if (Platform.isWindows) {
    // secure_storage does not support certain characters on Windows.
    return key.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
  }
  return key;
}

Future<void> _writeToStorage(String key, String txt) async {
  await secureStorage.write(key: escapeKey(key), value: txt);
}

Future<String?> _readFromStorage(String key) async {
  try {
    return secureStorage.read(key: escapeKey(key));
  } catch (e) {
    try {
      await secureStorage.deleteAll();
    } catch (e) {
      showSnackBar("Fehler: Bitte versuche, die App neu zu installieren.");
    }
    return null;
  }
}

Future<void> _saveNoData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  await api.actions.saveState();
}

Future<void> _deleteData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  deletedData = true;
  await api.actions.saveState();
}

Future<void> _restarted(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  if (api.state.loginState.loggedIn &&
      DateTime.now().difference(wrapper.lastInteraction).inMinutes > 3) {
    wrapper.interaction();
    final poppedAnything = _popAll();
    if (!poppedAnything) {
      // If we pop something the routeObserver will trigger a reload of the dasboard.
      // However, if we are on the dashboard already, we need to this here.
      await api.actions.dashboardActions.refresh();
    }
  }
}

Future<void> _start(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Uri?> action,
) async {
  await api.actions.loginActions.clearAfterLoginCallbacks();
  if (action.payload != null) {
    await api.actions.setUrl(action.payload!.origin);
    final parameters = action.payload!.queryParameters;
    switch (parameters["semesterWechsel"]) {
      case "1":
        await api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.first),
        );
      case "2":
        await api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.second),
        );
    }
    switch (action.payload!.path) {
      case "":
      case "/":
      case "/v2/":
        break;
      case "/v2/login":
        if (parameters["resetmail"] == "true") {
          final email = parameters["email"];
          final token = parameters["token"];
          await api.actions.routingActions.showPassReset(
            ShowPassResetPayload(
              (b) => b
                ..token = token
                ..email = email,
            ),
          );
          return;
        }
        if (parameters["username"] != null) {
          await api.actions.loginActions.setUsername(parameters["username"]!);
        }
        if (parameters["redirect"] != null) {
          await redirectAfterLogin(
              parameters["redirect"]!.replaceFirst("#", ""), api);
        }
      default:
        showSnackBar("Dieser Link konnte nicht geöffnet werden");
    }
    await redirectAfterLogin(action.payload!.fragment, api);
  }
  await api.actions.load();
}

Future<void> redirectAfterLogin(String location,
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api) async {
  switch (location) {
    case "":
    case "dashboard/student":
      break;
    case "student/absences":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showAbsences.call,
      );
    case "calendar/student":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCalendar.call,
      );
    case "student/subjects":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showGrades.call,
      );
    case "student/certificate":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCertificate.call,
      );
    case "message/list":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showMessages.call,
      );
    default:
      showSnackBar("Dieser Link konnte nicht geöffnet werden");
  }
}

bool _popAll() {
  var poppedAnything = false;
  navigatorKey?.currentState?.popUntil((route) {
    if (!route.isFirst) {
      poppedAnything = true;
    }
    return route.isFirst;
  });
  nestedNavKey.currentState?.popUntil((route) {
    if (!route.isFirst) {
      poppedAnything = true;
    }
    return route.isFirst;
  });
  return poppedAnything;
}

Future<String>? _attachmentDownloadDirectoryFuture;

Future<String> _getAttachmentDownloadDirectory() {
  final cached = _attachmentDownloadDirectoryFuture;
  if (cached != null) {
    return cached;
  }

  // TODO: this remains to be tested on all platforms
  final future = () async {
    try {
      return (await getExternalStorageDirectories(
              type: StorageDirectory.downloads))!
          .first
          .path;
    } catch (_) {
      log(
        "failed to get download directory, falling back to application storage",
      );
      return (await getApplicationDocumentsDirectory()).path;
    }
  }();
  _attachmentDownloadDirectoryFuture = future;
  return future;
}

/// Downloads a file.
///
/// Returns true on success and false on a failure.
Future<bool> downloadFile(
  String url,
  String fileName,
  Map<String, dynamic> parameters,
) async {
  await wrapper.ensureLoggedIn();

  final saveFile = File(
    "${await _getAttachmentDownloadDirectory()}/$fileName",
  );
  var success = true;
  if (await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(fileName);
    if (shouldOverwrite == null) {
      return false;
    } else if (!shouldOverwrite) {
      return true;
    }
  }
  try {
    final result = await wrapper.dio.get<dynamic>(
      url,
      queryParameters: parameters,
      options: dio.Options(responseType: dio.ResponseType.stream),
    );
    await saveFile.parent.create(recursive: true);
    final sink = saveFile.openWrite();
    await sink.addStream((result.data as dio.ResponseBody).stream);
    await sink.flush();
    await sink.close();
    success = result.statusCode == 200;
  } catch (e) {
    log("failed to download file $url: $e");
    success = false;
  }

  if (!success && await saveFile.exists()) {
    // The download was not successful, we should not keep the empty file or whatever was downloaded.
    await saveFile.delete();
  }

  return success;
}

Future<Uint8List> fetchAuthenticatedBytes(String url) async {
  await wrapper.ensureLoggedIn();
  final response = await wrapper.dio.get<List<int>>(
    url,
    options: dio.Options(responseType: dio.ResponseType.bytes),
  );
  return Uint8List.fromList(response.data ?? const <int>[]);
}

Future<bool> canOpenFile(String fileName) async {
  return File(
    "${await _getAttachmentDownloadDirectory()}/$fileName",
  ).exists();
}

Future<void> openFile(String fileName) async {
  log("opening file: $fileName");
  await OpenFile.open(
    "${await _getAttachmentDownloadDirectory()}/$fileName",
  );
}

Future<bool?> askShouldOverwriteFile(String fileName) {
  return navigatorKey!.currentState!.push<bool>(
    DialogRoute(
      builder: (context) {
        return InfoDialog(
          title: const Text("Datei existiert bereits"),
          content: Text(
            "Die Datei \"$fileName\" ist bereits im Downloads-Ordner vorhanden.\n\n"
            "Wenn die Datei erneut heruntergeladen wird, wird die bestehende Datei ersetzt.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Bestehende Datei verwenden"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Erneut herunterladen"),
            ),
          ],
        );
      },
      context: navigatorKey!.currentContext!,
    ),
  );
}

Future<void> _checkShowUnmaintainedAlert() async {
  final appDirectory = await getApplicationSupportDirectory();
  final file = File("${appDirectory.path}/unmaintainedAlertShown");
  if (await file.exists()) {
    return;
  }

  // A version of this app stored this file to the applications documents directory,
  // which is Documents/ for desktop. The directory was therefore fixed, but we should
  // still check for the file in the old location.
  final legacyFile = File(
      "${(await getApplicationDocumentsDirectory()).path}/unmaintainedAlertShown");
  if (await legacyFile.exists()) {
    // create the file in the correct location
    await file.create(recursive: true);
    return;
  }

  await showDialog<void>(
    context: navigatorKey!.currentContext!,
    builder: (context) {
      return InfoDialog(
        title: const Text("Willkommen!"),
        content: Text.rich(
          TextSpan(
            text:
                "Diese App ist ein Fork des Originals. In der App findest du sowohl das Original-Projekt als auch diesen Fork verlinkt.\n\n"
                "Das Original stammt von miDeb: ",
            children: [
              TextSpan(
                text: "github.com/mideb/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse(
                          "https://github.com/Tobias-Bucci/digitales_register"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              const TextSpan(
                text: "\n\nMein Fork ist hier zu finden: ",
              ),
              TextSpan(
                text: "github.com/Tobias-Bucci/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse(
                          "https://github.com/Tobias-Bucci/digitales_register"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              const TextSpan(
                text: "\n\nJede und jeder darf daran mitarbeiten.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      );
    },
  );

  await file.create(recursive: true);
}
