import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/change_email_container.dart';
import 'package:dr/container/profile_container.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/ui/change_email.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('profile opens the change-email form through the store',
      (tester) async {
    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(
        (b) => b
          ..settingsState.languageCode = 'en'
          ..profileState.name = 'Test User',
      ),
      AppActions(),
      middleware: <Middleware<AppState, AppStateBuilder, AppActions>>[
        routingMiddleware.build(),
      ],
    );

    await pumpApp(
      tester,
      store: store,
      home: ProfileContainer(),
      onGenerateRoute: (settings) => settings.name == '/change_email'
          ? MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => ChangeEmailContainer(),
            )
          : null,
    );
    await settleFor(tester);

    final changeEmail = find.text('Change email address');
    await tester.scrollUntilVisible(changeEmail, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(changeEmail);
    await settleFor(tester, duration: const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.byType(ChangeEmail), findsOneWidget);
    expect(find.text('New email address'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await store.dispose();
  });
}
