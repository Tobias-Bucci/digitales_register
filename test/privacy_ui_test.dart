import 'package:dr/analytics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

Widget app(Widget home,
        {Brightness brightness = Brightness.light,
        Locale locale = const Locale('de')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData(brightness: brightness),
      home: home,
    );

void main() {
  testWidgets(
      'details preserve unresolved choice; required-only closes once; settings can reopen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    await AnalyticsService.initLich();
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
                body: Column(children: [
              TextButton(
                  onPressed: () =>
                      AnalyticsService.showPrivacyConsentDialog(context),
                  child: const Text('open')),
              TextButton(
                  onPressed: () =>
                      AnalyticsService.showPrivacyOptionsForm(context),
                  child: const Text('manage')),
            ])))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Nur erforderliche Daten'), findsWidgets);
    expect(find.text('Zustimmen'), findsOneWidget);
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.tap(find.text('Mehr erfahren'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyDataDetailsPage), findsOneWidget);
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Zustimmen'), findsOneWidget);
    await tester
        .tap(find.widgetWithText(TextButton, 'Nur erforderliche Daten'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.hasCurrentConsent, true);
    expect(AnalyticsService.statisticsEnabled, false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Zustimmen'), findsNothing);
    await tester.tap(find.text('manage'));
    await tester.pumpAndSettle();
    expect(find.text('Optionale Diagnose- und Nutzungsdaten erlauben'),
        findsOneWidget);
    await tester
        .tap(find.text('Optionale Diagnose- und Nutzungsdaten erlauben'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.privacy.decision.allowsTelemetry, true);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final locale in [
      const Locale('de'),
      const Locale('it'),
      const Locale('en'),
      const Locale('de', 'LLD')
    ]) {
      testWidgets(
          'details at phone size ${brightness.name} ${locale.toLanguageTag()}',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app(const PrivacyDataDetailsPage(),
            brightness: brightness, locale: locale));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
