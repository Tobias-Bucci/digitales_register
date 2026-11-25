import 'dart:convert';
import 'dart:io';

import 'package:dr/analytics_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/privacy_consent_dialog.dart';
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'support/privacy_test_mocks.dart';

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
  setUp(mockPrivacyPlugins);

  // #162: the in-app details describe what the app does in the background
  // and outside the app, and promise nothing the code does not do.
  test('privacy details cover notifications and widgets in every language', () {
    expect(PrivacyDataDetailsPage.sections.keys,
        containsAll(['schoolNotifications', 'widgets']));
    for (final language in ['de', 'en', 'it', 'lld']) {
      final texts =
          jsonDecode(File('assets/locales/$language.json').readAsStringSync())
              as Map<String, dynamic>;
      for (final section in PrivacyDataDetailsPage.sections.keys) {
        for (final part in ['title', 'body']) {
          expect(texts['privacyDetails.$section.$part'], isNotEmpty,
              reason: '$language privacyDetails.$section.$part');
        }
      }
    }
    final en = jsonDecode(File('assets/locales/en.json').readAsStringSync())
        as Map<String, dynamic>;
    // Crashlytics has no user ID, so the ID cannot find diagnostics data.
    expect(
        en['privacySettings.technicalId.hint'], isNot(contains('diagnostics')));
    expect(en['desktop.keyringUnavailable'], isNot(contains('protected')));
  });

  // #162 items 8-10: the web app's school proxy is disclosed, its "Stay
  // signed in" is not called secure storage, and only Android and iOS use
  // Firebase.
  test('privacy texts disclose the web proxy and the platforms honestly', () {
    // Words that only the new texts contain, per language.
    const webApp = {
      'de': 'Web-App',
      'en': 'web app',
      'it': 'web app',
      'lld': 'web app',
    };
    const password = {
      'de': 'Passwort',
      'en': 'password',
      'it': 'password',
      'lld': 'password',
    };
    const browser = {
      'de': 'Browser',
      'en': 'browser',
      'it': 'browser',
      'lld': 'browser',
    };
    const oldFirebaseClaim = {
      'de': 'Windows und Linux verwenden keine Firebase',
      'en': 'Windows and Linux use no Firebase',
      'it': 'Windows e Linux non usano',
      'lld': 'Windows y Linux ne adora',
    };
    for (final language in ['de', 'en', 'it', 'lld']) {
      final texts =
          jsonDecode(File('assets/locales/$language.json').readAsStringSync())
              as Map<String, dynamic>;
      String text(String key) => texts[key] as String;
      final necessary = text('privacyConsent.necessary.details');
      final cloudflare = text('privacyDetails.cloudflare.body');
      final local = text('privacyDetails.local.body');
      final limits = text('privacyDetails.limits.body');
      final notice = text('privacyDetails.notice.body');
      for (final (name, value) in [
        ('necessary', necessary),
        ('cloudflare', cloudflare),
        ('local', local),
        ('notice', notice),
      ]) {
        expect(value, contains(webApp[language]), reason: '$language $name');
      }
      expect(necessary, contains('Cloudflare'), reason: language);
      expect(necessary, contains(password[language]), reason: language);
      expect(cloudflare, contains('app.digitalesregister.com'),
          reason: language);
      expect(cloudflare, contains('Cloudflare Worker'), reason: language);
      expect(local, contains(text('login.stayLoggedIn')), reason: language);
      expect(local, contains(browser[language]), reason: language);
      expect(limits, isNot(contains(oldFirebaseClaim[language])),
          reason: language);
      for (final platform in ['Android', 'iOS', 'macOS']) {
        expect(limits, contains(platform), reason: '$language $platform');
      }
    }
  });
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
                  onPressed: () => showPrivacyConsentDialog(context),
                  child: const Text('open')),
              TextButton(
                  onPressed: () => showPrivacyOptionsForm(context),
                  child: const Text('manage')),
            ])))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Nur erforderliche Daten'), findsWidgets);
    expect(find.text('Alle optionalen Daten erlauben'), findsOneWidget);
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.ensureVisible(find.text('Mehr erfahren'));
    await tester.tap(find.text('Mehr erfahren'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyDataDetailsPage), findsOneWidget);
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Alle optionalen Daten erlauben'), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacy-required-only')));
    await tester.pumpAndSettle();
    expect(AnalyticsService.hasCurrentConsent, true);
    expect(AnalyticsService.statisticsEnabled, false);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Alle optionalen Daten erlauben'), findsNothing);
    await tester.tap(find.text('manage'));
    await tester.pumpAndSettle();
    for (final tile
        in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(tile.value, false);
    }
    expect(find.text('Alle optionalen Daten erlauben'), findsOneWidget);
    await tester.tap(find.text('Alle optionalen Daten erlauben'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-age-confirm')));
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
