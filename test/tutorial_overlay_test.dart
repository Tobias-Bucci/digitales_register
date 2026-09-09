import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/tutorial/tutorial_practice.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/tutorial/tutorial_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tour extends TutorialService {
  bool running = true;
  bool completed = false;
  TutorialStep current =
      const TutorialStep(TutorialChapter.dashboard, 'test', target: 'test');
  @override
  bool get active => running;
  @override
  TutorialStep get step => current;
  @override
  int get length => 2;
  @override
  bool get canContinue => !step.requiresAction || completed;
  @override
  String stepTitle() => 'Test';
  @override
  String stepBody() => 'Tap the highlighted button.';
  @override
  String text(String suffix) => suffix;
  @override
  void completeRequiredAction(String target) {
    if (target == step.target) completed = true;
    refresh();
  }

  void refresh() => notifyListeners();
}

Widget app(_Tour tour, Widget home) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      builder: (_, child) => TutorialHost(service: tour, child: child!),
      home: Scaffold(body: home),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(360, 640),
    const Size(700, 280),
    const Size(1200, 720)
  ]) {
    testWidgets('controls never overlap app or modal at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tour = _Tour();
      var clicks = 0;
      await tester.pumpWidget(app(
          tour,
          Stack(fit: StackFit.expand, children: [
            Center(
                child: Builder(
                    builder: (context) => TutorialTarget(
                        id: 'test',
                        child: ElevatedButton(
                            child: const Text('Target'),
                            onPressed: () {
                              clicks++;
                              showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                          content: const Text('Dialog'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Save'))
                                          ]));
                            })))),
            TutorialOverlay(service: tour),
          ])));
      await tester.pumpAndSettle();
      tour.refresh();
      await tester.pumpAndSettle();
      final target = tester.getRect(find.text('Target'));
      expect(target.overlaps(tester.getRect(find.text('next'))), isFalse);
      await tester.tap(find.text('Target'));
      await tester.pumpAndSettle();
      tour.suspended = true;
      tour.refresh();
      await tester.pumpAndSettle();
      expect(clicks, 1);
      expect(find.text('next').hitTestable(), findsOneWidget);
      expect(find.text('cancel').hitTestable(), findsOneWidget);
      expect(
          tester
              .getRect(find.byType(AlertDialog))
              .overlaps(tester.getRect(find.text('next'))),
          isFalse);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resizing keeps the Navigator and follows the target',
      (tester) async {
    final tour = _Tour();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(
        tour,
        const Center(
            child: TutorialTarget(id: 'resize', child: Text('Anchor')))));
    await tester.pumpAndSettle();
    final navigator = tester.state(find.byType(Navigator));
    final before = tutorialTargets.rectFor('resize');
    tester.view.physicalSize = const Size(1200, 650);
    await tester.pumpAndSettle();
    expect(identical(navigator, tester.state(find.byType(Navigator))), isTrue);
    expect(tutorialTargets.rectFor('resize'), isNot(before));
    expect(
        tutorialTargets.rectFor('resize'), tester.getRect(find.text('Anchor')));
    tour.running = false;
    tour.refresh();
    await tester.pumpAndSettle();
    expect(find.text('next'), findsNothing);
    expect(identical(navigator, tester.state(find.byType(Navigator))), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final assessment in [false, true]) {
    testWidgets(
        'practice saves and deletes ${assessment ? 'classwork' : 'reminder'}',
        (tester) async {
      final tour = _Tour()
        ..current = TutorialStep(TutorialChapter.dashboard,
            assessment ? 'assessmentShortcuts' : 'reminders',
            target: 'tutorial-create', requiresAction: true);
      await tester.pumpWidget(app(
          tour, SingleChildScrollView(child: TutorialPractice(service: tour))));
      await tester.pumpAndSettle();
      expect(tour.canContinue, isFalse);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(tour.canContinue, isFalse);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          assessment ? '/cw example' : 'example');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      tour.completed = false;
      tour.current = TutorialStep(TutorialChapter.dashboard,
          assessment ? 'deleteAssessment' : 'deleteReminder',
          target: 'tutorial-delete', requiresAction: true);
      tour.refresh();
      await tester.pumpAndSettle();
      final rect = tutorialTargets.rectFor('tutorial-delete');
      expect(rect, isNotNull);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(tour.canContinue, isTrue);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
