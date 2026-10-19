import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' as app;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/tutorial/tutorial_target.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_harness.dart';
import 'support/fixtures.dart';

void main() {
  setUp(() => bootstrapTestEnvironment(fixedNow: fixtureNow));
  tearDown(resetTestState);

  for (final history in <Map<String, Object>>[
    {'tutorial.v2.offered': true},
    {'tutorial.v2.completed.dashboard': true},
    {'tutorial.v2.completed.calendar': true},
    {'tutorial.v2.completed.exams': true},
    {'tutorial.v2.progress': 40},
    {'tutorial.v2.progress': -1},
    {'tutorial.v2.progress': 999},
  ]) {
    test('existing onboarding history is preserved: $history', () async {
      SharedPreferences.setMockInitialValues(history);
      final tour = TutorialService();
      expect(await tour.shouldOffer(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('tutorial.v2.progress'), isFalse);
      expect(prefs.getBool('tutorial.v2.offered'), isTrue);
      for (final key in history.keys.where((k) => k.contains('completed'))) {
        expect(prefs.getBool(key), isTrue);
      }
      expect(await tour.shouldOffer(), isFalse);
      tour.dispose();
    });
  }

  test('new installations can be offered a tour', () async {
    final tour = TutorialService();
    expect(await tour.shouldOffer(), isTrue);
    tour.dispose();
  });

  test('seven focused steps and two replay chapters remain', () {
    expect(tutorialSteps.map((s) => s.key), [
      'welcome',
      'deadlines',
      'settings',
      'tutorialHelp',
      'grades',
      'calculator',
      'calculatorTarget'
    ]);
    expect(TutorialChapter.values.map((c) => c.name), ['dashboard', 'grades']);
    expect(tutorialSteps.map((s) => s.target).toSet().length, 6);
  });

  for (final language in AppLanguage.values) {
    test('all retained explanations are translated in ${language.code}',
        () async {
      final l10n = await AppLocalizations.load(language.locale);
      for (final step in tutorialSteps) {
        for (final suffix in ['title', 'body']) {
          final key = 'tutorial.step.${step.key}.$suffix';
          expect(l10n.text(key), isNot(key));
          expect(l10n.text(key).trim(), isNotEmpty);
        }
      }
      expect(l10n.text('tutorial.back'), isNot('tutorial.back'));
    });
  }

  testWidgets('language is explicitly chosen and applied before starting',
      (tester) async {
    final store = createStore(appActions: app.actions, withMiddleware: true);
    final tour = TutorialService();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Home')));
    final starting = tour.startAll(app.navigatorKey!.currentContext!);
    await tester.pumpAndSettle();
    expect(find.text('Sprache wählen'), findsOneWidget);
    expect(tour.active, isFalse);
    await tester.tap(find.text('Italiano'));
    await tester.runAsync(() => starting);
    await tester.pumpAndSettle();
    expect(appLanguageController.language, AppLanguage.it);
    expect(tour.text('next'), 'Avanti');
    expect(store.state.settingsState.languageCode, 'it');
    await tour.cancel();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    tour.dispose();
    store.dispose();
  });

  testWidgets('skipping an unfinished action does not complete chapters',
      (tester) async {
    final store = createStore(appActions: app.actions);
    final tour = TutorialService();
    await pumpApp(tester,
        store: store, home: const Scaffold(body: Text('Home')));
    await tester.runAsync(() => tour.startAll(app.navigatorKey!.currentContext!,
        language: AppLanguage.de));
    await tester.pumpAndSettle();
    await tour.next();
    expect(tour.step.key, 'deadlines');
    expect(tour.canContinue, isFalse);
    await tour.next();
    expect(tour.step.key, 'deadlines');
    await tour.previous();
    expect(tour.step.key, 'welcome');
    await tour.cancel();
    expect(await tour.isChapterCompleted(TutorialChapter.dashboard), isFalse);
    expect(await tour.shouldOffer(), isFalse);
    await tester.runAsync(() => tour.startAll(app.navigatorKey!.currentContext!,
        language: AppLanguage.de));
    await tester.pumpAndSettle();
    expect(tour.index, 0);
    await tour.cancel();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    tour.dispose();
    store.dispose();
  });

  for (final size in [const Size(360, 640), const Size(1200, 720)]) {
    testWidgets(
        'users choose deadlines, navigate settings and calculate an example at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final initial = AppState((b) => b
        ..settingsState.showGradesDiagram = false
        ..dashboardState.allDays = ListBuilder([buildDay(date: fixtureNow)])
        ..gradesState.subjects =
            ListBuilder([buildSubject(name: 'Mathematik')]));
      final store = Store<AppState, AppStateBuilder, AppActions>(
        appReducerBuilder.build(),
        initial,
        app.actions,
        middleware: [routingMiddleware.build()],
      );
      final tour = TutorialService();
      await tester.pumpWidget(ReduxProvider(
          store: store,
          child: MaterialApp(
            navigatorKey: app.navigatorKey,
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            onGenerateRoute: (settings) => settings.name == '/gradeCalculator'
                ? MaterialPageRoute<void>(
                    builder: (_) => const GradeCalculator())
                : null,
            builder: (_, child) => TutorialHost(service: tour, child: child!),
            home: DaysContainer(),
          )));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tour.startAll(
          app.navigatorKey!.currentContext!,
          language: AppLanguage.de));
      await tester.pumpAndSettle();
      expect(tour.length, 7);
      expect(tutorialTargets.rectFor(tour.highlightTarget), isNotNull);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'deadlines');
      expect(tour.canContinue, isFalse);

      Future<void> clickTarget(String id) async {
        final finder = find.byWidgetPredicate(
            (w) => w is TutorialTarget && w.id == id,
            skipOffstage: false);
        expect(finder, findsWidgets,
            reason:
                '$id; mounted targets: ${find.byType(TutorialTarget, skipOffstage: false).evaluate().map((e) => (e.widget as TutorialTarget).id).toList()}');
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 600));
      }

      await clickTarget('dashboard-deadline');
      await tester.pumpAndSettle();
      expect(tour.highlightTarget, 'deadline-dialog');
      expect(tour.suspended, isTrue,
          reason: 'deadline dialog should use full height');
      expect(tour.canContinue, isFalse);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(tour.canContinue, isFalse);
      await clickTarget('dashboard-deadline');
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Speichern');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.text('1 Notenschluss'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Datum 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Datum 1'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((k) => k.contains('gradeDeadline')), isTrue);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'settings');
      expect(tour.canContinue, isFalse);
      if (size.width < 720) await clickTarget('navigation-menu');
      await clickTarget('navigation-settings');
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'tutorialHelp');
      expect(tour.canContinue, isFalse);
      await clickTarget('settings-tutorial');
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'grades');
      if (size.width < 720) await clickTarget('navigation-menu');
      await clickTarget('navigation-grades');
      await app.actions.gradesActions.loadFailed();
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'calculator');
      await clickTarget('grades-calculator');
      await app.actions.gradesActions.loadFailed();
      await tester.pumpAndSettle();
      expect(tour.canContinue, isFalse);
      // The app-bar target is always visible, even when the greeting scrolls.
      await tester.tap(find.byTooltip('Zielnoten-Rechner'));
      await tester.pumpAndSettle();
      expect(find.byType(TargetGradeCalculator), findsOneWidget);
      expect(tour.canContinue, isTrue);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'calculatorTarget');
      expect(tour.canContinue, isFalse);
      final calculate = find.byKey(const Key('target-calculator-calculate'),
          skipOffstage: false);
      final target = find.byKey(const Key('target-calculator-target'),
          skipOffstage: false);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.enterText(target, '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(calculate);
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(tour.canContinue, isFalse);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.enterText(target, '7');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(calculate);
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      expect(tour.highlightTarget, 'target-calculator-result');
      expect(find.text('8', skipOffstage: false), findsOneWidget);
      expect(store.state.gradesState.subjects, initial.gradesState.subjects);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'calculator');
      expect(find.byType(TargetGradeCalculator), findsNothing);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.step.key, 'calculatorTarget');
      expect(find.text('Fertig').hitTestable(), findsOneWidget);
      await tour.next();
      await tester.pumpAndSettle();
      expect(tour.active, isFalse);
      for (final chapter in TutorialChapter.values) {
        expect(await tour.isChapterCompleted(chapter), isTrue);
      }
      expect(await tour.shouldOffer(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      tour.dispose();
      store.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
