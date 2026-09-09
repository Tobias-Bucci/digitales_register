import 'package:dr/app_language_controller.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_harness.dart';

void main() {
  setUp(() => bootstrapTestEnvironment(
      sharedPreferences: {'tutorial.v2.progress': 17}));
  tearDown(resetTestState);

  testWidgets('full start resets progress and persists the app language',
      (tester) async {
    final store = createStore(appActions: app.actions, withMiddleware: true);
    final tour = TutorialService();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: app.navigatorKey,
      builder: (_, child) => TutorialHost(service: tour, child: child!),
      home: const Scaffold(body: Text('Dashboard')),
    ));
    await tester.runAsync(() => tour.startAll(app.navigatorKey!.currentContext!,
        language: AppLanguage.it));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tour.index, 0);
    expect(tour.step.key, 'welcome');
    expect(store.state.settingsState.languageCode, 'it');
    expect(appLanguageController.language, AppLanguage.it);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appLanguage'), 'it');
    await tour.next();
    expect(tour.index, 1);
    await tour.cancel();
    expect(prefs.getInt('tutorial.v2.progress'), 1);
    await tester.runAsync(() => tour.startAll(app.navigatorKey!.currentContext!,
        language: AppLanguage.en));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tour.index, 0);
    expect(prefs.getInt('tutorial.v2.progress'), isNull);
    expect(prefs.getString('appLanguage'), 'en');
    await tour.cancel();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    tour.dispose();
    store.dispose();
  });
}
