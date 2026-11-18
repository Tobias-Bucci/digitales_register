import 'dart:convert';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/demo.dart';
import 'package:dr/main.dart' show navigatorKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

const _allowed = PrivacyDecision(
  version: currentPrivacyNoticeVersion,
  completed: true,
  usageAnalyticsConsent: ConsentChoice.granted,
  academicStatisticsConsent: ConsentChoice.granted,
  diagnosticsConsent: ConsentChoice.denied,
);

const _withdrawn = PrivacyDecision(
  version: currentPrivacyNoticeVersion,
  completed: true,
  usageAnalyticsConsent: ConsentChoice.denied,
  academicStatisticsConsent: ConsentChoice.denied,
  diagnosticsConsent: ConsentChoice.denied,
);

final _uuid = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}');

/// The consent and the analytics gate as PrivacyController leaves them.
/// [running] is false where usage analytics cannot run (no Firebase in this
/// build, desktop): the choice is saved, the gate stays closed.
void _privacy(PrivacyDecision decision, {required bool running}) {
  AnalyticsService.privacy
    ..decision = decision
    ..sdkReady = running;
  AnalyticsService.product.gate(running && decision.analyticsAllowed);
}

Future<void> _resetAnalytics() async {
  _privacy(const PrivacyDecision(), running: false);
  await AnalyticsService.product.clearIdentity();
}

void main() {
  final tile = find.byKey(const Key('settings-technical-id'));
  final copy = find.byKey(const Key('settings-technical-id-copy'));

  setUp(() async {
    await bootstrapTestEnvironment();
    await resetDemoStoreForTest();
    await _resetAnalytics();
  });

  tearDown(() async {
    await _resetAnalytics();
    await resetDemoStoreForTest();
    await resetTestState();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, store: createStore(), home: SettingsPageContainer());
    await settleFor(tester);
    for (var i = 0; i < 20 && tile.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(500, 2000), const Offset(0, -600));
      await settleFor(tester);
    }
    expect(tile, findsOneWidget);
  }

  String subtitle(WidgetTester tester) =>
      (tester.widget<ListTile>(tile).subtitle! as Text).data!;

  testWidgets('never allowed: "none" with that reason', (tester) async {
    await pumpSettings(tester);
    expect(subtitle(tester), contains('nie eine Nutzungsanalyse erlaubt'));
    expect(copy, findsNothing);
  });

  testWidgets(
      'allowed where usage analytics cannot run: no identifier, and the '
      'tile does not claim it was never allowed', (tester) async {
    _privacy(_allowed, running: false);
    await pumpSettings(tester);
    expect(subtitle(tester), isNot(contains('nie')));
    expect(subtitle(tester), contains('nicht verfügbar'));
    expect(copy, findsNothing);
  });

  testWidgets(
      'allowed: the identifier appears without leaving the page once the '
      'open account is identified', (tester) async {
    _privacy(_allowed, running: true);
    await pumpSettings(tester);
    expect(subtitle(tester), isNot(contains('nie')));
    expect(copy, findsNothing);

    await tester.runAsync(() => AnalyticsService.product
        .identifyUser(jsonEncode(['', 'demo']), demo: true));
    await tester.runAsync(AnalyticsService.product.flush);
    await settleFor(tester);
    for (var i = 0; i < 5 && copy.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    final id =
        await tester.runAsync(AnalyticsService.product.currentPseudonymousId);
    expect(id, matches(_uuid));
    expect(subtitle(tester), startsWith(id!));
    expect(subtitle(tester), contains('pseudonyme Kennung'));
    expect(copy, findsOneWidget);
  });

  testWidgets('withdrawn later: the stored identifier stays shown',
      (tester) async {
    _privacy(_allowed, running: true);
    await tester.runAsync(() async {
      await AnalyticsService.product
          .identifyUser(jsonEncode(['', 'demo']), demo: true);
      await AnalyticsService.product.flush();
    });
    final id =
        await tester.runAsync(AnalyticsService.product.currentPseudonymousId);
    expect(id, matches(_uuid));

    _privacy(_withdrawn, running: true);
    await pumpSettings(tester);
    for (var i = 0; i < 5 && copy.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(subtitle(tester), startsWith(id!));
    expect(copy, findsOneWidget);
  });

  group('through sign-in', () {
    setUp(() async {
      await bootstrapTestEnvironment(storage: {
        'login': jsonEncode({'user': 'demo', 'pass': 'demo', 'url': ''}),
      });
      await resetDemoStoreForTest();
      await _resetAnalytics();
      navigatorKey = null;
    });

    Future<void> startApp() async {
      // A new process: a new connection, nothing of the account in memory.
      wrapper = Wrapper();
      resetMiddlewareStateForTest();
      await AnalyticsService.product.clearIdentity();
      await createStore(withMiddleware: true).actions.load();
      await AnalyticsService.product.flush();
    }

    test(
        'after consent is withdrawn and the app restarts, the open account '
        'still finds its stored identifier', () async {
      _privacy(_allowed, running: true);
      await startApp();
      final id = await AnalyticsService.product.currentPseudonymousId();
      expect(id, matches(_uuid));

      _privacy(_withdrawn, running: true);
      await startApp();
      expect(await AnalyticsService.product.currentPseudonymousId(), id);
    });

    test('a sign-in while analytics is off creates and sends nothing',
        () async {
      _privacy(_withdrawn, running: true);
      await startApp();
      expect(await AnalyticsService.product.currentPseudonymousId(), isNull);
      expect(AnalyticsService.product.identityReady, isFalse);

      // Consent given later identifies the open account at once.
      _privacy(_allowed, running: true);
      await AnalyticsService.product.applyPrivacyState();
      expect(await AnalyticsService.product.currentPseudonymousId(),
          matches(_uuid));
    });
  });
}
