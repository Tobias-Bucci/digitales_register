import 'package:dr/ui/profile_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

// #142: signing out keeps the account, removing it deletes it. The menu must
// not let the two look alike.
void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  Future<({int logouts, int removals})> pumpMenu(
    WidgetTester tester, {
    required bool logoutKeepsAccount,
    required Future<void> Function() interact,
  }) async {
    var logouts = 0, removals = 0;
    await pumpApp(
      tester,
      store: createStore(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => ProfileMenu(
                name: 'Max',
                username: 'max',
                account: 'max',
                userIcon: null,
                otherAccounts: const [],
                logoutKeepsAccount: logoutKeepsAccount,
                showProfile: () {},
                showSettings: () {},
                selectAccount: (_) {},
                addAccount: () {},
                removeCurrentAccount: () => removals++,
                logout: () => logouts++,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return (logouts: logouts, removals: removals);
  }

  testWidgets('signing out says that the account stays on the device',
      (tester) async {
    final result =
        await pumpMenu(tester, logoutKeepsAccount: true, interact: () async {
      await tester.tap(find.byKey(const Key('profile-menu-logout')));
      await tester.pumpAndSettle();
      expect(find.text('Abmelden?'), findsOneWidget);
      expect(find.textContaining('bleibt auf diesem Gerät gespeichert'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
      await tester.pumpAndSettle();
    });
    expect(result, (logouts: 1, removals: 0));
  });

  testWidgets('in the browser and the demo it promises nothing of the kind',
      (tester) async {
    await pumpMenu(tester, logoutKeepsAccount: false, interact: () async {
      await tester.tap(find.byKey(const Key('profile-menu-logout')));
      await tester.pumpAndSettle();
      expect(find.text('Du kannst dich jederzeit wieder anmelden.'),
          findsOneWidget);
      expect(find.textContaining('bleibt auf diesem Gerät'), findsNothing);
    });
  });

  testWidgets('removing asks a destructive question about this device',
      (tester) async {
    final result =
        await pumpMenu(tester, logoutKeepsAccount: true, interact: () async {
      await tester.tap(find.byKey(const Key('profile-menu-remove-account')));
      await tester.pumpAndSettle();
      expect(find.text('Konto von diesem Gerät entfernen?'), findsOneWidget);
      expect(find.textContaining('mit den gespeicherten Zugangsdaten'),
          findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Konto entfernen');
      final context = tester.element(confirm);
      final button = tester.widget<FilledButton>(confirm);
      expect(button.style?.backgroundColor?.resolve({}),
          Theme.of(context).colorScheme.error);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    });
    expect(result, (logouts: 0, removals: 1));
  });

  testWidgets('the two entries look different', (tester) async {
    await pumpMenu(tester, logoutKeepsAccount: true, interact: () async {
      Icon iconOf(String key) => tester.widget<Icon>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(Icon)));
      expect(iconOf('profile-menu-logout').icon, Icons.logout_rounded);
      expect(iconOf('profile-menu-remove-account').icon,
          Icons.person_remove_outlined);
    });
  });
}
