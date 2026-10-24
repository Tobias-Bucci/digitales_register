import 'dart:io';
import 'dart:ui' as ui;

import 'package:dr/app_state.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/ui/school_notification_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

class _SettingsService extends SchoolNotificationService {
  _SettingsService() {
    preferences.enabled = true;
  }
  @override
  bool get supported => true;
  @override
  bool get mobileBackgroundSupported => true;
  @override
  Future<void> initialize({bool background = false}) async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> requestPermission() async {
    granted = true;
    notifyListeners();
  }

  @override
  Future<void> setEnabled(bool value) async {
    preferences.enabled = value;
    notifyListeners();
  }

  @override
  Future<void> setShowEventCount(bool value) async {
    preferences.showEventCount = value;
    notifyListeners();
  }

  @override
  Future<void> setCategory(
      SchoolNotificationCategory category, bool value) async {
    if (category == SchoolNotificationCategory.grade) {
      preferences.grades = value;
    } else {
      preferences.messages = value;
    }
    notifyListeners();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() async {
    await bootstrapTestEnvironment();
  });
  tearDown(resetTestState);

  for (final language in ['en', 'de', 'it', 'lld']) {
    for (final dark in [false, true]) {
      testWidgets(
          'notification permission settings $language ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _SettingsService();
        addTearDown(service.dispose);
        final store = createStore(
            initialState:
                AppState((b) => b.settingsState.languageCode = language));
        final boundary = GlobalKey();
        await pumpApp(tester,
            store: store,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: RepaintBoundary(
                        key: boundary,
                        child: SchoolNotificationSettings(service: service)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SwitchListTile), findsNWidgets(4));
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          final target = File(
              'build/notification_previews/settings_${language}_${dark ? 'dark' : 'light'}.png');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes);
          image.dispose();
        });
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(service.granted, isTrue);
        expect(find.byType(FilledButton), findsNothing);
        await tester.tap(find.byType(SwitchListTile).at(1));
        await tester.pumpAndSettle();
        expect(service.preferences.grades, isFalse);
        expect(service.preferences.messages, isTrue);
        await tester.tap(find.byType(SwitchListTile).first);
        await tester.pumpAndSettle();
        expect(service.preferences.enabled, isFalse);
        expect(
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile).at(1))
                .onChanged,
            isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'diagnostics expand separately and distinguish request from success',
      (tester) async {
    final service = _SettingsService()
      ..granted = true
      ..platformStatus = {'scheduled': true, 'channelsBlocked': true}
      ..diagnostics = {
        'lastBackgroundStartedAt': '2026-10-24T10:00:00Z',
        'lastBackgroundSuccessAt': '2026-10-24T09:00:00Z',
        'lastNotificationRequestedAt': '2026-10-24T08:00:00Z',
        'backgroundResult': 'networkError',
      };
    addTearDown(service.dispose);
    final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = 'en'));
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: SingleChildScrollView(
                child: SchoolNotificationSettings(service: service))));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Last successful background check'), findsNothing);
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Background check scheduled'), findsOneWidget);
    expect(find.textContaining('Last successful background check'),
        findsOneWidget);
    expect(find.textContaining('Last system notification requested'),
        findsOneWidget);
    expect(find.textContaining('channel is disabled'), findsOneWidget);
    expect(find.textContaining('unreachable during the last check'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background unavailable is explained and large text fits',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _SettingsService()..backgroundAvailable = false;
    addTearDown(service.dispose);
    final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = 'en'));
    await pumpApp(tester,
        store: store,
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: SchoolNotificationSettings(service: service)))));
    await tester.pumpAndSettle();
    expect(find.textContaining('currently unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
