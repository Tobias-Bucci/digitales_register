import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/notification_background_service.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestSecureStorage implements FlutterSecureStorage {
  TestSecureStorage({Map<String, String>? storage})
      : storage = Map<String, String>.from(storage ?? const <String, String>{});

  final Map<String, String> storage;

  @override
  Future<bool> containsKey({
    String? key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    return storage.containsKey(key);
  }

  @override
  Future<void> delete({
    String? key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    storage.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    storage.clear();
  }

  @override
  Future<String?> read({
    String? key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    return storage[key];
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    return Map<String, String>.from(storage);
  }

  @override
  Future<void> write({
    String? key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (key == null || value == null) {
      return;
    }
    storage[key] = value;
  }

  @override
  AndroidOptions get aOptions => throw UnimplementedError();

  @override
  IOSOptions get iOptions => throw UnimplementedError();

  @override
  LinuxOptions get lOptions => throw UnimplementedError();

  @override
  MacOsOptions get mOptions => throw UnimplementedError();

  @override
  WindowsOptions get wOptions => throw UnimplementedError();

  @override
  WebOptions get webOptions => throw UnimplementedError();
}

class MockWrapper extends Mock implements Wrapper {}

class MockDio extends Mock implements Dio {}

const String testServerUrl = 'https://example.digitales.register.example';
const String testLoginAddress = '$testServerUrl/v2/api/login';
const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

Directory? _testAppDirectory;
bool _pathProviderMockInstalled = false;

Future<void> bootstrapTestEnvironment({
  Map<String, String>? storage,
  Wrapper? wrapperOverride,
  UtcDateTime? fixedNow,
  Map<String, Object> sharedPreferences = const <String, Object>{},
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(sharedPreferences);
  secureStorage = TestSecureStorage(storage: storage);
  wrapper = wrapperOverride ?? Wrapper();
  passDio = null;
  deletedData = false;
  statePersistenceService.clear();
  navigatorKey = GlobalKey<NavigatorState>();
  nestedNavKey = GlobalKey<NavigatorState>();
  scaffoldKey = GlobalKey<ResponsiveScaffoldState<Pages>>();
  scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  mockNow = fixedNow;
  await NotificationBackgroundService.resetForTest();
  await _ensurePathProviderMocks();
}

Future<void> _ensurePathProviderMocks() async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (_testAppDirectory == null) {
    _testAppDirectory = Directory.systemTemp.createTempSync('dr_test_support');
    final marker = File(
      '${_testAppDirectory!.path}${Platform.pathSeparator}unmaintainedAlertShown',
    );
    if (!marker.existsSync()) {
      marker.createSync(recursive: true);
    }
  }
  if (_pathProviderMockInstalled) {
    return;
  }
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _pathProviderChannel,
    (call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
        case 'getApplicationDocumentsDirectory':
        case 'getTemporaryDirectory':
          return _testAppDirectory!.path;
      }
      return null;
    },
  );
  _pathProviderMockInstalled = true;
}

Future<void> resetTestState() async {
  mockNow = null;
  deletedData = false;
  statePersistenceService.clear();
  passDio = null;
  resetNoInternetRetryForTest();
  await NotificationBackgroundService.resetForTest();
}

Store<AppState, AppStateBuilder, AppActions> createStore({
  AppState? initialState,
  AppActions? appActions,
  bool withMiddleware = false,
}) {
  return Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    initialState ?? AppState(),
    appActions ?? actions,
    middleware: withMiddleware
        ? middleware(includeErrorMiddleware: false)
        : const <Middleware<AppState, AppStateBuilder, AppActions>>[],
  );
}

Widget buildTestApp({
  required Store<AppState, AppStateBuilder, AppActions> store,
  required Widget home,
  ThemeData? theme,
  ThemeData? darkTheme,
  ThemeMode themeMode = ThemeMode.light,
  RouteFactory? onGenerateRoute,
  GlobalKey<NavigatorState>? appNavigatorKey,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) {
  return ReduxProvider(
    store: store,
    child: MaterialApp(
      navigatorKey: appNavigatorKey ?? navigatorKey,
      scaffoldMessengerKey: messengerKey ?? scaffoldMessengerKey,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('de')],
      onGenerateRoute: onGenerateRoute,
      themeMode: themeMode,
      theme: theme ?? ThemeData(colorSchemeSeed: defaultContrastColor),
      darkTheme: darkTheme ??
          ThemeData(
            colorSchemeSeed: defaultContrastColor,
            brightness: Brightness.dark,
          ),
      home: home,
    ),
  );
}

Future<void> pumpApp(
  WidgetTester tester, {
  required Store<AppState, AppStateBuilder, AppActions> store,
  required Widget home,
  ThemeData? theme,
  ThemeData? darkTheme,
  ThemeMode themeMode = ThemeMode.light,
  RouteFactory? onGenerateRoute,
}) {
  return tester.pumpWidget(
    buildTestApp(
      store: store,
      home: home,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      onGenerateRoute: onGenerateRoute,
    ),
  );
}

Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 1,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(step);
  }
}

Future<void> settleFor(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 300),
  Duration step = const Duration(milliseconds: 16),
}) async {
  final iterations = duration.inMicroseconds ~/ step.inMicroseconds;
  await pumpFrames(tester, count: iterations, step: step);
}
