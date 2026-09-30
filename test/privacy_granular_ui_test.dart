import 'package:dr/analytics_service.dart';
import 'package:dr/privacy_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'privacy_ui_test.dart' show app;

void main() {
  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    await tester.runAsync(() => AnalyticsService.initLich());
    await tester.runAsync(() => AnalyticsService.privacy.initialize());
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () =>
                    AnalyticsService.showPrivacyConsentDialog(context),
                child: const Text('open'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }

  testWidgets('customize does not save; under14 disables every optional toggle',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Auswahl anpassen'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.hasCurrentConsent, false);
    for (final widget
        in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(widget.onChanged, isNull);
    }
    await tester.ensureVisible(find.text('Altersberechtigung'));
    await tester.tap(find.text('Altersberechtigung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.hasCurrentConsent, false);
    for (final widget
        in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(widget.value, false);
      expect(widget.onChanged, isNull);
    }
    await tester.tap(find.text('Auswahl speichern'));
    await tester.pumpAndSettle();
    final decision = AnalyticsService.privacy.decision;
    expect(decision.ageEligibility, AnalyticsAgeEligibility.under14);
    expect(decision.requiredOnly, true);
    expect(decision.diagnosticsConsent, ConsentChoice.denied);
    expect(decision.usageAnalyticsConsent, ConsentChoice.denied);
    expect(decision.academicStatisticsConsent, ConsentChoice.denied);
  });
  testWidgets('all optional first requires age and No cannot enable collection',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Alle optionalen Daten erlauben'));
    await tester.pumpAndSettle();
    expect(find.text('Bist du mindestens 14 Jahre alt?'), findsOneWidget);
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.tap(find.text('Nein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswahl speichern'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.privacy.decision.analyticsAllowed, false);
    expect(AnalyticsService.privacy.decision.diagnosticsAllowed, false);
  });
  testWidgets(
      'later eligibility change requires a new explicit optional choice',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Auswahl anpassen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Altersberechtigung'));
    await tester.tap(find.text('Altersberechtigung'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja'));
    await tester.pumpAndSettle();
    for (final widget
        in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(widget.value, false);
    }
    expect(AnalyticsService.hasCurrentConsent, false);
    await tester.tap(find.text('Auswahl speichern'));
    await tester.pumpAndSettle();
    expect(AnalyticsService.privacy.decision.ageEligibility,
        AnalyticsAgeEligibility.atLeast14);
    expect(AnalyticsService.privacy.decision.requiredOnly, true);
  });
}
