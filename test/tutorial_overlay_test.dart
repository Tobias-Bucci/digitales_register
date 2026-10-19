import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/tutorial/tutorial_overlay.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/tutorial/tutorial_target.dart';
import 'package:dr/ui/days.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tour extends TutorialService {
  bool running = true;
  int advances = 0;
  int backwards = 0;
  int position = 0;
  Map<String, String> labels = {};
  String? body;
  @override
  int get index => position;
  TutorialStep current =
      const TutorialStep(TutorialChapter.dashboard, 'test', target: 'test');
  @override
  bool get active => running;
  @override
  TutorialStep get step => current;
  @override
  int get length => 2;
  @override
  bool get canContinue => true;
  @override
  String stepTitle() => 'Test';
  @override
  String stepBody() => body ?? 'Tap the highlighted button.';
  @override
  String text(String suffix) => labels[suffix] ?? suffix;
  @override
  Future<void> next() async {
    advances++;
  }

  @override
  Future<void> previous() async {
    backwards++;
  }

  @override
  Future<void> cancel() async {
    running = false;
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

  for (final initialMessage in ['', '/cw ']) {
    testWidgets(
        '${initialMessage.isEmpty ? 'reminder' : 'classwork'} dialog gets the full space above the keyboard',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final tour = _Tour();
      await tester.pumpWidget(app(
        tour,
        Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showEnterReminderDialog(
                context,
                initialMessage: initialMessage,
              ),
              child: const Text('Add reminder'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add reminder'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.text('next'), findsNothing);
      expect(tester.getRect(find.byType(TextField)).bottom,
          lessThanOrEqualTo(500));
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('next'), findsOneWidget);
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

  testWidgets('keyboard shortcuts navigate and Escape skips', (tester) async {
    final tour = _Tour()..position = 1;
    await tester.pumpWidget(app(tour, const TextField()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(tour.backwards, 1);
    expect(tour.advances, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tour.active, isFalse);
    expect(find.text('next'), findsNothing);
  });

  for (final language in ['de', 'it', 'en', 'lld']) {
    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 480), const Size(700, 280)]) {
        testWidgets(
            'large text controls remain usable at $size in $brightness ($language)',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final l10n = await AppLocalizations.load(Locale(language));
          final tour = _Tour()
            ..position = 1
            ..body = l10n.text('tutorial.step.calculatorTarget.body')
            ..labels = {
              for (final key in ['cancel', 'back', 'finish'])
                key: l10n.text('tutorial.$key')
            };
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: TutorialHost(service: tour, child: child!),
            ),
            home: const Scaffold(body: Text('Content')),
          ));
          await tester.pumpAndSettle();
          for (final label in tour.labels.values) {
            expect(find.text(label).hitTestable(), findsOneWidget);
            final button = find.ancestor(
                of: find.text(label),
                matching: find.bySubtype<ButtonStyleButton>());
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(find.bySemanticsLabel(label), findsOneWidget);
          }
          await tester.tap(find.text(tour.text('back')));
          expect(tour.backwards, 1);
          await tester.drag(
              find.byType(SingleChildScrollView), const Offset(0, -300));
          await tester.pumpAndSettle();
          tour.current = const TutorialStep(
              TutorialChapter.dashboard, 'new-step',
              target: 'test');
          tour.refresh();
          await tester.pumpAndSettle();
          expect(
              tester
                  .state<ScrollableState>(find.byType(Scrollable))
                  .position
                  .pixels,
              0);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  }
}
