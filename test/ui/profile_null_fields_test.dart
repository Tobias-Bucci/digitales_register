import 'package:dr/app_state.dart';
import 'package:dr/ui/profile.dart';
import 'package:dr/ui/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('profile with missing optional fields remains usable',
      (tester) async {
    var notificationSetting = false;
    var changeEmailCalls = 0;
    final profile = ProfileState((b) => b..name = 'Test User');

    await pumpApp(
      tester,
      store: createStore(),
      home: Profile(
        profileState: profile,
        baseUrl: null,
        noInternet: false,
        biometricAppLockEnabled: false,
        setSendNotificationEmails: (value) => notificationSetting = value,
        setBiometricAppLockEnabled: (_) {},
        changeEmail: () => changeEmailCalls++,
        changePass: () {},
        uploadProfilePicture: () async {},
        updateCodiceFiscale: (_) async {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(UserProfile), findsOneWidget);

    final notificationSwitch =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).first;
    expect(notificationSwitch.value, isFalse);
    expect(notificationSwitch.onChanged, isNotNull);
    notificationSwitch.onChanged!(true);
    expect(notificationSetting, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();

    final emailTile =
        tester.widgetList<ListTile>(find.byType(ListTile)).firstWhere(
              (tile) =>
                  tile.subtitle is Text && (tile.subtitle! as Text).data == '',
            );
    expect(emailTile.onTap, isNotNull);
    emailTile.onTap!();
    expect(changeEmailCalls, 1);
  });
}
