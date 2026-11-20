import 'package:dr/analytics_service.dart';
import 'package:dr/telemetry_capabilities.dart';
import 'package:dr/ui/privacy_consent_dialog.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_ui_test.dart' show app;
import 'support/privacy_test_mocks.dart';

void main() {
  setUp(mockPrivacyPlugins);

  test('native telemetry adapters work on a supported platform', () async {
    final collection = FirebaseTelemetryCollection(
      capabilities: const TelemetryCapabilities(TargetPlatform.macOS),
    );
    // Covers the macOS SDK path even when the suite runs on Windows/Linux.
    await collection.analyticsCollection(false);
    await collection.crashCollection(false);
    expect(FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled, false);
    await collection.deleteReports();
    await collection.resetAnalytics();
    await collection.analyticsCollection(true);
    await collection.crashCollection(true);
    expect(FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled, true);
    await FirebaseCrashlytics.instance.setCustomKey('screen', 'test');
    await FirebaseCrashlytics.instance.log('test');
    await FirebaseCrashlytics.instance.recordError(
      StateError('test'),
      StackTrace.current,
      printDetails: false,
    );
  });

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    await AnalyticsService.initLich();
    await AnalyticsService.privacy.initialize();
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => showPrivacyConsentDialog(context),
                child: const Text('open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('customize asks no age up front; academic depends on usage',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await tester.ensureVisible(find.text('Auswahl anpassen'));
      await tester.tap(find.text('Auswahl anpassen'));
      await tester.pumpAndSettle();
      expect(AnalyticsService.hasCurrentConsent, false);
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches[0].onChanged, isNotNull);
      expect(switches[1].onChanged, isNotNull);
      // Academic statistics need usage analytics, which starts off.
      expect(switches[2].onChanged, isNull);
      // A first decision starts with every optional purpose off (#155).
      expect(switches.every((tile) => !tile.value), true);
      expect(find.text('Altersberechtigung'), findsNothing);
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auswahl speichern'));
      await tester.pumpAndSettle();
      // Switching a purpose on asks for the age confirmation (Art. 2-quinquies
      // D.Lgs. 196/2003).
      expect(find.byKey(const Key('privacy-age-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy-age-confirm')));
      await tester.pumpAndSettle();
      final decision = AnalyticsService.privacy.decision;
      expect(decision.diagnosticsAllowed, false);
      expect(decision.analyticsAllowed, true);
      expect(decision.academicStatsAllowed, false);
      expect(decision.serialize(), isNot(contains('ageEligibility')));
    });
  });
  testWidgets('saving the untouched choices allows no optional purpose',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      expect(AnalyticsService.privacy.sdkReady, false);
      expect(AnalyticsService.hasCurrentConsent, false);
      await tester.ensureVisible(find.text('Auswahl anpassen'));
      await tester.tap(find.text('Auswahl anpassen'));
      await tester.pumpAndSettle();
      expect(AnalyticsService.hasCurrentConsent, false);
      await tester.tap(find.text('Auswahl speichern'));
      await tester.pumpAndSettle();
      // Nothing was switched on, so there is no age question either.
      expect(find.byKey(const Key('privacy-age-confirm')), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(AnalyticsService.hasCurrentConsent, true);
      final decision = AnalyticsService.privacy.decision;
      expect(decision.diagnosticsAllowed, false);
      expect(decision.analyticsAllowed, false);
      expect(decision.academicStatsAllowed, false);
      expect(AnalyticsService.privacy.sdkReady, false);
    });
  });
  testWidgets('refusing looks exactly like accepting', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      final acceptAll = find.byKey(const Key('privacy-accept-all'));
      final requiredOnly = find.byKey(const Key('privacy-required-only'));
      expect(tester.widget(acceptAll).runtimeType,
          tester.widget(requiredOnly).runtimeType);
      expect(tester.widget<ButtonStyleButton>(acceptAll).style,
          tester.widget<ButtonStyleButton>(requiredOnly).style);
      expect(tester.getSize(acceptAll), tester.getSize(requiredOnly));
      await tester.tap(requiredOnly);
      await tester.pumpAndSettle();
    });
  });
  testWidgets('allow all asks for the age confirmation, then saves',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      expect(
          find.descendant(
              of: find.byKey(const Key('privacy-accept-all')),
              matching: find.text('Alle optionalen Daten erlauben')),
          findsOneWidget);
      await tester.tap(find.text('Alle optionalen Daten erlauben'));
      await tester.pumpAndSettle();
      expect(
          find.text('Ich bin mindestens 14 Jahre alt oder meine '
              'Erziehungsberechtigten sind einverstanden.'),
          findsOneWidget);
      // Switching a purpose on asks for the age confirmation (Art. 2-quinquies
      // D.Lgs. 196/2003).
      expect(find.byKey(const Key('privacy-age-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy-age-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(AnalyticsService.privacy.decision.allOptionalAllowed, true);
    });
  });
  testWidgets('without the age confirmation nothing is switched on',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await tester.tap(find.text('Alle optionalen Daten erlauben'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy-age-cancel')));
      await tester.pumpAndSettle();
      // The privacy dialog stays open and nothing was decided.
      expect(find.text('Alle optionalen Daten erlauben'), findsOneWidget);
      expect(AnalyticsService.hasCurrentConsent, false);
      expect(AnalyticsService.privacy.decision.diagnosticsAllowed, false);
      expect(AnalyticsService.privacy.decision.analyticsAllowed, false);
      expect(AnalyticsService.privacy.decision.academicStatsAllowed, false);
      // Close the dialog, so that the next test opens a new one.
      await tester.tap(find.byKey(const Key('privacy-required-only')));
      await tester.pumpAndSettle();
    });
  });
  testWidgets('necessary only asks no age', (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await tester.tap(find.byKey(const Key('privacy-required-only')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-age-confirm')), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(AnalyticsService.hasCurrentConsent, true);
      expect(AnalyticsService.privacy.decision.allOptionalAllowed, false);
    });
  });
  testWidgets('custom selection can enable usage and revoke academic again',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await tester.ensureVisible(find.text('Auswahl anpassen'));
      await tester.tap(find.text('Auswahl anpassen'));
      await tester.pumpAndSettle();
      SwitchListTile tile(int index) =>
          tester.widget<SwitchListTile>(find.byType(SwitchListTile).at(index));
      Future<void> toggle(int index) async {
        await tester.ensureVisible(find.byType(SwitchListTile).at(index));
        await tester.tap(find.byType(SwitchListTile).at(index));
        await tester.pumpAndSettle();
      }

      // Academic statistics need usage analytics.
      expect(tile(2).onChanged, isNull);
      await toggle(1);
      await toggle(2);
      expect(tile(2).value, true);
      await toggle(1);
      expect(tile(2).value, false);
      await toggle(0);
      await tester.tap(find.text('Auswahl speichern'));
      await tester.pumpAndSettle();
      // Switching a purpose on asks for the age confirmation (Art. 2-quinquies
      // D.Lgs. 196/2003).
      expect(find.byKey(const Key('privacy-age-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy-age-confirm')));
      await tester.pumpAndSettle();
      expect(AnalyticsService.privacy.decision.diagnosticsAllowed, true);
      expect(AnalyticsService.privacy.decision.analyticsAllowed, false);
      expect(AnalyticsService.privacy.decision.academicStatsAllowed, false);
    });
  });
}
