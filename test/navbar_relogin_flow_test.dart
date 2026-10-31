import 'dart:async';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import 'support/test_harness.dart';

LoginPayload _demo() => LoginPayload((b) => b
  ..user = 'demo'
  ..pass = 'demo'
  ..url = ''
  ..fromStorage = false);

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> logIn(WidgetTester tester, Future<void> Function() login) async {
    final pending = login();
    await settle(tester);
    await pending;
    await settle(tester);
  }

  ScaffoldState homeScaffold() =>
      scaffoldKey!.currentState!.scaffoldKey.currentState!;

  testWidgets('the drawer is closed after logging out from it and back in',
      (tester) async {
    // Below the tablet breakpoint the navigation is a modal drawer.
    tester.view.physicalSize = const Size(tabletLayoutBreakpoint - 20, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    schoolNotificationStartupReady.value = true;
    final store = createStore(withMiddleware: true);
    await tester.pumpWidget(RegisterApp(store: store));
    await settle(tester);

    for (var round = 0; round < 2; round++) {
      await logIn(tester, () => store.actions.loginActions.login(_demo()));
      expect(store.state.loginState.loggedIn, isTrue);
      expect(homeScaffold().isDrawerOpen, isFalse,
          reason: 'round $round starts with a closed drawer');

      homeScaffold().openDrawer();
      await settle(tester);
      expect(homeScaffold().isDrawerOpen, isTrue);
      await tester.tap(find.text('Abmelden').last);
      await settle(tester);
      expect(store.state.loginState.loggedIn, isFalse);
    }

    await logIn(tester, () => store.actions.loginActions.login(_demo()));
    expect(homeScaffold().isDrawerOpen, isFalse);
    expect(find.byType(Drawer), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    statePersistenceService.clear();
    unawaited(androidWidgetSnapshotService.clear());
    store.dispose();
    await tester.pump(const Duration(minutes: 10));
  });
}
