import 'dart:io';
import 'dart:ui' as ui;

import 'package:dr/app_state.dart';
import 'package:dr/biometric_app_lock.dart';
import 'package:dr/school_notification_engine.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

class _Service extends SchoolNotificationService {
  int generation = 1;
  int saves = 0;
  final savedAccounts = <String>[];
  bool fail = false;
  _Service() {
    activeAccount = notificationDigest(['school', 'student']);
    activeAccountLabel = 'Student · school.example';
  }
  @override
  int get sessionGeneration => generation;
  @override
  Future<SchoolNotificationOptInOffer?> pendingOptIn() async =>
      preferences.consent == SchoolNotificationConsent.unknown &&
              activeAccount != null
          ? SchoolNotificationOptInOffer(
              activeAccount!, generation, activeAccountLabel!)
          : null;
  @override
  Future<bool> decideOptIn(SchoolNotificationOptInOffer offer,
      {required bool accept, bool grades = true, bool messages = true}) async {
    if (fail) throw StateError('test storage failed');
    saves++;
    savedAccounts.add(offer.account);
    preferences
      ..consent = accept
          ? SchoolNotificationConsent.accepted
          : SchoolNotificationConsent.declined
      ..enabled = accept
      ..grades = grades
      ..messages = messages;
    notifyListeners();
    return true;
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
  Future<void> host(WidgetTester tester, _Service service,
      {ValueNotifier<bool>? ready,
      bool signedIn = true,
      String language = 'en',
      Key? key}) async {
    final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = language));
    await pumpApp(tester,
        store: store,
        home: SchoolNotificationOptInHost(
            key: key,
            signedIn: signedIn,
            account: service.activeAccount,
            service: service,
            ready: ready ?? ValueNotifier(true),
            child: const Scaffold(body: Text('Dashboard'))));
    await tester.pumpAndSettle();
  }

  for (final language in ['de', 'it', 'en', 'lld']) {
    for (final dark in [false, true]) {
      testWidgets(
          'opt-in $language ${dark ? 'dark' : 'light'} is localized and preselection is not consent',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _Service();
        addTearDown(service.dispose);
        final boundary = GlobalKey();
        final store = createStore(
            initialState:
                AppState((b) => b.settingsState.languageCode = language));
        await pumpApp(tester,
            store: store,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => RepaintBoundary(
                                key: boundary,
                                child: SchoolNotificationOptInDialog(
                                    accountLabel: 'Student · school.example',
                                    onDecision: (a, g, m) async {
                                      await service.decideOptIn(
                                          SchoolNotificationOptInOffer(
                                              service.activeAccount!, 1, ''),
                                          accept: a,
                                          grades: g,
                                          messages: m);
                                    }))),
                        child: const Text('Open')))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                .every((tile) => tile.value == true),
            isTrue);
        expect(service.saves, 0);
        expect(service.preferences.enabled, isFalse);
        expect(find.textContaining('schoolNotifications.'), findsNothing);
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          final target = File(
              'build/notification_optin_previews/${language}_${dark ? 'dark' : 'light'}.png');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes);
          image.dispose();
        });
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(service.saves, 1);
        expect(service.preferences.enabled, isTrue);
        expect(service.preferences.grades, isTrue);
        expect(service.preferences.messages, isTrue);
        expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'fresh login offers once, decline remains off and rebuilds do not repeat',
      (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    await host(tester, service);
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
    await tester.tap(find.text('No, thanks'));
    await tester.pumpAndSettle();
    expect(service.preferences.enabled, isFalse);
    expect(service.saves, 1);
    await host(tester, service, key: const ValueKey('restart'));
    expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
  });

  testWidgets(
      'startup notices finish before opt-in; signed-out state does not prompt',
      (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await host(tester, service, ready: ready);
    expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
    ready.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
    await host(tester, service, ready: ready, signedIn: false);
    expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
    expect(service.saves, 0);
  });

  testWidgets(
      'account change dismisses the old dialog and offers the new account',
      (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final ready = ValueNotifier(true);
    addTearDown(ready.dispose);
    await host(tester, service, ready: ready);
    final previous = service.activeAccount;
    service.activeAccount = notificationDigest(['other-school', 'student']);
    service.generation++;
    await host(tester, service, ready: ready);
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
    expect(service.activeAccount, isNot(previous));
    expect(service.saves, 0);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(service.savedAccounts.single, service.activeAccount);
  });

  testWidgets('an app lock defers the opt-in until the user unlocks',
      (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    biometricAppLockController.syncEnabled(true);
    addTearDown(() => biometricAppLockController.syncEnabled(false));
    await host(tester, service);
    expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
    biometricAppLockController.syncEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
  });

  testWidgets('another modal finishes before the opt-in is offered',
      (tester) async {
    final service = _Service();
    addTearDown(service.dispose);
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await host(tester, service, ready: ready);
    final other = showDialog<void>(
        context: tester.element(find.text('Dashboard')),
        builder: (_) => const AlertDialog(content: Text('Other dialog')));
    await tester.pumpAndSettle();
    ready.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(SchoolNotificationOptInDialog), findsNothing);
    Navigator.of(tester.element(find.text('Other dialog'))).pop();
    await other;
    await tester.pumpAndSettle();
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
  });

  testWidgets('large text fits and choosing no categories disables acceptance',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore(
        initialState: AppState((b) => b.settingsState.languageCode = 'de'));
    var saves = 0;
    await pumpApp(tester,
        store: store,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => MediaQuery(
                            data: const MediaQueryData(
                                textScaler: TextScaler.linear(1.8)),
                            child: SchoolNotificationOptInDialog(
                                accountLabel: 'Student · school.example',
                                onDecision: (a, g, m) async {
                                  saves++;
                                }))),
                    child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (final finder in [
      find.byType(CheckboxListTile).first,
      find.byType(CheckboxListTile).last
    ]) {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SchoolNotificationOptInDialog), findsOneWidget);
    await tester.ensureVisible(find.text('Nein, danke'));
    await tester.tap(find.text('Nein, danke'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed persistence keeps a retryable dialog without consent',
      (tester) async {
    final service = _Service()..fail = true;
    addTearDown(service.dispose);
    await host(tester, service);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(service.preferences.enabled, isFalse);
    expect(service.saves, 0);
    service.fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
  });
}
