import 'package:dr/app_state.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/profile_avatar.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('tapping the profile avatar opens the profile page',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b
          ..noInternet = true
          ..loginState.username = 'Anna Beispiel',
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: SidebarContainer(
          tabletMode: false,
          goHome: () {},
          currentSelected: Pages.homework,
        ),
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('Profilseite')),
          );
        }
        return null;
      },
    );
    await settleFor(tester);

    await tester.tap(find.byType(ProfileAvatar));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Profilseite'), findsOneWidget);
  });

  testWidgets('collapsed tablet sidebar shows no username text',
      (tester) async {
    final store = createStore(initialState: AppState(), withMiddleware: true);

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(
        body: Sidebar(
          tabletMode: true,
          drawerExpanded: false,
          onDrawerExpansionChange: _noopDrawerCallback,
          username: 'Anna Beispiel',
          userIcon: null,
          goHome: _noopVoidCallback,
          currentSelected: Pages.homework,
          showGrades: _noopVoidCallback,
          showAbsences: _noopVoidCallback,
          showCalendar: _noopVoidCallback,
          showCertificate: _noopVoidCallback,
          showMessages: _noopVoidCallback,
          showProfile: _noopVoidCallback,
          showSettings: _noopVoidCallback,
          logout: _noopVoidCallback,
          otherAccounts: <String>[],
          selectAccount: _noopSelectAccount,
          addAccount: _noopVoidCallback,
          passwordSavingEnabled: true,
        ),
      ),
    );
    await settleFor(tester);

    expect(find.byType(ProfileAvatar), findsOneWidget);
    expect(find.text('Anna Beispiel'), findsNothing);
  });
}

void _noopVoidCallback() {}

void _noopDrawerCallback(bool _) {}

void _noopSelectAccount(int _) {}
