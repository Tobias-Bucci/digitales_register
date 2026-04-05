import 'package:dio/dio.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/login_page.dart';
import 'package:dr/container/request_pass_reset_container.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/login_page_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('request pass reset sends the request and shows the success message',
      (tester) async {
    final dio = MockDio();
    passDio = dio;

    when(
      () => dio.post<dynamic>(
        '$testServerUrl/api/auth/resetPassword',
        data: <String, dynamic>{
          'email': 'foo@example.com',
          'username': 'username23',
        },
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        data: <String, Object?>{
          'message': 'Eine Email wurde gesendet...',
        },
        requestOptions: RequestOptions(
          path: '$testServerUrl/api/auth/resetPassword',
        ),
      ),
    );

    final store = createStore(
      initialState: AppState((b) => b.url = testServerUrl),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: RequestPassResetContainer(),
    );

    await tester.enterText(find.byType(TextField).first, 'username23');
    await tester.enterText(find.byType(TextField).last, 'foo@example.com');
    await tester.tap(find.text('Anfrage zum Zurücksetzen senden'));
    await tester.pump();
    await settleFor(tester);

    expect(find.text('Eine Email wurde gesendet...'), findsOneWidget);
    verify(
      () => dio.post<dynamic>(
        '$testServerUrl/api/auth/resetPassword',
        data: <String, dynamic>{
          'email': 'foo@example.com',
          'username': 'username23',
        },
      ),
    ).called(1);
  });

  testWidgets('change password screen requires matching passwords before submit',
      (tester) async {
    String? capturedUser;
    String? capturedOldPass;
    String? capturedNewPass;
    String? capturedUrl;

    await pumpApp(
      tester,
      store: createStore(),
      home: LoginPageContent(
        vm: LoginPageViewModel.from(
          AppState(
            (b) => b.loginState
              ..changePassword = true
              ..mustChangePassword = false
              ..username = 'username23',
          ).rebuild((b) => b.url = testServerUrl),
        ),
        onLogin: (_, __, ___) {},
        onChangePass: (user, oldPass, newPass, url) {
          capturedUser = user;
          capturedOldPass = oldPass;
          capturedNewPass = newPass;
          capturedUrl = url;
        },
        setSaveNoPass: (_) {},
        onReload: () {},
        onRequestPassReset: (_) {},
        onSelectAccount: (_) {},
      ),
    );

    await tester.enterText(
      find.ancestor(
        of: find.text('Altes Passwort'),
        matching: find.byType(TextField),
      ),
      'oldPW',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Neues Passwort'),
        matching: find.byType(TextField),
      ),
      'newPW1',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Neues Passwort wiederholen'),
        matching: find.byType(TextField),
      ),
      'newPW2',
    );
    await tester.pump();

    final initialSubmitButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Passwort ändern'),
    );
    expect(initialSubmitButton.onPressed, isNull);

    await tester.enterText(
      find.ancestor(
        of: find.text('Neues Passwort'),
        matching: find.byType(TextField),
      ),
      'asdf123/ASDF',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Neues Passwort wiederholen'),
        matching: find.byType(TextField),
      ),
      'asdf123/ASDF',
    );
    await tester.pump();

    final enabledSubmitButton =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Passwort ändern'));
    enabledSubmitButton.onPressed!();
    await tester.pump();

    expect(capturedUser, 'username23');
    expect(capturedOldPass, 'oldPW');
    expect(capturedNewPass, 'asdf123/ASDF');
    expect(capturedUrl, testServerUrl);
  });
}
