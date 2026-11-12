import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show nestedNavKey, scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:dr/ui/grades_chart_page_new.dart';
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

const _phone = Size(360, 640);
const _wide = Size(1280, 800);

AppState _state({
  String languageCode = 'de',
  void Function(AppStateBuilder)? updates,
}) =>
    buildGradesPageState().rebuild((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
      updates?.call(b);
    });

/// A subject for the import and the target grade calculator.
Subject _math(List<GradeAll> grades) => buildSubject(
      id: 77,
      name: 'Mathematik',
      gradesAll: {Semester.first: BuiltList(grades)},
    );

AppState _mathState({int assessments = 0}) => _state(
      updates: (b) => b
        ..gradesState.subjects.replace([
          _math([
            buildGradeAll(date: UtcDateTime(2026, 4, 3), grade: 700),
            buildGradeAll(date: UtcDateTime(2026, 4, 2), grade: 800),
          ]),
        ])
        ..dashboardState.allDays = ListBuilder<Day>([
          for (var i = 0; i < assessments; i++)
            buildDay(
              date: UtcDateTime(2099, 1, 2).add(Duration(days: i)),
              homework: [
                buildHomework(
                  id: 100 + i,
                  title: 'Schularbeit',
                  subtitle: 'Thema $i',
                  label: 'Mathematik',
                  type: HomeworkType.gradeGroup,
                  warning: true,
                ),
              ],
            ),
        ]),
    );

/// Opens [page] on top of the grades page inside the shell, as the routing of
/// the new design does it.
Future<Store<AppState, AppStateBuilder, AppActions>> _pumpTool(
  WidgetTester tester,
  Widget page, {
  AppState? state,
  Size size = _phone,
  bool newDesign = true,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: state ?? _state(),
    newDesign: newDesign,
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
  scaffoldKey!.currentState!
      .selectContentWidget(const GradesPageContainer(), Pages.grades);
  await settleFor(tester);
  unawaited(nestedNavKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  ));
  await settleFor(tester, duration: const Duration(milliseconds: 600));
  return store;
}

bool _inShell(WidgetTester tester, Finder finder) =>
    ResponsiveNavigationScope.isActive(tester.element(finder));

/// Blur only in the header and the navigation.
void _expectBlurOnlyInHeader(WidgetTester tester, Key header) {
  final allowed = [
    header,
    const Key('app-navigation-bar'),
    const Key('app-navigation-rail'),
  ];
  expect(
    find.descendant(
        of: find.byKey(header), matching: find.byType(BackdropFilter)),
    findsOneWidget,
  );
  for (final element in find.byType(BackdropFilter).evaluate()) {
    final allowedPlace = allowed.any(
      (key) => find
          .ancestor(
              of: find.byWidget(element.widget), matching: find.byKey(key))
          .evaluate()
          .isNotEmpty,
    );
    expect(allowedPlace, isTrue);
  }
}

Future<void> _addGrade(WidgetTester tester, String grade, String weight) async {
  final add = find.byKey(const Key('grade-calculator-add'));
  await tester.tap(
    add.evaluate().isEmpty ? find.text('Note hinzufügen').first : add,
  );
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  final panel = find.byKey(const Key('grade-calculator-add-panel'));
  expect(panel, findsOneWidget);
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('grade-calculator-add-grade')),
      matching: find.byType(TextField),
    ),
    grade,
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(const Key('grade-calculator-add-weight')),
      matching: find.byType(TextField),
    ),
    weight,
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('grade-calculator-add-confirm')));
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Future<void> _selectMath(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('target-calculator-subject')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mathematik').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('the design switch', () {
    testWidgets('the chart in the shell is the new page', (tester) async {
      await _pumpTool(tester, const GradesChartPage());
      expect(find.byType(GradesChartPageNew), findsOneWidget);
      expect(find.byKey(const Key('grades-chart-header')), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      expect(_inShell(tester, find.byType(GradesChartPageNew)), isTrue);
    });

    testWidgets('Legacy keeps the old pages', (tester) async {
      await _pumpTool(tester, const GradeCalculator(), newDesign: false);
      expect(find.byType(Greeting), findsOneWidget);
      expect(find.byKey(const Key('grade-calculator-header')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pumpTool(tester, const GradesChartPage(), newDesign: false);
      expect(find.byType(GradesChartPageNew), findsNothing);
      expect(find.text('Legende'), findsOneWidget);
    });

    testWidgets('the calculators switch with the design at once',
        (tester) async {
      final store = await _pumpTool(tester, const GradeCalculator());
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(Greeting), findsOneWidget);
      expect(tester.takeException(), isNull);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
    });
  });

  group('chart', () {
    testWidgets('chart and folded legend on a phone', (tester) async {
      final store = await _pumpTool(tester, const GradesChartPage());
      expect(find.byKey(const Key('grades-chart-full')), findsOneWidget);
      expect(find.byKey(const Key('grades-chart-legend')), findsOneWidget);
      expect(find.byKey(const Key('grades-chart-legend-list')), findsNothing);

      await tester.tap(find.byKey(const Key('grades-chart-legend-toggle')));
      await settleFor(tester);
      expect(find.text('Fach1'), findsOneWidget);
      expect(find.text('Fach2'), findsOneWidget);
      // The chart keeps most of the height.
      expect(
        tester.getSize(find.byKey(const Key('grades-chart-full'))).height,
        greaterThan(200),
      );

      // The slider hides a subject, as in Legacy.
      final slider = find.descendant(
        of: find
            .ancestor(
              of: find.text('Fach1'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Slider),
      );
      await tester.drag(slider, const Offset(-400, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await settleFor(tester);
      expect(store.state.settingsState.subjectThemes['Fach1']?.thick, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the legend stands beside the chart on a phone held sideways',
        (tester) async {
      await _pumpTool(
        tester,
        const GradesChartPage(),
        size: const Size(915, 412),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('grades-chart-legend-toggle')), findsNothing);
      expect(find.text('Fach1'), findsOneWidget);
      final chart = tester.getRect(find.byKey(const Key('grades-chart-full')));
      final legend =
          tester.getRect(find.byKey(const Key('grades-chart-legend')));
      expect(legend.left, greaterThan(chart.right));
      expect(chart.height, greaterThan(250));
    });

    testWidgets('without grades a state card', (tester) async {
      await _pumpTool(
        tester,
        const GradesChartPage(),
        state: _state(updates: (b) => b.gradesState.subjects.clear()),
      );
      expect(find.byKey(const Key('grades-chart-empty')), findsOneWidget);
    });

    testWidgets('a tap shows the details in the colours of the scheme',
        (tester) async {
      await _pumpTool(tester, const GradesChartPage(), size: _wide);
      expect(
        find.text('Tippe auf das Diagramm, um Details zu sehen'),
        findsOneWidget,
      );
      final chart = tester.getRect(find.byKey(const Key('grades-chart-full')));
      await tester.tapAt(Offset(chart.right - 30, chart.top + 150));
      await settleFor(tester);
      expect(find.textContaining('Fach1 – Schularbeit3'), findsOneWidget);
    });
  });

  group('grade calculator', () {
    testWidgets('welcome card with the three ways to start', (tester) async {
      await _pumpTool(tester, const GradeCalculator());
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
      expect(find.byKey(const Key('grade-calculator-import')), findsOneWidget);
      expect(
        find.byKey(const Key('grade-calculator-open-target')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('grade-calculator-target')), findsOneWidget);
    });

    testWidgets('a grade is added in a sheet and checked as in Legacy',
        (tester) async {
      await _pumpTool(tester, const GradeCalculator());
      await tester.tap(find.text('Note hinzufügen'));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(GlassSheet), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('grade-calculator-add-grade')),
          matching: find.byType(TextField),
        ),
        'abc',
      );
      await tester.pump();
      expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const Key('grade-calculator-add-confirm')))
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFor(tester, duration: const Duration(milliseconds: 500));

      await _addGrade(tester, '6', '1');
      await _addGrade(tester, '7', '15');
      // The same rounding as Legacy: 6.9375 is 6,94.
      expect(find.text('6,94'), findsOneWidget);
      expect(find.text('2 Noten'), findsOneWidget);
      expect(find.byKey(const Key('grade-calculator-grades')), findsOneWidget);

      await tester.tap(find.byKey(const Key('grade-calculator-remove')).first);
      await settleFor(tester);
      expect(find.text('7,00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('grade-calculator-remove')));
      await settleFor(tester);
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
    });

    testWidgets('editing a row changes the average', (tester) async {
      await _pumpTool(tester, const GradeCalculator());
      await _addGrade(tester, '6', '100');
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const Key('grade-calculator-grades')),
              matching: find.byType(TextField),
            )
            .last,
        '8,5',
      );
      await tester.pump();
      expect(find.text('8,50'), findsWidgets);
    });

    testWidgets('grades are imported in a sheet', (tester) async {
      await _pumpTool(tester, const GradeCalculator(), state: _mathState());
      await tester.tap(find.byKey(const Key('grade-calculator-import')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('grade-calculator-import-panel')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
                find.byKey(const Key('grade-calculator-import-confirm')))
            .onPressed,
        isNull,
      );
      await tester
          .tap(find.byKey(const Key('grade-calculator-import-subject')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematik').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('glass-segment-${Semester.first}')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('grade-calculator-import-confirm')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));

      expect(find.text('2 Noten'), findsOneWidget);
      expect(find.text('7,50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the target calculator opens in the same frame',
        (tester) async {
      await _pumpTool(tester, const GradeCalculator());
      await tester.tap(find.byKey(const Key('grade-calculator-target')));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byKey(const Key('target-calculator-header')), findsOneWidget);
      expect(
        _inShell(tester, find.byType(TargetGradeCalculator)),
        isTrue,
      );
      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
    });
  });

  group('target grade calculator', () {
    testWidgets('calculates with the inputs in cards', (tester) async {
      await _pumpTool(
        tester,
        const TargetGradeCalculator(),
        state: _mathState(),
        size: const Size(800, 2000),
      );
      await _selectMath(tester);
      expect(
          find.byKey(const Key('target-calculator-current')), findsOneWidget);
      expect(find.textContaining('7 · 100%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('target-calculator-calculate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('target-calculator-error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('target-calculator-add-future')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('target-calculator-target')), '8');
      await tester.tap(find.byKey(const Key('target-calculator-calculate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('target-calculator-error')), findsNothing);
      expect(find.byKey(const Key('target-calculator-result')), findsOneWidget);
      expect(find.textContaining('Dein Ziel'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a grade not in the register yet is added in a sheet',
        (tester) async {
      await _pumpTool(
        tester,
        const TargetGradeCalculator(),
        state: _mathState(),
        size: const Size(800, 2000),
      );
      await _selectMath(tester);
      await tester.tap(find.byKey(const Key('target-calculator-add-existing')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      await tester.enterText(
          find.byKey(const Key('target-calculator-existing-grade')), '12');
      await tester
          .tap(find.byKey(const Key('target-calculator-existing-confirm')));
      await tester.pump();
      expect(find.textContaining('außerhalb des gültigen Bereichs'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('target-calculator-existing-grade')), '9');
      await tester
          .tap(find.byKey(const Key('target-calculator-existing-confirm')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.textContaining('9 · 100%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the calendar assessment limit is unchanged', (tester) async {
      await _pumpTool(
        tester,
        const TargetGradeCalculator(),
        state: _mathState(assessments: 60),
        size: const Size(800, 9000),
      );
      await _selectMath(tester);
      expect(find.byKey(const Key('target-calculator-calendar-limited')),
          findsOneWidget);
      expect(
          find.textContaining('nur die nächsten 20 von 60 kommenden Prüfungen'),
          findsOneWidget);
      final shown = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>)
              .value
              .startsWith('target-calculator-calendar-assessment-'));
      expect(shown, findsNWidgets(20));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('target-calculator-add-future')));
        await tester.pumpAndSettle();
      }
      expect(shown, findsNWidgets(17));
    });
  });

  group('layouts, themes and access', () {
    for (final (name, page, header) in [
      ('chart', const GradesChartPage(), 'grades-chart-header'),
      ('calculator', const GradeCalculator(), 'grade-calculator-header'),
      ('target', const TargetGradeCalculator(), 'target-calculator-header'),
    ]) {
      for (final size in [_phone, _wide]) {
        for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
          testWidgets('$name at $size in ${themeMode.name}', (tester) async {
            await _pumpTool(
              tester,
              page,
              size: size,
              themeMode: themeMode,
              amoled: themeMode == ThemeMode.dark,
            );
            expect(tester.takeException(), isNull);
            expect(find.byKey(Key(header)), findsOneWidget);
            _expectBlurOnlyInHeader(tester, Key(header));
          });
        }
      }

      testWidgets('$name at 320 px with text at 200 %', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpTool(tester, page, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name in high contrast has no blur', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpTool(tester, page);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$name with reduced motion', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpTool(tester, page);
        expect(tester.takeException(), isNull);
      });

      for (final language in ['it', 'en', 'lld']) {
        testWidgets('$name in $language', (tester) async {
          await _pumpTool(tester, page, state: _state(languageCode: language));
          expect(tester.takeException(), isNull);
          expect(find.textContaining('.title'), findsNothing);
          expect(find.textContaining('ui.'), findsNothing);
        });
      }
    }
  });
}
