import 'package:dr/analytics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/privacy_test_mocks.dart';

void main() {
  setUp(mockPrivacyPlugins);
  testWidgets('legacy user sees one privacy update until a decision is saved',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'privacy_consent_choice_v2': 'v2_all'});
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    await AnalyticsService.initLich();
    expect(AnalyticsService.statisticsEnabled, false);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () =>
                      AnalyticsService.showPrivacyConsentDialog(context),
                  child: const Text('open')))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Aktualisierte Datenschutzeinstellungen'), findsOneWidget);
    await tester
        .tap(find.widgetWithText(TextButton, 'Nur erforderliche Daten'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.hasCurrentConsent, true);
    expect(AnalyticsService.statisticsEnabled, false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Aktualisierte Datenschutzeinstellungen'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('privacy_consent_choice_v2'), false);
  });
}
