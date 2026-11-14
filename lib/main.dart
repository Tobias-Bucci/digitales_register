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

// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/android_widget_service.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/app_state.dart';
import 'package:dr/app_subject_translation_controller.dart';
import 'package:dr/biometric_app_lock.dart';
import 'package:dr/container/change_email_container.dart';
import 'package:dr/container/home_page.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/container/notifications_page_container.dart';
import 'package:dr/container/pass_reset_container.dart';
import 'package:dr/container/profile_container.dart';
import 'package:dr/container/request_pass_reset_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/desktop.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/host_platform.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/notification_feed.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/reminder_notifications.dart';
import 'package:dr/reminder_sync.dart';
import 'package:dr/runtime_trace.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/school_proxy.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/startup_timeline.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:dr/ui/launch/app_launch_animation.dart';
import 'package:dr/ui/server_notifications/server_notification_bell.dart';
import 'package:dr/ui/server_notifications/server_notification_popup.dart';
import 'package:dr/ui/system_pages.dart';
import 'package:dr/util.dart';
import 'package:dr/web_app/web_routing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_links/uni_links.dart';

GlobalKey<NavigatorState>? navigatorKey;
GlobalKey<NavigatorState> nestedNavKey = GlobalKey();
GlobalKey<ResponsiveScaffoldState<Pages>>? scaffoldKey;
GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
StreamSubscription<Uri?>? _uriLinkSubscription;
SettingsState _startupSettingsState = SettingsState();

typedef SingleArgumentVoidCallback<T> = void Function(T arg);

// Actions are now global (although this doesn't seem to be the case in the official example).
// This way it is easier for ui code to dispatch actions.
// TODO: This is actually a bad idea for testing. It should be removed again.
final AppActions actions = AppActions();

Future<void> main() async {
  startupTimeline.start();
  final startupStopwatch = Stopwatch()..start();
  if (kIsWeb) {
    // Readable addresses (/grades) instead of /#/grades. Before the binding
    // reads the initial route.
    usePathUrlStrategy();
    WebUrlSync.instance.start();
  }
  WidgetsFlutterBinding.ensureInitialized();
  startupTimeline.mark('p1_binding_ready');

  navigatorKey = GlobalKey();
  scaffoldKey = GlobalKey();
  scaffoldMessengerKey = GlobalKey();
  secureStorage = getFlutterSecureStorage();
  await startupTimeline.step(
      'p1_privacy_analytics', () => AnalyticsService.initLich());
  await startupTimeline.step('p1_app_clock', appClock.initialize);
  await _loadStartupUserPreferences();
  await startupTimeline.step('p1_legacy_cleanup', removeLegacyNotificationData);
  final store = Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    AppState((b) => b.settingsState.replace(_startupSettingsState)),
    actions,
    middleware: middleware(),
  );
  startupTimeline.mark('p1_store_created');
  AnalyticsService.refreshContext = () async {
    await refreshProductAnalyticsContext(store.state);
    await submitAcademicSummary(store.state);
  };
  await startupTimeline.step(
    'p1_widget_launch_handler',
    () => AndroidWidgetPlatformBridge().registerLaunchHandler(
      (destination) => handleAndroidWidgetLaunchDestination(
        store.actions,
        destination,
        deferUntilLogin: !store.state.loginState.loggedIn,
      ),
    ),
  );
  startupTimeline
    ..mark('p2_run_app')
    ..watchFrames();
  runApp(RegisterApp(store: store, launchTargetReady: _launchTargetReady()));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(
      startupTimeline
          .step(
        'p6_after_first_frame_init',
        () => _initializeAfterFirstFrame(
          store: store,
          startupStopwatch: startupStopwatch,
        ),
      )
          .whenComplete(() {
        appLaunchGate.open();
        serverNotifications.isLoggedIn = () => store.state.loginState.loggedIn;
        // Bugs only, as a category and a sanitized stack, and only with the
        // diagnostics consent. Network failures never get this far.
        serverNotifications.onUnexpectedError = (error, stack) =>
            diagnostics.report(error, stack, DiagnosticError.notification);
        unawaited(serverNotifications.start());
      }),
    ),
  );
}

/// Completes when the launch animation may uncover the start-up route.
Future<void> _launchTargetReady() async {
  await appLaunchGate.opened;
  // `--dart-define=DR_LAUNCH_EXTRA_WAIT_MS=3000` simulates a slow sign-in.
  final extraWaitMs =
      int.tryParse(const String.fromEnvironment('DR_LAUNCH_EXTRA_WAIT_MS'));
  if (extraWaitMs != null && extraWaitMs > 0) {
    await Future<void>.delayed(Duration(milliseconds: extraWaitMs));
  }
  // The reveal must not uncover the login page halfway through its push.
  await waitForRouteTransition(() => navigatorKey?.currentState);
  startupTimeline.mark('p3_launch_target_ready');
}

DateTime? _proxyNoticeShown;

/// Web: the proxy to the school servers is out of today's free quota.
void _showSchoolProxyUnavailable() {
  final now = DateTime.now();
  final last = _proxyNoticeShown;
  if (last != null && now.difference(last) < const Duration(minutes: 1)) {
    return;
  }
  final context = navigatorKey?.currentContext;
  final messenger = scaffoldMessengerKey?.currentState;
  if (context == null || messenger == null) return;
  _proxyNoticeShown = now;
  messenger.showSnackBar(SnackBar(
    content: Text(context.l10n.text('error.webProxyUnavailable')),
    duration: const Duration(seconds: 8),
  ));
}

/// Removes what older versions stored for background notification polling.
@visibleForTesting
Future<void> removeLegacyNotificationData() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in const [
    'pushNotificationsEnabled',
    'backgroundNotificationReminderEntries',
    'backgroundNotificationLogs',
    'backgroundNotificationPollLease',
    'backgroundNotificationPollLastCompleted',
  ]) {
    // Usually long gone: skip the platform round trip before the first frame.
    if (prefs.containsKey(key)) await prefs.remove(key);
  }
}

Future<void> _initializeAfterFirstFrame({
  required Store<AppState, AppStateBuilder, AppActions> store,
  required Stopwatch startupStopwatch,
}) async {
  // On Windows the first post-frame callback can run before MaterialApp has
  // finished creating its Navigator (for example while localizations load).
  // Startup routing must wait for it, otherwise showLogin has nowhere to push
  // its route and the splash screen remains visible indefinitely.
  for (var attempt = 0; navigatorKey?.currentState == null; attempt++) {
    if (attempt == 120) {
      throw StateError('Navigator was not mounted during app startup.');
    }
    await WidgetsBinding.instance.endOfFrame;
  }
  startupTimeline.mark('p2_first_frame');

  unawaited(AnalyticsService.initLich());
  unawaited(startupTimeline.step('p6_package_info', _loadPackageInfo));
  unawaited(startupTimeline.step(
      'p6_restore_preferences', () => _restoreUserPreferences(store)));

  await AnalyticsService.logCustomEvent("app_first_frame", <String, Object>{
    "elapsedMs": startupStopwatch.elapsedMilliseconds,
  });

  onSchoolProxyUnavailable = _showSchoolProxyUnavailable;

  Uri? uri;
  if (HostPlatform.isAndroid) {
    uri = await getInitialUri();
    await _uriLinkSubscription?.cancel();
    _uriLinkSubscription = uriLinkStream.listen((event) async {
      await store.actions.start(event);
    });
  }

  schoolNotifications.refresh = () async {
    if (store.state.loginState.loggedIn && !store.state.noInternet) {
      await refreshSchoolNotificationFeed(store.actions);
    }
  };
  var handlingSchoolNotificationTap = false;
  schoolNotifications.onTap = () async {
    final destination = schoolNotifications.pendingDestination;
    if (destination == null ||
        !store.state.loginState.loggedIn ||
        scaffoldKey?.currentState == null ||
        handlingSchoolNotificationTap) {
      return;
    }
    handlingSchoolNotificationTap = true;
    try {
      var user = store.state.loginState.username;
      var server = store.state.url;
      if (user == null || server == null) return;
      if (destination.account != schoolNotifications.accountKey(server, user)) {
        final owner = (server, user);
        final index = await schoolNotifications.savedAccountIndex(
            destination.account,
            loggedIn: store.state.loginState.loggedIn,
            noPasswordSaving: store.state.settingsState.noPasswordSaving);
        // A manual account change supersedes the tap while storage was read.
        if ((store.state.url, store.state.loginState.username) != owner) return;
        if (index == null) {
          schoolNotifications.pendingDestination = null;
          final context = scaffoldKey?.currentContext;
          if (context != null && context.mounted) {
            showSnackBar(context.l10n
                .text('schoolNotifications.settings.accountUnavailable'));
          }
          return;
        }
        schoolNotifications.preserveDestinationForNextAccountSwitch();
        await store.actions.loginActions.selectAccount(index);
        // A second manual switch clears the destination and supersedes this tap.
        if (!identical(schoolNotifications.pendingDestination, destination)) {
          return;
        }
        user = store.state.loginState.username;
        server = store.state.url;
        if (!store.state.loginState.loggedIn ||
            user == null ||
            server == null ||
            destination.account !=
                schoolNotifications.accountKey(server, user)) {
          return;
        }
      }
      schoolNotifications.pendingDestination = null;
      navigatorKey?.currentState?.popUntil((route) => route.isFirst);
      if (destination.category == SchoolNotificationCategory.grade) {
        await store.actions.routingActions.showGrades();
      } else if (destination.objectId != null) {
        await store.actions.routingActions.showMessage(destination.objectId!);
      } else {
        await store.actions.routingActions.showMessages();
      }
    } finally {
      handlingSchoolNotificationTap = false;
    }
  };
  // Reads the state at the time of the tap: a link changed after a reminder was
  // scheduled counts, and the settings are there before the sign-in.
  reminderNotifications.onTap = (payload) => openReminderTarget(
        payload,
        mensaUrl: store.state.settingsState.mensaReminderUrl,
        openDashboard: () {
          // Before the sign-in the app is on its way to the dashboard anyway,
          // and the login page must stay.
          if (store.state.loginState.loggedIn) showDashboardHome();
        },
        linkFailed: () => showSnackBar(tr('navigation.linkOpenFailed')),
      );
  reminderNotifications.prepare();
  // Notification storage/OS scheduling is optional and can be busy in another
  // Flutter engine. It must not hold the splash screen or automatic login.
  unawaited(schoolNotificationOperation(() async {
    await startupTimeline.step(
        'p6_notifications_init', schoolNotifications.initialize);
    await schoolNotifications.onTap?.call();
  }));
  final loginTimer = Stopwatch()..start();
  runtimeTrace('AppStartup', 'login-start',
      detail: 'startupMs=${startupStopwatch.elapsedMilliseconds}');
  reminderSync.attach(store.nextState, store.state);
  await startupTimeline.step(
      'p3_p4_start_action', () => store.actions.start(uri));
  runtimeTrace('AppStartup', 'login-end',
      durationMs: loginTimer.elapsedMilliseconds);
  _showKeyringFallbackNotice();

  WidgetsBinding.instance.addObserver(
    LifecycleObserver(
      store.actions.restarted.call,
      // this might not finish in time:
      store.actions.saveState.call,
    ),
  );
}

/// Tells the user once when Linux had no keyring for the login data.
void _showKeyringFallbackNotice() {
  void show() {
    if (!DesktopSecureStorage.keyringFallbackNotice.value) return;
    DesktopSecureStorage.keyringFallbackNotice.value = false;
    showSnackBar(tr('desktop.keyringUnavailable'));
  }

  DesktopSecureStorage.keyringFallbackNotice.addListener(show);
  show();
}

Future<void> _restoreUserPreferences(
  Store<AppState, AppStateBuilder, AppActions> store,
) async {
  await store.actions.settingsActions.setLanguage(
    appLanguageController.language.code,
  );
  await appSubjectTranslationController.load();
}

Future<void> _loadStartupUserPreferences() async {
  await startupTimeline.step(
    'p1_language',
    () => appLanguageController.load(
      fallbackLocale: WidgetsBinding.instance.platformDispatcher.locale,
    ),
  );
  _startupSettingsState = await startupTimeline.step(
          'p1_settings', settingsPersistenceService.load) ??
      SettingsState(
        (b) => b.languageCode = appLanguageController.language.code,
      );
  await startupTimeline.step(
    'p1_language_apply',
    () => appLanguageController.setLanguage(
      AppLanguage.fromCode(_startupSettingsState.languageCode),
    ),
  );
  final stopwatch = Stopwatch()..start();
  await startupTimeline.step('p1_theme', themeController.load);
  stopwatch.stop();
  await AnalyticsService.logCustomEvent("theme_loaded", <String, Object>{
    "elapsedMs": stopwatch.elapsedMilliseconds,
  });
}

Future<void> _loadPackageInfo() async {
  try {
    setPackageInfo(await PackageInfo.fromPlatform());
  } catch (_) {
    // Keep the default placeholder values when platform package info is unavailable.
  }
}

class RegisterApp extends StatelessWidget {
  const RegisterApp({super.key, required this.store, this.launchTargetReady});

  final Store<AppState, AppStateBuilder, AppActions> store;

  /// Plays the launch animation until this completes; null skips it.
  final Future<void>? launchTargetReady;

  @override
  Widget build(BuildContext context) {
    return ReduxProvider(
      store: store,
      child: Listener(
        onPointerDown: (_) => store.actions.loginActions.updateLogout(),
        child: _withLaunchAnimation(
            StoreConnection<AppState, AppActions, _RegisterAppViewModel>(
          connect: (state) => _RegisterAppViewModel(
            amoledMode: state.settingsState.amoledMode,
            legacyDesign: state.settingsState.legacyDesign,
            biometricAppLockEnabled:
                state.settingsState.biometricAppLockEnabled,
            locale: AppLanguage.fromCode(
              state.settingsState.languageCode,
            ).locale,
          ),
          builder: (context, vm, actions) => AnimatedBuilder(
            animation: Listenable.merge([themeController, appClock]),
            builder: (context, _) => MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              locale: vm.locale,
              localeResolutionCallback: (locale, supportedLocales) {
                if (locale == null) {
                  return supportedLocales.first;
                }
                for (final supported in supportedLocales) {
                  final sameLanguage =
                      supported.languageCode == locale.languageCode;
                  final sameCountry =
                      supported.countryCode == locale.countryCode;
                  if (sameLanguage && sameCountry) {
                    return supported;
                  }
                }
                for (final supported in supportedLocales) {
                  if (supported.languageCode == locale.languageCode) {
                    return supported;
                  }
                }
                return supportedLocales.first;
              },
              navigatorKey: navigatorKey,
              // The browser tab's title; native builds keep their app name.
              title: kIsWeb ? 'Digitales Register' : '',
              navigatorObservers: [
                DiagnosticsNavigatorObserver(
                    onScreen: (screen) =>
                        unawaited(AnalyticsService.logScreenView(screen))),
                if (kIsWeb) WebUrlSync.instance,
              ],
              scaffoldMessengerKey: scaffoldMessengerKey,
              initialRoute: "/",
              // The browser's address would otherwise become the initial
              // route stack ('/' and '/grades', past the login). The web app
              // starts at home like the native app and opens the address's
              // page after signing in (WebUrlSync).
              onGenerateInitialRoutes: kIsWeb
                  ? (_) => [
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(name: '/'),
                          builder: (_) => HomePage(),
                        ),
                      ]
                  : null,
              onGenerateRoute: (RouteSettings settings) {
                final List<String> pathElements = settings.name!.split("/");
                if (pathElements[0] != "") return null;
                switch (pathElements[1]) {
                  case "":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => HomePage(),
                    );
                  case "login":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) =>
                          ServerNotificationCornerBell(child: LoginPage()),
                    );
                  case "request_pass_reset":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => RequestPassResetContainer(),
                    );
                  case "pass_reset":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => PassResetContainer(),
                    );
                  case "change_email":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => ChangeEmailContainer(),
                    );
                  case "profile":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => ProfileContainer(),
                    );
                  case "notifications":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => NotificationPageContainer(
                        focusSchoolId: takeNotificationCenterFocus(),
                      ),
                      fullscreenDialog: true,
                    );
                  case "gradesChart":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const GradesChartPage(),
                      fullscreenDialog: true,
                    );
                  case "gradeCalculator":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const GradeCalculator(),
                      fullscreenDialog: true,
                    );
                  case "settings":
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const SettingsPageContainer(),
                      fullscreenDialog: true,
                    );
                  default:
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) =>
                          UnknownRoutePage(routeName: settings.name ?? ''),
                    );
                }
              },
              themeMode: themeController.themeMode,
              theme: themeController.buildTheme(
                brightness: Brightness.light,
                amoledMode: false,
              ),
              darkTheme: themeController.buildTheme(
                brightness: Brightness.dark,
                amoledMode: vm.amoledMode,
              ),
              builder: (context, child) => AppLockSync(
                enabled: vm.biometricAppLockEnabled,
                child: BiometricAppLockOverlay(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: SafeArea(
                      top: false,
                      child: ServerNotificationHost(
                        newDesign: !vm.legacyDesign,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
              debugShowCheckedModeBanner: false,
            ),
          ),
        )),
      ),
    );
  }

  /// The overlay sits above MaterialApp so the very first frame already shows
  /// the logo, even while the localizations are still loading.
  Widget _withLaunchAnimation(Widget app) {
    final ready = launchTargetReady;
    if (ready == null) return app;
    return AppLaunchAnimation(
      targetReady: ready,
      onFinished: () => startupTimeline
        ..mark('p3_launch_overlay_removed')
        ..stopFrames(),
      child: app,
    );
  }
}

class LifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onForeground;
  final VoidCallback onBackground;
  Future<void>? _resumeInFlight;
  bool _foreground = false;

  LifecycleObserver(this.onForeground, this.onBackground);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    diagnostics.update(
        'app_state',
        state == AppLifecycleState.resumed
            ? 'foreground'
            : state == AppLifecycleState.paused
                ? 'background'
                : state.name);
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // On every resume, also while an earlier one still runs: its prompt may
      // have hidden the app in between, which paused all requests. Left paused,
      // every request of this session would fail until a restart. It also
      // resumes them when the user later retries the prompt using the overlay
      // button, which does not emit a new lifecycle event.
      resumeNetworkRequests();
      _resumeInFlight ??=
          _handleResumed().whenComplete(() => _resumeInFlight = null);
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      biometricAppLockController.lock();
      pauseNetworkRequests();
      onBackground();
    }
  }

  Future<void> _handleResumed() async {
    final timer = Stopwatch()..start();
    runtimeTrace('AppStartup', 'resume-auth-start');
    final authenticated =
        await biometricAppLockController.authenticateIfNeeded();
    runtimeTrace('AppStartup', 'resume-auth-end',
        durationMs: timer.elapsedMilliseconds,
        detail: 'authenticated=$authenticated');
    if (!authenticated || !_foreground) return;
    await AnalyticsService.logCustomEvent("app_opened");
    onForeground();
    runtimeTrace('AppStartup', 'resume-refresh-dispatched',
        durationMs: timer.elapsedMilliseconds);
  }
}

class _RegisterAppViewModel {
  const _RegisterAppViewModel({
    required this.amoledMode,
    required this.legacyDesign,
    required this.biometricAppLockEnabled,
    required this.locale,
  });

  final bool amoledMode;
  final bool legacyDesign;
  final bool biometricAppLockEnabled;
  final Locale locale;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _RegisterAppViewModel &&
            other.amoledMode == amoledMode &&
            other.legacyDesign == legacyDesign &&
            other.biometricAppLockEnabled == biometricAppLockEnabled &&
            other.locale == locale;
  }

  @override
  int get hashCode =>
      Object.hash(amoledMode, legacyDesign, biometricAppLockEnabled, locale);
}

String tr(String key, {Map<String, String> args = const {}}) {
  final context = navigatorKey?.currentContext;
  if (context == null) {
    return key;
  }
  return AppLocalizations.of(context).text(key, args: args);
}

/// Utility to show a global Snack Bar, with a button if [onAction] is given.
void showSnackBar(
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messengerState = scaffoldMessengerKey?.currentState;
  if (messengerState == null) {
    return;
  }
  messengerState.showSnackBar(SnackBar(
    content: Text(message),
    action: actionLabel == null || onAction == null
        ? null
        : SnackBarAction(label: actionLabel, onPressed: onAction),
  ));
}

/*
ThemeData _getDarkTheme(MaterialColor primarySwatch) {
  final colorScheme = ColorScheme(
    primary: primarySwatch,
    primaryVariant: primarySwatch[700],
    secondary: primarySwatch,
    secondaryVariant: primarySwatch[700],
    surface: Colors.grey[800],
    background: Colors.grey[700],
    error: Colors.red[700],
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Colors.white,
    onBackground: Colors.white,
    onError: Colors.black,
    brightness: Brightness.dark,
  );
  return ThemeData(
    brightness: Brightness.dark,
    primarySwatch: primarySwatch,
    primaryColor: primarySwatch,
    primaryColorLight: primarySwatch[100],
    primaryColorDark: primarySwatch[700],
    toggleableActiveColor: primarySwatch[600],
    accentColor: primarySwatch[500],
    secondaryHeaderColor: primarySwatch[200],
    backgroundColor: primarySwatch[200],
    indicatorColor: primarySwatch[500],
    buttonColor: primarySwatch[600],
    colorScheme: colorScheme,
  );
}
*/
