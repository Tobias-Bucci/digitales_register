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
import 'dart:io';

import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dr/account_scope.dart';
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
import 'package:dr/analytics_schema.dart';
import 'package:dr/analytics_school_ids.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/android_widget/android_widget_service.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/calendar_load_log.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/change_email_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/container/notifications_page_container.dart';
import 'package:dr/container/profile_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/data.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/external_links.dart';
import 'package:dr/host_platform.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/local_data_inventory.dart';
import 'package:dr/main.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/privacy_log.dart';
import 'package:dr/profile_picture.dart';
import 'package:dr/reminders/reminder_sync.dart';
import 'package:dr/school_api_endpoints.dart';
import 'package:dr/school_config_parser.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/school_proxy.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/startup_timeline.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:dr/stored_login.dart';
import 'package:dr/study_data/study_data_migration.dart';
import 'package:dr/study_data/study_data_service.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/debug_page.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/glass_page.dart' show GlassPanel, glassSheetRoute;
import 'package:dr/ui/glass_surface.dart' show NewDesignTheme;
import 'package:dr/ui/grade_calculator.dart' show GradeCalculator;
import 'package:dr/ui/grades_chart_page.dart' show GradesChartPage;
import 'package:dr/ui/launch/app_launch_animation.dart';
import 'package:dr/ui/privacy_consent_dialog.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart';
import 'package:dr/ui/settings_page_new.dart' show SettingsSheetActions;
import 'package:dr/ui/system_pages.dart';
import 'package:dr/ui/two_factor_dialog.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/web_app/browser_download.dart';
import 'package:dr/web_app/demo_entry.dart';
import 'package:dr/web_app/web_routing.dart';
import 'package:dr/wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Action, Notification;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as image;
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

part 'absences.dart';
part 'analytics.dart';
part 'calendar.dart';
part 'certificate.dart';
part 'course_materials.dart';
part 'dashboard.dart';
part 'downloads.dart';
part 'grades.dart';
part 'local_data.dart';
part 'login.dart';
part 'messages.dart';
part 'notifications.dart';
part 'page_payloads.dart';
part 'pass.dart';
part 'persistence.dart';
part 'profile.dart';
part 'routing.dart';
part 'runtime_cache.dart';
part 'session.dart';
part 'settings.dart';
part 'study_data.dart';

late FlutterSecureStorage secureStorage;
final AppStatePersistenceService statePersistenceService =
    AppStatePersistenceService(onWriteFailed: _warnAboutLocalSave);

/// When the user was last told that this device did not take a change.
DateTime? _lastLocalSaveWarning;

/// Retries go on in the background, which must not repeat the message.
void _warnAboutLocalSave() {
  final now = DateTime.now();
  final last = _lastLocalSaveWarning;
  if (last != null && now.difference(last) < const Duration(minutes: 2)) return;
  _lastLocalSaveWarning = now;
  showSnackBar(tr('error.localSave'));
}

final StudyDataService studyDataService =
    StudyDataService(storage: () => secureStorage);
final StudyDataMigration studyDataMigration = StudyDataMigration(
  service: studyDataService,
  settings: settingsPersistenceService,
);

/// Changes whenever the older learning notes that belong to no account are
/// assigned, discarded or found, so that what shows them can ask again.
final ValueNotifier<int> legacyStudyDataRevision = ValueNotifier<int>(0);
final AndroidWidgetSnapshotService androidWidgetSnapshotService =
    AndroidWidgetSnapshotService();

@visibleForTesting
Duration noInternetRetryInterval = const Duration(seconds: 5);
Timer? _noInternetRetryTimer;
bool _noInternetRetryInFlight = false;

@visibleForTesting
Wrapper wrapper = Wrapper();

/// Installs a fresh [Wrapper] (which also starts without cookies).
///
/// The old instance is retired first: its refresh timer, requests and
/// credentials must not outlive the session the app has left. With
/// [keepMock], tests that injected a mock keep it.
void _replaceWrapper({bool keepMock = false}) {
  // Everything started before this point belongs to a session we left, even
  // when a test keeps its mock wrapper.
  _sessionGeneration++;
  if (keepMock && wrapper is Mock) return;
  wrapper.retire();
  wrapper = Wrapper();
}

bool isOffline() => wrapper.noInternet;

List<Middleware<AppState, AppStateBuilder, AppActions>> middleware({
  @visibleForTesting bool includeErrorMiddleware = true,
}) =>
    [
      if (includeErrorMiddleware) _errorMiddleware,
      _productAnalyticsMiddleware,
      _diagnosticsMiddleware,
      _saveStateMiddleware,
      _staleSessionMiddleware,
      (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
            ..add(LoginActionsNames.updateLogout, _tap)
            ..add(SettingsActionsNames.saveNoData, _saveNoData)
            ..add(AppActionsNames.deleteData, _deleteData)
            ..add(AppActionsNames.assignLegacyStudyData, _assignLegacyStudyData)
            ..add(
                AppActionsNames.discardLegacyStudyData, _discardLegacyStudyData)
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
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) =>
    (ActionHandler next) => (Action action) async {
          Future<void> handleError(dynamic e, StackTrace? trace) async {
            unawaited(AnalyticsService.product.event('error_presented', {
              'feature': 'unknown',
              'error_category': e is ParseException ? 'parsing' : 'unknown'
            }));
            diagnostics.report(
                e as Object, trace ?? StackTrace.empty, DiagnosticError.caught);
            privacyLog('technical_operation');
            await navigatorKey?.currentState?.push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (context) => ErrorPage(
                  messageKey: e is UnexpectedLogoutException
                      ? 'error.session'
                      : e is ParseException
                          ? 'error.parse'
                          : 'error.generic',
                  onContact: () async {
                    await launchUrl(
                      Uri.parse(
                        "https://docs.google.com/forms/d/e/1FAIpQLScTmSAZzj0bjwX_8IHVx9dVTTVrncJJpZo_D20dF7mrnU_zdQ/viewform",
                      ),
                    );
                  },
                ),
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

void _tap(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) {
  wrapper.interaction();
  // do not call next: this action is only to update the logout time
}

Future<void> _refreshNoInternet(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final noInternet = await wrapper.refreshNoInternet();
  await api.actions.noInternet(noInternet);
}

void _cancelNoInternetRetry() {
  _noInternetRetryTimer?.cancel();
  _noInternetRetryTimer = null;
}

void pauseNetworkRequests() {
  wrapper.pauseNetworkActivity();
  _cancelNoInternetRetry();
}

void resumeNetworkRequests() {
  wrapper.resumeNetworkActivity();
  if (wrapper.noInternet) {
    _scheduleNoInternetRetry(actions.refreshNoInternet.call);
  }
}

@visibleForTesting
void resetNoInternetRetryForTest() {
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  noInternetRetryInterval = const Duration(seconds: 5);
}

/// Resets middleware state which is intentionally kept for the app lifetime.
///
/// Tests share an isolate within a test file, so an unfinished coalesced load
/// from one test must never be allowed to affect the next one.
@visibleForTesting
void resetMiddlewareStateForTest() {
  schoolNotificationStartupReady.value = false;
  _unreadableStorageKeys.clear();
  _lastUnreadableRetry = null;
  _retryingUnreadable = false;
  _lastLocalSaveWarning = null;
  localDataPolicy.reset();
  _studyDataScope = null;
  resetNoInternetRetryForTest();
  _clearRuntimeCaches();
  openProfileShellPages.value = 0;
}

void _scheduleNoInternetRetry(Future<void> Function() refreshNoInternet) {
  if (!wrapper.isAppInForeground) return;
  if (_noInternetRetryTimer != null) {
    return;
  }
  _noInternetRetryTimer = Timer(noInternetRetryInterval, () {
    _noInternetRetryTimer = null;
    unawaited(_runNoInternetRetry(refreshNoInternet));
  });
}

Future<void> _runNoInternetRetry(
  Future<void> Function() refreshNoInternet,
) async {
  if (!wrapper.isAppInForeground || _noInternetRetryInFlight) {
    return;
  }
  _noInternetRetryInFlight = true;
  try {
    await refreshNoInternet();
  } finally {
    _noInternetRetryInFlight = false;
    if (wrapper.isAppInForeground && wrapper.noInternet) {
      _scheduleNoInternetRetry(refreshNoInternet);
    }
  }
}

Future<void> _noInternet(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<bool> action,
) async {
  final prevNoInternet = api.state.noInternet;
  await next(action);
  final noInternet = api.state.noInternet;
  if (prevNoInternet != noInternet) {
    if (noInternet) {
      _scheduleNoInternetRetry(api.actions.refreshNoInternet.call);
      showSnackBar(tr('offline.title'));
    } else {
      _cancelNoInternetRetry();
      retryProfilePictures();
      showSnackBar(tr('offline.reconnected'));
      await api.actions.dashboardActions.refresh();
    }
  }
}

Future<void> _load(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await _loadAccounts(api, beforeLoad: () => next(action));
}

Future<void> _loadAccounts(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api, {
  FutureOr<void> Function()? beforeLoad,
  bool explicitSelection = false,
}) async {
  // By resetting the wrapper we clear all cookies.
  // However we don't want to reset the wrapper in tests
  _replaceWrapper(keepMock: true);
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  _clearRuntimeCaches();
  statePersistenceService.clear();
  await androidWidgetSnapshotService.clear();
  wrapper.noInternet = api.state.noInternet;
  await beforeLoad?.call();
  if (!api.state.noInternet) _popAll();
  // Opened at /demo: the demo account instead of any saved login. Its storage
  // is memory only (DemoEntry), so there is nothing saved to read anyway.
  final demoSignIn = DemoEntry.takeSignIn();
  Map<String, dynamic> login = <String, dynamic>{};
  if (!demoSignIn) {
    try {
      final raw = await startupTimeline.step(
          'p3_saved_accounts_read', () => secureStorage.read(key: 'login'));
      login = decodeStoredLogin(raw);
      if (raw != null && json.encode(login) != raw) {
        await secureStorage.write(key: 'login', value: json.encode(login));
      }
    } catch (e, stack) {
      diagnostics.report(e, stack, DiagnosticError.storage);
      // A failed repair must not discard the valid accounts already recovered.
      showSnackBar(tr('error.savedDataLoadFailed'));
    }
  }

  final user = getString(login["user"]);
  final savedForNotificationMigration = [
    login,
    ...(login['otherAccounts'] as List? ?? []).whereType<Map>()
  ];
  unawaited(schoolNotificationOperation(
      () => schoolNotifications.migrateLegacyDecisions([
            for (final saved in savedForNotificationMigration)
              if (saved['url'] is String && saved['user'] is String)
                (saved['url'] as String, saved['user'] as String),
          ])));
  final pass = getString(login["pass"]);
  final url = getString(login["url"]);
  final hasPrimaryAccount = user != null && pass != null && url != null;
  final shouldSignIn =
      explicitSelection || !api.state.settingsState.noPasswordSaving;
  final List<String> otherAccounts = List.from(
    (login["otherAccounts"] as List?)?.map<String>(
          (dynamic login) => login["user"] as String,
        ) ??
        <String>[],
  );
  if (hasPrimaryAccount && !shouldSignIn) {
    otherAccounts.insert(0, user);
  }
  await api.actions.loginActions.setAvailableAccounts(otherAccounts);
  if (demoSignIn) {
    await api.actions.loginActions.login(
      LoginPayload(
        (b) => b
          ..user = 'demo'
          ..pass = 'demo'
          ..url = ''
          ..fromStorage = false,
      ),
    );
  } else if ((api.state.url != null && api.state.url != url) ||
      (api.state.loginState.username != null &&
          api.state.loginState.username != user)) {
    // TODO: Figure out when exactly we'd hit this code path and how to handle it better.
    await api.actions.savePassActions.delete();
    await api.actions.routingActions.showLogin();
  } else {
    if (hasPrimaryAccount && shouldSignIn) {
      await api.actions.loginActions.login(
        LoginPayload(
          (b) => b
            ..user = user
            ..pass = pass
            ..url = url
            ..fromStorage = true,
        ),
      );
    } else {
      await api.actions.routingActions.showLogin();
    }
  }

  // Login or dashboard is decided; the launch animation may uncover it. It
  // covers the app, so it must open before the dialogs below wait for input.
  // A saved login has opened it already, once its saved data was mounted.
  appLaunchGate.open();

  // The first-run dialogs must be pushed after the login or dashboard route is
  // visible. On Windows, pushing them while the opaque splash is still the
  // only route can leave the dialog future pending without a visible dialog.
  if (navigatorKey?.currentState != null) {
    await WidgetsBinding.instance.endOfFrame;
  }
  await _checkShowUnmaintainedAlert();
  await _checkShowPrivacyConsentAlert();
  schoolNotificationStartupReady.value = true;
}

Future<void> _refresh(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  _markRuntimeCacheStale(_notificationsCacheKey);
  final showAbsences =
      api.state.settingsState.dashboardItems.contains('absences');
  if (showAbsences) _markRuntimeCacheStale(_absencesCacheKey);
  await Future.wait([
    api.actions.dashboardActions.load(api.state.dashboardState.future),
    api.actions.notificationsActions.load(),
    if (showAbsences) api.actions.absencesActions.load(),
  ]);
}

/// Puts the saved [state] of the account of [session] into the store.
Future<void> _mountSavedState(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session,
  String state,
) async {
  // Synchronous on the UI isolate, during the launch animation.
  final serializedState = startupTimeline.stepSync(
    'p3_saved_state_decode',
    () => serializers.deserialize(json.decode(state) as Object),
  );
  if (serializedState is SettingsState) {
    final currentSettings = await _settingsForAccountLoad(
      legacySettings: serializedState,
    );
    session.ensureCurrent();
    await api.actions.mountAppState(
      api.state.rebuild(
        (b) => b..settingsState.replace(currentSettings),
      ),
    );
  } else if (serializedState is AppState) {
    final currentState = api.state;
    final currentSettings = await _settingsForAccountLoad(
      legacySettings: serializedState.settingsState,
    );
    session.ensureCurrent();
    await api.actions.mountAppState(
      serializedState.rebuild(
        (b) => b
          ..loginState.replace(currentState.loginState)
          ..url = currentState.url
          ..noInternet = currentState.noInternet
          ..config = currentState.config?.toBuilder()
          ..dashboardState.future = true
          ..gradesState.semester.replace(
                currentState.gradesState.semester == Semester.all
                    ? serializedState.gradesState.semester
                    : currentState.gradesState.semester,
              )
          ..settingsState.replace(currentSettings),
      ),
    );
  }
}

Future<void> _loggedIn(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<LoggedInPayload> action,
) async {
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    statePersistenceService.clear();
  }
  if (!action.payload.fromStorage) {
    await api.actions.savePassActions.save();
  }
  deletedData = false;
  final session = _Session.capture();
  final key = getStorageKey(action.payload.username, wrapper.loginAddress);
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    privacyLog('technical_operation');
    final state = await _readFromStorage(key);
    // The saved state of this account must not be mounted into another one.
    session.ensureCurrent();
    if (state != null) {
      try {
        await _mountSavedState(api, session, state);

        // next not at the beginning: bug fix (serialization)
        await next(action);
      } on StaleSessionException {
        rethrow;
      } catch (e) {
        showSnackBar(tr('error.savedDataLoadFailed'));
        privacyLog('technical_operation');
        await next(action);
      }
    } else {
      await next(action);
    }

    await _mountStudyData(api, session, action.payload.username);
    _popAll();
  } else {
    await next(action);
  }

  // Restoring settings applies the session policy without removing accounts or
  // rewriting their credentials as a side effect of signing in.
  wrapper.safeMode = api.state.settingsState.noPasswordSaving;
  if (!action.payload.offlineOnly &&
      !wrapper.demoMode &&
      wrapper.user != null) {
    unawaited(schoolNotificationOperation(() => schoolNotifications.activate(
          wrapper.url!,
          wrapper.user!,
          backgroundAllowed: !api.state.settingsState.noPasswordSaving,
        )));
  }
  for (final callback in api.state.loginState.callAfterLogin) {
    callback();
  }
  if (!action.payload.offlineOnly) {
    // A saved profile can show an avatar before there is a session to load it.
    retryProfilePictures();
    await startupTimeline.step(
      'p5_first_data',
      () => Future.wait([
        api.actions.dashboardActions.load(api.state.dashboardState.future),
        api.actions.notificationsActions.load(),
        api.actions.profileActions.load(),
      ]),
    );
    // Dashboard loading starts holiday hydration independently in the background.
  }
  await schoolNotificationOperation(() async {
    await schoolNotifications.onTap?.call();
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(schoolNotificationOperation(() async {
      await schoolNotifications.onTap?.call();
    }));
  });
  // Optional account onboarding is offered by the mounted home route after
  // startup notices finish, followed by the tutorial. Neither blocks login.
  // Registering a post-frame callback does not itself request a frame. With
  // idle startup data the offer would otherwise wait for the user's next tap.
  WidgetsBinding.instance.ensureVisualUpdate();
}

Future<SettingsState> _settingsForAccountLoad({
  required SettingsState legacySettings,
}) async {
  final globalSettings = await settingsPersistenceService.load();
  if (globalSettings != null) {
    return globalSettings;
  }
  // The first shared settings are the ones this account has saved so far,
  // learning notes included: they are not lost, and belong to no account yet.
  await settingsPersistenceService.adopt(legacySettings);
  return StudyData.empty.applyTo(legacySettings);
}

Future<void> _restarted(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final source = wrapper;
  final server = source.url;
  final user = source.user;
  unawaited(reminderSync.refresh());
  unawaited(schoolNotificationOperation(() async {
    await schoolNotifications.reload();
    if (api.state.loginState.loggedIn &&
        identical(source, wrapper) &&
        server == wrapper.url &&
        user == wrapper.user) {
      await api.actions.notificationsActions.load();
      await schoolNotifications.schedule();
      await schoolNotifications.onTap?.call();
    }
  }));
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
  // Web: the page of the address the app was opened with (/grades, ...),
  // once signed in, like a link from a widget or a notification.
  final webDestination = WebUrlSync.instance.takePendingDestination();
  final openWebDestination = webDestination == null
      ? null
      : webDestination == 'extras'
          ? api.actions.routingActions.showExtras.call
          : serverNotificationDestinations[webDestination];
  if (openWebDestination != null) {
    await api.actions.loginActions.addAfterLoginCallback(openWebDestination);
  }
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
            parameters["redirect"]!.replaceFirst("#", ""),
            api,
          );
        }
      default:
        showSnackBar(tr('navigation.linkOpenFailed'));
    }
    await redirectAfterLogin(action.payload!.fragment, api);
  }
  final widgetDestination =
      await AndroidWidgetPlatformBridge().consumeLaunchDestination();
  if (widgetDestination != null) {
    await handleAndroidWidgetLaunchDestination(
      api.actions,
      widgetDestination,
      deferUntilLogin: true,
    );
  }
  await api.actions.load();
}

Future<void> redirectAfterLogin(
  String location,
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
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
      showSnackBar(tr('navigation.linkOpenFailed'));
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

const _welcomeShownPreference = 'unmaintainedAlertShown';

Future<void> _checkShowUnmaintainedAlert() async {
  if (kIsWeb) {
    // The browser has no app folder; a preference marks it instead.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_welcomeShownPreference) ?? false) return;
    await _showWelcomeDialog();
    await prefs.setBool(_welcomeShownPreference, true);
    return;
  }
  final appDirectory = await getApplicationSupportDirectory();
  final file = File("${appDirectory.path}/unmaintainedAlertShown");
  if (await file.exists()) {
    return;
  }

  // A version of this app stored this file to the applications documents directory,
  // which is Documents/ for desktop. The directory was therefore fixed, but we should
  // still check for the file in the old location.
  final legacyFile = File(
    "${(await getApplicationDocumentsDirectory()).path}/unmaintainedAlertShown",
  );
  if (await legacyFile.exists()) {
    // create the file in the correct location
    await file.create(recursive: true);
    return;
  }

  await _showWelcomeDialog();
  await file.create(recursive: true);
}

Future<void> _showWelcomeDialog() async {
  await showDialog<void>(
    context: navigatorKey!.currentContext!,
    builder: (context) {
      return InfoDialog(
        title: Text(tr('about.welcome.title')),
        content: Text.rich(
          TextSpan(
            text: tr('about.welcome.bodyPrefix'),
            children: [
              TextSpan(
                text: "github.com/mideb/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse("https://github.com/miDeb/digitales_register"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              TextSpan(text: tr('about.welcome.bodyMiddle')),
              TextSpan(
                text: "github.com/Tobias-Bucci/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse(
                        "https://github.com/Tobias-Bucci/digitales_register",
                      ),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              TextSpan(text: tr('about.welcome.bodySuffix')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('common.done')),
          ),
        ],
      );
    },
  );
}

Future<void> _checkShowPrivacyConsentAlert() async {
  // The web app has no optional purposes (no Firebase), so nothing to ask.
  if (kIsWeb) return;
  final context = navigatorKey?.currentContext;
  if (context == null || !context.mounted) {
    return;
  }

  await showPrivacyConsentDialog(context);
}
