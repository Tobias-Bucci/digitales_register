import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/extras_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);

/// The entries in their order, with the texts they show.
const _entries = [
  (
    'extras-class-register',
    'sidebar.classRegister',
    'extras.classRegister.subtitle'
  ),
  ('extras-homework-summary', 'sidebar.homework', 'extras.homework.subtitle'),
  ('extras-certificate', 'sidebar.certificate', 'extras.certificate.subtitle'),
  ('extras-absences', 'sidebar.absences', 'extras.absences.subtitle'),
  (
    'extras-course-materials',
    'sidebar.courseMaterials',
    'extras.courseMaterials.subtitle',
  ),
];

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

/// Opens Extras as the navigation does, below the shell of the new design.
/// [page] replaces the container, to see which entry calls what.
Future<void> _pumpExtras(
  WidgetTester tester, {
  Widget page = const ExtrasPageContainer(),
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  String languageCode = 'de',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(languageCode: languageCode),
    newDesign: true,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
    darkTheme: themeController.buildTheme(
      brightness: Brightness.dark,
      amoledMode: amoled,
    ),
  );
  await settleFor(tester);
  scaffoldKey!.currentState!.selectContentWidget(page, Pages.extras);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Finder _entry(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('content', () {
    testWidgets('a glass header without a back button', (tester) async {
      await _pumpExtras(tester);

      expect(find.byType(ExtrasPage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byKey(const Key('extras-app-header')), findsOneWidget);
      expect(find.byType(GlassPageHeader), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.text('Extras'), findsOneWidget);
    });

    testWidgets('the entries are glass tiles, in their order', (tester) async {
      await _pumpExtras(tester);

      double? previous;
      for (final (key, _, _) in _entries) {
        expect(
          find.descendant(of: _entry(key), matching: find.byType(GlassTile)),
          findsOneWidget,
        );
        final top = tester.getRect(_entry(key)).top;
        if (previous != null) expect(top, greaterThan(previous));
        previous = top;
      }
    });

    testWidgets('each entry opens its page', (tester) async {
      final opened = <String>[];
      await _pumpExtras(
        tester,
        page: ExtrasPage(
          showClassRegister: () => opened.add('classRegister'),
          showHomeworkSummary: () => opened.add('homeworkSummary'),
          showCertificate: () => opened.add('certificate'),
          showAbsences: () => opened.add('absences'),
          showCourseMaterials: () => opened.add('courseMaterials'),
        ),
      );

      for (final (key, _, _) in _entries) {
        await tester.tap(_entry(key));
        await tester.pump();
      }
      expect(opened, [
        'classRegister',
        'homeworkSummary',
        'certificate',
        'absences',
        'courseMaterials',
      ]);
    });

    testWidgets('each entry is one button for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpExtras(tester);

      final l10n = tester.element(find.byType(ExtrasPage)).l10n;
      for (final (key, title, subtitle) in _entries) {
        expect(
          tester.getSemantics(
            find.descendant(of: _entry(key), matching: find.byType(InkWell)),
          ),
          isSemantics(
            label: '${l10n.text(title)}, ${l10n.text(subtitle)}',
            isButton: true,
            hasTapAction: true,
          ),
        );
      }
      expect(
        tester.getSemantics(find.byKey(const Key('extras-header-title'))),
        isSemantics(label: l10n.text('extras.title'), isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('the keyboard reaches every entry', (tester) async {
      final opened = <String>[];
      await _pumpExtras(
        tester,
        page: ExtrasPage(
          showClassRegister: () => opened.add('classRegister'),
          showHomeworkSummary: () => opened.add('homeworkSummary'),
          showCertificate: () => opened.add('certificate'),
          showAbsences: () => opened.add('absences'),
          showCourseMaterials: () => opened.add('courseMaterials'),
        ),
      );

      final first = tester.widget<InkWell>(
        find.descendant(
          of: _entry('extras-class-register'),
          matching: find.byType(InkWell),
        ),
      );
      expect(first.mouseCursor, NewDesignTheme.clickCursor);

      // Tab until the first entry has the focus, then open it with Enter.
      for (var i = 0; i < 30 && opened.isEmpty; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context;
        if (focus != null &&
            find
                .descendant(
                  of: _entry('extras-class-register'),
                  matching: find.byWidget(focus.widget),
                )
                .evaluate()
                .isNotEmpty) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
        }
      }
      expect(opened, ['classRegister']);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the list ends above the bar', (tester) async {
      await _pumpExtras(tester, size: const Size(360, 400));

      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      final header = tester.getRect(find.byKey(const Key('extras-app-header')));
      expect(header.left, 0);
      expect(header.top, 0);
      expect(
        tester.getRect(_entry('extras-class-register')).top,
        greaterThanOrEqualTo(header.bottom),
      );

      await tester.drag(
        find.byKey(const Key('extras-list')),
        const Offset(0, -2000),
      );
      await settleFor(tester);
      expect(
        tester.getRect(_entry('extras-course-materials')).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });

    for (final size in const [
      Size(1280, 800),
      Size(1920, 1080),
      Size(800, 600)
    ]) {
      testWidgets(
          'at ${size.width} x ${size.height} the header floats above the list',
          (tester) async {
        await _pumpExtras(tester, size: size);

        expect(find.byType(AppNavigationRail), findsOneWidget);
        final header =
            tester.getRect(find.byKey(const Key('extras-app-header')));
        final entry = tester.getRect(_entry('extras-class-register'));
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(entry.left, header.left);
        expect(entry.right, header.right);
        expect(entry.top, greaterThanOrEqualTo(header.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('320 px, text at $scale, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpExtras(
            tester,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );

          expect(tester.takeException(), isNull);
          for (final (key, _, _) in _entries) {
            expect(tester.getSize(_entry(key)).width,
                320 - 2 * DesignTokens.gutter);
            expect(
                tester.getSize(_entry(key)).height, greaterThanOrEqualTo(48));
          }
        });
      }
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pumpExtras(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('extras-list')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('high contrast has no blur and no light, ${themeMode.name}',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpExtras(tester, themeMode: themeMode);

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ExtrasPage),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint && widget.painter is GlassSheenPainter,
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without blur the header stays readable', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      addTearDown(GlassPerformance.instance.reset);
      await _pumpExtras(tester);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('extras-header-title')), findsOneWidget);
    });
  });

  group('languages', () {
    for (final (code, title) in const [
      ('de', 'Extras'),
      ('it', 'Extra'),
      ('en', 'Extras'),
      ('lld', null),
    ]) {
      testWidgets('in $code', (tester) async {
        await _pumpExtras(tester,
            languageCode: code, size: const Size(320, 640));

        final l10n = tester.element(find.byType(ExtrasPage)).l10n;
        final header = tester.widget<Text>(
          find.byKey(const Key('extras-header-title')),
        );
        expect(header.data, title ?? l10n.text('extras.title'));
        for (final (key, label, subtitle) in _entries) {
          expect(
            find.descendant(
              of: _entry(key),
              matching: find.text(l10n.text(label)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _entry(key),
              matching: find.text(l10n.text(subtitle)),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
