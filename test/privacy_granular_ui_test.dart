import 'package:dr/analytics_service.dart';
import 'package:dr/privacy_consent.dart';
import 'package:dr/telemetry_capabilities.dart';
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
    await collection.deleteReports();
    await collection.resetAnalytics();
    await collection.analyticsCollection(true);
    await collection.crashCollection(true);
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
                onPressed: () =>
                    AnalyticsService.showPrivacyConsentDialog(context),
                child: const Text('open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('customize needs no age; academic depends on usage',
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
      expect(switches[2].onChanged, isNotNull);
      expect(switches.every((tile) => tile.value), true);
      expect(find.text('Altersberechtigung'), findsNothing);
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auswahl speichern'));
      await tester.pumpAndSettle();
      final decision = AnalyticsService.privacy.decision;
      expect(decision.diagnosticsAllowed, true);
      expect(decision.analyticsAllowed, false);
      expect(decision.academicStatsAllowed, false);
      expect(decision.serialize(), isNot(contains('ageEligibility')));
    });
  });
  testWidgets('save accepts all initial defaults without enabling before save',
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
      expect(AnalyticsService.privacy.decision.allOptionalAllowed, true);
      expect(find.byType(Dialog), findsNothing);
    });
  });
  testWidgets('allow all saves immediately with no extra question',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      expect(
          find.ancestor(
              of: find.text('Alle optionalen Daten erlauben'),
              matching:
                  find.byWidgetPredicate((widget) => widget is FilledButton)),
          findsOneWidget);
      await tester.tap(find.text('Alle optionalen Daten erlauben'));
      await tester.pumpAndSettle();
      expect(find.text('Bist du mindestens 14 Jahre alt?'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(AnalyticsService.privacy.decision.allOptionalAllowed, true);
    });
  });
  testWidgets('custom selection can enable usage and revoke academic again',
      (tester) async {
    await tester.runAsync(() async {
      await open(tester);
      await tester.ensureVisible(find.text('Auswahl anpassen'));
      await tester.tap(find.text('Auswahl anpassen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(find.byType(SwitchListTile).at(2))
              .value,
          false);
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).at(2));
      await tester.ensureVisible(find.byType(SwitchListTile).at(2));
      await tester.tap(find.byType(SwitchListTile).at(2));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile).at(1));
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(find.byType(SwitchListTile).at(2))
              .value,
          false);
      await tester.tap(find.text('Auswahl speichern'));
      await tester.pumpAndSettle();
      expect(AnalyticsService.privacy.decision.diagnosticsAllowed, true);
      expect(AnalyticsService.privacy.decision.analyticsAllowed, false);
    });
  });
}
