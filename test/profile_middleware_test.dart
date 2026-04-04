import 'package:dr/app_state.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

void main() {
  late MockWrapper mockWrapper;

  setUp(() async {
    mockWrapper = MockWrapper();
    when(() => mockWrapper.loginAddress).thenReturn(testLoginAddress);
    when(() => mockWrapper.noInternet).thenReturn(false);
    await bootstrapTestEnvironment(wrapperOverride: mockWrapper);
  });

  tearDown(resetTestState);

  testWidgets(
      'sendNotificationEmails keeps the previous state when the server logs out unexpectedly',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/profile/updateNotificationSettings',
        args: <String, Object?>{'notificationsEnabled': false},
      ),
    ).thenThrow(UnexpectedLogoutException());

    final store = createStore(
      initialState: AppState(
        (b) {
          b.profileState.sendNotificationEmails = true;
        },
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(body: SizedBox()),
    );
    await tester.pump();

    await expectLater(
      store.actions.profileActions.sendNotificationEmails(false),
      completes,
    );
    await tester.pump();

    expect(store.state.profileState.sendNotificationEmails, isTrue);
    verify(
      () => mockWrapper.send(
        'api/profile/updateNotificationSettings',
        args: <String, Object?>{'notificationsEnabled': false},
      ),
    ).called(1);
  });
}
