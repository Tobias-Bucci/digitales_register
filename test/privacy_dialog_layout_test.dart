import 'package:dr/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_ui_test.dart' show app;
import 'support/privacy_test_mocks.dart';

void main() {
  setUp(mockPrivacyPlugins);

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1024, 768)
  ]) {
    for (final brightness in Brightness.values) {
      for (final locale in [
        const Locale('de'),
        const Locale('it'),
        const Locale('en'),
        const Locale('de', 'LLD')
      ]) {
        testWidgets(
            'privacy dialog ${size.width} ${brightness.name} ${locale.toLanguageTag()}',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundaryKey = GlobalKey();
          await tester.runAsync(() async {
            SharedPreferences.setMockInitialValues({});
            PackageInfo.setMockInitialValues(
                appName: 'Test',
                packageName: 'test',
                version: '1.0.0',
                buildNumber: '1',
                buildSignature: '');
            await AnalyticsService.initLich();
            await AnalyticsService.privacy.initialize();
            await tester.pumpWidget(RepaintBoundary(
                key: boundaryKey,
                child: app(
                    Builder(
                        builder: (context) => Scaffold(
                            body: TextButton(
                                onPressed: () =>
                                    AnalyticsService.showPrivacyConsentDialog(
                                        context),
                                child: const Text('open')))),
                    brightness: brightness,
                    locale: locale)));
            await tester.pumpAndSettle();
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            final buttons =
                find.byWidgetPredicate((widget) => widget is FilledButton);
            expect(buttons, findsOneWidget);
            expect(
                tester.getRect(buttons).bottom, lessThanOrEqualTo(size.height));
            expect(tester.takeException(), isNull);
            expect(find.byIcon(Icons.verified_user_outlined), findsNothing);
            await tester.tap(buttons);
            await tester.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(AnalyticsService.privacy.decision.allOptionalAllowed, true);
          });
        });
      }
    }
  }
}
