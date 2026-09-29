import 'package:dr/app_language_controller.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_harness.dart';
import 'support/fixtures.dart';

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

  testWidgets('saved reminders and classwork advance to the next task',
      (tester) async {
    final tour = TutorialService();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: app.navigatorKey,
      builder: (_, child) => TutorialHost(service: tour, child: child!),
      home: const Scaffold(body: Text('Dashboard')),
    ));
    await tester.runAsync(
      () => tour.startChapter(
        app.navigatorKey!.currentContext!,
        TutorialChapter.dashboard,
      ),
    );
    await tour.next(); // Holidays.
    await tour.next(); // Deadlines.
    for (final target in [
      'dashboard-deadline',
      'dashboard-filter',
      'dashboard-past',
    ]) {
      tour.completeRequiredAction(target);
      await tour.next();
    }
    expect(tour.step.key, 'reminders');

    final day = buildDay(date: UtcDateTime(2026, 3, 28));
    for (final entry in [
      (text: 'Bring books', id: 101, nextStep: 'deleteReminder'),
      (text: '/cw Algebra', id: 102, nextStep: 'deleteAssessment'),
    ]) {
      tour.reminderSubmitted(day, entry.text);
      expect(tour.observeDashboardDays([day]), isFalse);
      final saved = buildHomework(
        id: entry.id,
        type: HomeworkType.homework,
        subtitle: entry.text,
      );
      expect(
        tour.observeDashboardDays([
          buildDay(date: day.date, homework: [saved]),
        ]),
        isTrue,
      );
      await tester.pump();
      expect(tour.step.key, entry.nextStep);
      tour.reminderDeleted(saved.id);
      await tester.pump();
    }
    expect(tour.active, isFalse);
    await tour.cancel();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    tour.dispose();
  });
}
