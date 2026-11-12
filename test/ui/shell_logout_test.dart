import 'dart:async';

import 'package:dr/actions/login_actions.dart';
import 'package:dr/main.dart' show RegisterApp, navigatorKey, nestedNavKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/profile.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

// On its own like navbar_relogin_flow_test.dart: signing in and out through
// the real app needs a fresh middleware state.
void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('logging out from Profile in the shell leaves nothing behind',
      (tester) async {
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    schoolNotificationStartupReady.value = true;
    final store = createStore(withMiddleware: true, newDesign: true);
    await tester.pumpWidget(RegisterApp(store: store));
    await settle();

    Future<void> logIn() async {
      final login = store.actions.loginActions.login(LoginPayload((b) => b
        ..user = 'demo'
        ..pass = 'demo'
        ..url = ''
        ..fromStorage = false));
      await settle();
      await login;
      await settle();
    }

    await logIn();
    expect(store.state.loginState.loggedIn, isTrue);

    // The calculator of the grades opens in the shell as well.
    await store.actions.routingActions.showGradeCalculator();
    await settle();
    expect(find.byType(GradeCalculator), findsOneWidget);
    await store.actions.routingActions.showProfile();
    await settle();
    expect(find.byType(Profile), findsOneWidget);
    expect(nestedNavKey.currentState!.canPop(), isTrue);

    await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
    await settle();
    expect(find.byKey(const Key('profile-menu-logout')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-menu-logout')));
    await settle();
    expect(find.widgetWithText(FilledButton, 'Abmelden'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
    for (var i = 0; i < 5 && store.state.loginState.loggedIn; i++) {
      await settle();
    }
    expect(store.state.loginState.loggedIn, isFalse);
    expect(find.byType(Profile), findsNothing);

    // As in legacy, the pages wait below the login page until the next
    // sign-in, which closes all of them.
    await logIn();
    expect(store.state.loginState.loggedIn, isTrue);
    expect(find.byType(Profile, skipOffstage: false), findsNothing);
    expect(find.byType(GradeCalculator, skipOffstage: false), findsNothing);
    expect(nestedNavKey.currentState!.canPop(), isFalse);
    expect(navigatorKey!.currentState!.canPop(), isFalse);
    expect(openProfileShellPages.value, 0);
    expect(
        tester
            .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
            .selected,
        AppDestination.dashboard);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    statePersistenceService.clear();
    unawaited(androidWidgetSnapshotService.clear());
    unawaited(store.dispose());
    await tester.pump(const Duration(minutes: 10));
  });
}
