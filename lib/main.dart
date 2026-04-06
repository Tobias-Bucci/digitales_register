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

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
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
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/notification_background_service.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:uni_links/uni_links.dart';

GlobalKey<NavigatorState>? navigatorKey;
GlobalKey<NavigatorState> nestedNavKey = GlobalKey();
GlobalKey<ResponsiveScaffoldState<Pages>>? scaffoldKey;
GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

typedef SingleArgumentVoidCallback<T> = void Function(T arg);

// Actions are now global (although this doesn't seem to be the case in the official example).
// This way it is easier for ui code to dispatch actions.
// TODO: This is actually a bad idea for testing. It should be removed again.
final AppActions actions = AppActions();

Future<void> main() async {
  final startupStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  navigatorKey = GlobalKey();
  scaffoldKey = GlobalKey();
  scaffoldMessengerKey = GlobalKey();
  secureStorage = getFlutterSecureStorage();
  await appLanguageController.load(
    fallbackLocale: WidgetsBinding.instance.platformDispatcher.locale,
  );
  await appSubjectTranslationController.load();
  final store = Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    AppState(
      (b) => b.settingsState.languageCode = appLanguageController.language.code,
    ),
    actions,
    middleware: middleware(),
  );
  runApp(RegisterApp(store: store));
  unawaited(_loadThemeController());
  unawaited(_loadPackageInfo());
  unawaited(_initializeNotificationBackgroundService());
  WidgetsBinding.instance.addPostFrameCallback(
    (_) async {
      logPerformanceEvent(
        "app_first_frame",
        <String, Object?>{
          "elapsedMs": startupStopwatch.elapsedMilliseconds,
        },
      );
      Uri? uri;
      if (Platform.isAndroid) {
        uri = await getInitialUri();
        uriLinkStream.listen((event) {
          store.actions.start(event);
        });
      }
      unawaited(store.actions.start(uri));
      WidgetsBinding.instance.addObserver(
        LifecycleObserver(
          store.actions.restarted.call,
          // this might not finish in time:
          store.actions.saveState.call,
        ),
      );
    },
  );
}

Future<void> _loadThemeController() async {
  final stopwatch = Stopwatch()..start();
  await themeController.load();
  stopwatch.stop();
  logPerformanceEvent(
    "theme_loaded",
    <String, Object?>{
      "elapsedMs": stopwatch.elapsedMilliseconds,
    },
  );
}

Future<void> _loadPackageInfo() async {
  try {
    setPackageInfo(await PackageInfo.fromPlatform());
  } catch (_) {
    // Keep the default placeholder values when platform package info is unavailable.
  }
}

Future<void> _initializeNotificationBackgroundService() async {
  final stopwatch = Stopwatch()..start();
  await NotificationBackgroundService.initialize();
  stopwatch.stop();
  logPerformanceEvent(
    "notification_service_initialized",
    <String, Object?>{
      "elapsedMs": stopwatch.elapsedMilliseconds,
    },
  );
}

Future<void> setGlobalContrastColor(Color color) async {
  await themeController.setContrastColor(color);
}

class RegisterApp extends StatelessWidget {
  const RegisterApp({
    super.key,
    required this.store,
  });

  final Store<AppState, AppStateBuilder, AppActions> store;

  @override
  Widget build(BuildContext context) {
    return ReduxProvider(
      store: store,
      child: Listener(
        onPointerDown: (_) => store.actions.loginActions.updateLogout(),
        child: StoreConnection<AppState, AppActions, _RegisterAppViewModel>(
          connect: (state) => _RegisterAppViewModel(
            amoledMode: state.settingsState.amoledMode,
            biometricAppLockEnabled:
                state.settingsState.biometricAppLockEnabled,
            locale: AppLanguage.fromCode(state.settingsState.languageCode)
                .locale,
          ),
          builder: (context, vm, actions) => AnimatedBuilder(
            animation: themeController,
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
                  final sameCountry = supported.countryCode == locale.countryCode;
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
              scaffoldMessengerKey: scaffoldMessengerKey,
              initialRoute: "/",
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
                      builder: (_) => LoginPage(),
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
                      builder: (_) => NotificationPageContainer(),
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
                      builder: (_) => SettingsPageContainer(),
                      fullscreenDialog: true,
                    );
                  default:
                    throw Exception("Unknown Route ${pathElements[1]}");
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
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              debugShowCheckedModeBanner: false,
            ),
          ),
        ),
      ),
    );
  }
}

class LifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onForeground;
  final VoidCallback onBackground;

  LifecycleObserver(this.onForeground, this.onBackground);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumed());
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      biometricAppLockController.lock();
      unawaited(NotificationBackgroundService.handleAppPaused());
      onBackground();
    }
  }

  Future<void> _handleResumed() async {
    await NotificationBackgroundService.handleAppResumed();
    await biometricAppLockController.authenticateIfNeeded();
    onForeground();
  }
}

class _RegisterAppViewModel {
  const _RegisterAppViewModel({
    required this.amoledMode,
    required this.biometricAppLockEnabled,
    required this.locale,
  });

  final bool amoledMode;
  final bool biometricAppLockEnabled;
  final Locale locale;
}

/// Utility to show a global Snack Bar
void showSnackBar(String message) {
  scaffoldMessengerKey!.currentState!.showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
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
