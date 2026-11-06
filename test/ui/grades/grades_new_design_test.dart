import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/favorite_subject_filter.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/ui/grades_page.dart';
import 'package:dr/ui/grades_page_new.dart';
import 'package:dr/ui/grades_panels.dart';
import 'package:dr/ui/grades_subject_list.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

const _phone = Size(412, 900);

Key _open(String subject) => ValueKey('grades-subject-open-$subject');

AppState _gradesState({
  void Function(AppStateBuilder)? updates,
  List<String> favoriteSubjects = const [],
}) =>
    buildGradesPageState(favoriteSubjects: favoriteSubjects).rebuild((b) {
      b.settingsState
        ..showGradesDiagram = true
        ..showAllSubjectsAverage = true;
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      updates?.call(b);
    });

/// A subject that has a cancelled grade.
Subject _withCancelled() => buildSubject(
      id: 7,
      name: 'Geschichte',
      gradesAll: {
        Semester.first: BuiltList([
          buildGradeAll(date: UtcDateTime(2021, 1, 2), grade: 800),
        ]),
      },
      grades: {
        Semester.first: BuiltList([
          buildGradeDetail(
            id: 70,
            date: UtcDateTime(2021, 1, 2),
            grade: 800,
            name: 'Bleibt',
          ),
          buildGradeDetail(
            id: 71,
            date: UtcDateTime(2021, 1, 3),
            grade: 500,
            name: 'Weg',
          ).rebuild((b) => b.cancelled = true),
        ]),
      },
      observations: {Semester.first: BuiltList()},
    );

AppState _cancelledState() => _gradesState(
      updates: (b) => b.gradesState.subjects.add(_withCancelled()),
    );

/// Opens the grades as the app does it, below the shell of the new design.
Future<Store<AppState, AppStateBuilder, AppActions>> _pumpGrades(
  WidgetTester tester,
  AppState state, {
  Size size = _phone,
  bool newDesign = true,
  bool withMiddleware = false,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: state,
    newDesign: newDesign,
    withMiddleware: withMiddleware,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
    onGenerateRoute: (settings) => switch (settings.name) {
      '/gradesChart' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GradesChartPage(),
        ),
      '/gradeCalculator' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GradeCalculator(),
        ),
      _ => null,
    },
  );
  await settleFor(tester);
  scaffoldKey!.currentState!
      .selectContentWidget(const GradesPageContainer(), Pages.grades);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Future<void> _tapOpen(WidgetTester tester, String subject) async {
  await tester.ensureVisible(find.byKey(_open(subject)));
  await tester.pump();
  await tester.tap(find.byKey(_open(subject)));
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Future<void> _openDisplayPanel(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('grades-display-options')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('grades-display-options')));
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Future<void> _closePanel(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Iterable<ColorScheme> _allSchemes() sync* {
  for (final accent in AppAccent.values) {
    for (final brightness in Brightness.values) {
      for (final amoled in [false, true]) {
        yield AppPalette.scheme(
          brightness: brightness,
          amoled: amoled,
          accent: accent,
        );
      }
    }
  }
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    gradesPageFocusSubject.value = null;
    await resetTestState();
  });

  group('the design switch', () {
    testWidgets('the new design shows the new page', (tester) async {
      await _pumpGrades(tester, _gradesState());

      expect(find.byType(GradesPageNew), findsOneWidget);
      expect(find.byType(GradesPage), findsNothing);
      expect(find.byType(SubjectWidget), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('grades-app-header')), findsOneWidget);
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await _pumpGrades(tester, _gradesState(), newDesign: false);

      expect(find.byType(GradesPage), findsOneWidget);
      expect(find.byType(GradesPageNew), findsNothing);
      expect(find.byType(SubjectWidget), findsWidgets);
      expect(find.byType(SwitchListTile), findsNWidgets(3));
    });

    testWidgets('switching applies at once, in both directions',
        (tester) async {
      final store = await _pumpGrades(tester, _gradesState());

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(GradesPage), findsOneWidget);
      expect(find.byType(GradesPageNew), findsNothing);
      expect(find.byType(FloatingNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(GradesPageNew), findsOneWidget);
      expect(find.byType(GradesPage), findsNothing);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('shows the averages, the chart and the subjects',
        (tester) async {
      await _pumpGrades(tester, _gradesState());

      expect(find.byKey(const Key('grades-overview')), findsOneWidget);
      expect(find.byKey(const Key('grades-chart')), findsOneWidget);
      expect(find.byKey(const Key('grades-statistics')), findsOneWidget);
      expect(find.byKey(const Key('grades-calculator')), findsOneWidget);
      expect(find.byType(GradeSubjectEntry), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(_open('Fach1')),
          matching: find.text('Fach1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaves out what the settings turn off', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) => b.settingsState
            ..showGradesDiagram = false
            ..showAllSubjectsAverage = false,
        ),
      );

      expect(find.byKey(const Key('grades-overview')), findsNothing);
      expect(find.byKey(const Key('grades-chart')), findsNothing);
      expect(find.byType(GradeSubjectEntry), findsNWidgets(2));
    });

    testWidgets('the chart opens in full screen, from both places',
        (tester) async {
      await _pumpGrades(tester, _gradesState(), withMiddleware: true);

      await tester.tap(find.byKey(const Key('grades-chart-open')));
      await tester.pumpAndSettle();
      expect(find.byType(GradesChartPage), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(GradesChartPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('the calculator stays available', (tester) async {
      await _pumpGrades(tester, _gradesState(), withMiddleware: true);

      await tester.tap(find.byKey(const Key('grades-calculator')));
      await tester.pumpAndSettle();
      expect(find.byType(GradeCalculator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('history, statistics, forecast and the report card average',
        (tester) async {
      await _pumpGrades(tester, _gradesState());

      Future<void> check(Key button, Key panel) async {
        await tester.tap(find.byKey(button));
        await settleFor(tester, duration: const Duration(milliseconds: 500));
        expect(find.byKey(panel), findsOneWidget);
        await _closePanel(tester);
        expect(find.byKey(panel), findsNothing);
      }

      await check(
        const Key('grades-history'),
        const Key('grades-history-panel'),
      );
      await check(
        const Key('grades-statistics'),
        const Key('grades-statistics-panel'),
      );
      await check(
        const Key('grades-forecast-hint'),
        const Key('grades-forecast-panel'),
      );
      await tester.tap(find.byIcon(Icons.info_outline_rounded).first);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byKey(const Key('grades-certificate-panel')), findsOneWidget);
      await _closePanel(tester);
    });

    testWidgets('filters by favourite subject', (tester) async {
      await _pumpGrades(tester, _gradesState(favoriteSubjects: ['Fach2']));

      expect(find.byType(FavoriteSubjectFilter), findsOneWidget);
      await tester.ensureVisible(find.byType(FavoriteSubjectFilter));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(FavoriteSubjectFilter),
          matching: find.text('Fach2'),
        ),
      );
      await settleFor(tester);
      expect(find.byType(GradeSubjectEntry), findsOneWidget);
      expect(find.byKey(_open('Fach1')), findsNothing);
    });

    testWidgets('names excluded subjects', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) =>
              b.settingsState.ignoreForGradesAverage.replace(['Fach2']),
        ),
      );

      expect(
        find.text(
          '* Du hast dieses Fach aus dem Notendurchschnitt ausgeschlossen',
        ),
        findsOneWidget,
      );
    });
  });

  group('states', () {
    testWidgets('without grades', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(updates: (b) => b.gradesState.subjects.clear()),
      );

      expect(find.byKey(const Key('grades-empty')), findsOneWidget);
      expect(find.byKey(const Key('grades-app-header')), findsOneWidget);
      expect(find.byType(GradeSubjectEntry), findsNothing);
    });

    testWidgets('while the first grades are loading', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) => b.gradesState
            ..subjects.clear()
            ..loading = true,
        ),
      );

      expect(find.byKey(const Key('grades-loading')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(GradeSubjectEntry), findsNothing);
    });

    testWidgets('offline without grades', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) {
            b.gradesState.subjects.clear();
            b.noInternet = true;
          },
        ),
      );

      expect(find.byKey(const Key('grades-offline')), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('offline with grades says how old they are', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) {
            b.noInternet = true;
            final subjects = b.gradesState.subjects.build();
            b.gradesState.subjects.replace([
              for (final subject in subjects)
                subject.rebuild(
                  (s) => s.lastFetchedBasic = MapBuilder({
                    Semester.first: UtcDateTime.now(),
                  }),
                ),
            ]);
          },
        ),
      );

      expect(find.byKey(const Key('grades-last-fetched')), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
      expect(find.byType(GradeSubjectEntry), findsNWidgets(2));
    });

    testWidgets('offline, a subject without details cannot open',
        (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(updates: (b) => b.noInternet = true),
      );

      await tester.tap(find.byKey(_open('Fach2')));
      await settleFor(tester);
      expect(
        tester
            .widgetList<GradeSubjectEntry>(find.byType(GradeSubjectEntry))
            .where((entry) => entry.expanded),
        isEmpty,
      );
    });
  });

  group('semester', () {
    testWidgets('a segment switches it', (tester) async {
      final store = await _pumpGrades(tester, _gradesState());

      await tester
          .tap(find.byKey(ValueKey('glass-segment-${Semester.second}')));
      await settleFor(tester);
      expect(store.state.gradesState.semester, Semester.second);

      await tester.tap(find.byKey(ValueKey('glass-segment-${Semester.all}')));
      await settleFor(tester);
      expect(store.state.gradesState.semester, Semester.all);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closes the open subject', (tester) async {
      final store = await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');

      await store.actions.gradesActions.setSemester(Semester.all);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(GradeEntryRow), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segments work with the keyboard and have a full name',
        (tester) async {
      final handle = tester.ensureSemantics();
      final store = await _pumpGrades(tester, _gradesState());

      final second = find.byKey(ValueKey('glass-segment-${Semester.second}'));
      expect(find.byTooltip('2. Semester'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('2. Semester')), findsOneWidget);
      Focus.of(
        tester.element(
          find
              .descendant(of: second, matching: find.byType(GestureDetector))
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFor(tester);
      expect(store.state.gradesState.semester, Semester.second);
      handle.dispose();
    });

    testWidgets('the lens is at the selected segment', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) => b.gradesState.semester = Semester.all.toBuilder(),
        ),
      );

      final lens = find.descendant(
        of: find.byType(GlassSegmentedControl<Semester>),
        matching: find.byType(GlassLens),
      );
      final segment = find.byKey(ValueKey('glass-segment-${Semester.all}'));
      expect(tester.getCenter(lens).dx, tester.getCenter(segment).dx);
    });
  });

  group('subjects', () {
    testWidgets('opening shows the grades and closing hides them',
        (tester) async {
      await _pumpGrades(tester, _gradesState());
      expect(find.byType(GradeEntryRow), findsNothing);

      await _tapOpen(tester, 'Fach1');
      expect(find.byType(GradeEntryRow), findsNWidgets(3));
      expect(find.byType(ObservationEntryRow), findsOneWidget);
      expect(find.byType(CompetenceLine), findsOneWidget);

      await _tapOpen(tester, 'Fach1');
      expect(find.byType(GradeEntryRow), findsNothing);
    });

    testWidgets('only one subject is open at a time', (tester) async {
      await _pumpGrades(tester, _cancelledState());

      await _tapOpen(tester, 'Fach1');
      await _tapOpen(tester, 'Geschichte');
      expect(find.text('Erste Schularbeit'), findsNothing);
      expect(
        tester
            .widgetList<GradeSubjectEntry>(find.byType(GradeSubjectEntry))
            .where((entry) => entry.expanded)
            .map((entry) => entry.subject.name),
        ['Geschichte'],
      );
    });

    testWidgets('a subject without details shows that they are loading',
        (tester) async {
      await _pumpGrades(tester, _gradesState());

      await _tapOpen(tester, 'Fach2');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('a grade opens its details', (tester) async {
      await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');

      await tester.tap(find.byKey(const ValueKey('grades-grade-0')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      final panel = find.byKey(const Key('grades-grade-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('Erste Schularbeit')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('am 3. 2. erstellt')),
        findsOneWidget,
      );
      await _closePanel(tester);
      expect(panel, findsNothing);
    });

    testWidgets('an observation opens its note', (tester) async {
      await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');

      await tester.tap(find.byType(ObservationEntryRow));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byKey(const Key('grades-observation-panel')), findsOneWidget);
      expect(find.text('Notiz blabla bla'), findsOneWidget);
    });

    testWidgets('shows absences, but no empty badge', (tester) async {
      await _pumpGrades(tester, _gradesState());

      expect(find.byIcon(Icons.event_busy_outlined), findsOneWidget);
      expect(find.byTooltip('3 Absenzen'), findsOneWidget);
    });

    testWidgets('sort by type groups the grades', (tester) async {
      await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');
      expect(
          find.byKey(const ValueKey('grades-type-Schularbeit1')), findsNothing);

      await _openDisplayPanel(tester);
      await tester.tap(find.byKey(const Key('grades-sort-by-type')));
      await settleFor(tester);
      await _closePanel(tester);

      final group = find.byKey(const ValueKey('grades-type-Schularbeit1'));
      expect(group, findsOneWidget);
      expect(find.byType(GradeEntryRow), findsNWidgets(3));

      // The heading of the group says what the rows no longer repeat.
      expect(
        tester
            .widget<GradeEntryRow>(
              find.byKey(const ValueKey('grades-grade-0')),
            )
            .showType,
        isFalse,
      );

      // A group closes on its own.
      await tester.tap(
        find.descendant(of: group, matching: find.byType(InkWell)).first,
      );
      await settleFor(tester);
      expect(find.byType(GradeEntryRow), findsNWidgets(2));
    });

    testWidgets('cancelled grades show only on demand, struck through',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGrades(tester, _cancelledState());
      await _tapOpen(tester, 'Geschichte');
      expect(find.byKey(const ValueKey('grades-grade-71')), findsNothing);

      await _openDisplayPanel(tester);
      await tester.tap(find.byKey(const Key('grades-show-cancelled')));
      await settleFor(tester);
      await _closePanel(tester);

      final row = find.byKey(const ValueKey('grades-grade-71'));
      expect(row, findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(of: row, matching: find.byType(Text)).at(1),
      );
      expect(text.style?.decoration, TextDecoration.lineThrough);
      expect(
        tester
            .getSemantics(
              find.descendant(of: row, matching: find.byType(InkWell)),
            )
            .label,
        contains('gelöscht'),
      );
      handle.dispose();
    });

    testWidgets('the subject of a banner opens and leaves the rest closed',
        (tester) async {
      gradesPageFocusSubject.value = 'fach1';
      await _pumpGrades(tester, _gradesState());

      expect(gradesPageFocusSubject.value, isNull);
      expect(
        tester
            .widgetList<GradeSubjectEntry>(find.byType(GradeSubjectEntry))
            .where((entry) => entry.expanded)
            .map((entry) => entry.subject.name),
        ['Fach1'],
      );
    });

    testWidgets('a banner while the page is open scrolls below the header',
        (tester) async {
      await _pumpGrades(tester, _gradesState(), size: const Size(412, 500));

      gradesPageFocusSubject.value = 'Fach2';
      await settleFor(tester, duration: const Duration(seconds: 1));

      final header = tester.getRect(
        find.byKey(const Key('grades-app-header')),
      );
      expect(
        tester.getTopLeft(find.byKey(_open('Fach2'))).dy,
        greaterThanOrEqualTo(header.bottom),
      );
    });

    testWidgets('Enter and Space open and close a subject', (tester) async {
      await _pumpGrades(tester, _gradesState());
      await tester.ensureVisible(find.byKey(_open('Fach1')));
      await tester.pump();

      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byKey(_open('Fach1')),
                matching: find.text('Fach1'),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(GradeEntryRow), findsNWidgets(3));

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(GradeEntryRow), findsNothing);
    });

    testWidgets('reduced motion opens without an animation', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpGrades(tester, _gradesState());

      await tester.tap(find.byKey(_open('Fach1')));
      await tester.pump();
      await tester.pump();
      final transition = tester.widget<SizeTransition>(
        find.byType(SizeTransition).first,
      );
      expect(transition.sizeFactor.value, 1);

      await tester.tap(find.byKey(_open('Fach1')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(GradeEntryRow), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('colours', () {
    testWidgets('grades are coloured unless that was turned off',
        (tester) async {
      final store = await _pumpGrades(tester, _gradesState());
      bool colorized() => tester
          .widget<GradeBadge>(
            find
                .descendant(
                  of: find.byKey(_open('Fach1')),
                  matching: find.byType(GradeBadge),
                )
                .first,
          )
          .colorized;
      expect(colorized(), isTrue);

      await store.actions.settingsActions.colorGrades(false);
      await settleFor(tester);
      expect(colorized(), isFalse);
      expect(store.state.settingsState.gradeColorsTurnedOff, isTrue);
    });

    testWidgets('the switch shows what the page does', (tester) async {
      await _pumpGrades(tester, _gradesState());
      await _openDisplayPanel(tester);

      expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const Key('grades-color-grades')))
            .value,
        isTrue,
      );
    });

    testWidgets('colour is never the only signal', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGrades(
        tester,
        _gradesState(
          updates: (b) => b.gradesState.subjects.add(
            buildSubject(
              id: 9,
              name: 'Knapp',
              gradesAll: {
                Semester.first: BuiltList([
                  buildGradeAll(date: UtcDateTime(2021, 1, 2), grade: 560),
                ]),
              },
            ),
          ),
        ),
      );

      Finder row(String subject) => find.byKey(_open(subject));
      expect(
        tester.getSemantics(row('Fach1')).label,
        'Fach1, Durchschnitt 7,50, positiv, 3 Absenzen',
      );
      expect(
        tester.getSemantics(row('Fach2')).label,
        'Fach2, Durchschnitt 4,00, negativ',
      );
      expect(
        tester.getSemantics(row('Knapp')).label,
        'Knapp, Durchschnitt 5,60, knapp',
      );
      handle.dispose();
    });

    testWidgets('a grade is spoken in full', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');

      final label = tester
          .getSemantics(
            find.descendant(
              of: find.byKey(const ValueKey('grades-grade-0')),
              matching: find.byType(InkWell),
            ),
          )
          .label;
      expect(label, contains('Schularbeit1'));
      expect(label, contains('Erste Schularbeit'));
      expect(label, contains('Gewichtung 100'));
      expect(label, contains('Note 8-, positiv'));
      handle.dispose();
    });

    test('text on the glass of the page meets WCAG AA', () {
      for (final scheme in _allSchemes()) {
        // The worst case is the wash of the page below the card.
        final page = Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.42),
          scheme.surface,
        );
        final card = Color.alphaBlend(
          scheme.surfaceContainerLowest
              .withValues(alpha: DesignTokens.cardOpacity),
          page,
        );
        final hint = Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.36),
          card,
        );
        final observation = Color.alphaBlend(
          scheme.observationContainer.withValues(alpha: 0.6),
          scheme.surfaceContainerLowest,
        );
        final reason = '${scheme.brightness} ${scheme.primary}';
        for (final surface in [
          card,
          hint,
          scheme.surfaceContainerLowest,
          scheme.surfaceContainerLow,
        ]) {
          expect(
            AppPalette.contrastRatio(scheme.onSurfaceVariant, surface),
            greaterThanOrEqualTo(4.5),
            reason: reason,
          );
          expect(
            AppPalette.contrastRatio(scheme.onSurface, surface),
            greaterThanOrEqualTo(4.5),
            reason: reason,
          );
        }
        expect(
          AppPalette.contrastRatio(scheme.onObservationContainer, observation),
          greaterThanOrEqualTo(4.5),
          reason: reason,
        );
        expect(
          AppPalette.contrastRatio(
            scheme.onNoticeContainer,
            scheme.noticeContainer,
          ),
          greaterThanOrEqualTo(4.5),
          reason: reason,
        );
        for (final (text, fill) in [
          (scheme.onErrorContainer, scheme.errorContainer),
          (scheme.onWarningContainer, scheme.warningContainer),
          (scheme.onSuccessContainer, scheme.successContainer),
        ]) {
          expect(
            AppPalette.contrastRatio(text, fill),
            greaterThanOrEqualTo(4.5),
            reason: reason,
          );
        }
      }
    });
  });

  group('layouts', () {
    final side = find.byKey(const Key('dashboard-side-column'));

    for (final size in const [
      Size(1920, 1080),
      Size(1366, 768),
      Size(1280, 720),
    ]) {
      testWidgets('two columns at ${size.width} x ${size.height}',
          (tester) async {
        await _pumpGrades(tester, _gradesState(), size: size);

        expect(find.byType(AppNavigationRail), findsOneWidget);
        expect(find.byType(FloatingNavigationBar), findsNothing);
        expect(side, findsOneWidget);
        expect(
          find.descendant(
            of: side,
            matching: find.byKey(const Key('grades-overview')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: side,
            matching: find.byType(GradeSubjectEntry),
          ),
          findsNothing,
        );

        final overview =
            tester.getRect(find.byKey(const Key('grades-overview')));
        final row = tester.getRect(find.byType(GradeSubjectEntry).first);
        expect(row.left, greaterThanOrEqualTo(overview.right));
        expect(row.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));

        // The columns line up with the floating header.
        final header =
            tester.getRect(find.byKey(const Key('grades-app-header')));
        expect(overview.left, header.left);
        expect(row.right, header.right);
        // All of the side column fits, so it stays where it is.
        expect(
          tester.getRect(find.byKey(const Key('grades-statistics'))).bottom,
          lessThanOrEqualTo(size.height),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('one readable column in a narrower window', (tester) async {
      await _pumpGrades(tester, _gradesState(), size: const Size(1000, 800));

      expect(side, findsNothing);
      expect(find.byType(AppNavigationRail), findsOneWidget);
      expect(
        tester.getSize(find.byType(GradeSubjectEntry).first).width,
        lessThanOrEqualTo(DesignTokens.contentMaxWidth),
      );
    });

    testWidgets('sheets become centred panels in wide windows', (tester) async {
      await _pumpGrades(tester, _gradesState(), size: const Size(1366, 768));

      await tester.tap(find.byKey(const Key('grades-statistics')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      final panel = find.byKey(const Key('glass-sheet'));
      expect(panel, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getCenter(panel).dx, moreOrLessEquals(683, epsilon: 1));
      await _closePanel(tester);
      expect(panel, findsNothing);
    });

    testWidgets('sheets stay sheets on phones', (tester) async {
      await _pumpGrades(tester, _gradesState());

      await tester.tap(find.byKey(const Key('grades-statistics')));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('320 px, text at $scale, ${themeMode.name}',
            (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpGrades(
            tester,
            _gradesState(),
            size: const Size(320, 640),
            themeMode: themeMode,
          );
          expect(tester.takeException(), isNull);

          await _tapOpen(tester, 'Fach1');
          expect(tester.takeException(), isNull);

          await _openDisplayPanel(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the list ends above the bar', (tester) async {
      await _pumpGrades(tester, _gradesState(), size: const Size(412, 500));

      await tester.drag(
        find.byKey(const Key('grades-list')),
        const Offset(0, -2000),
      );
      await settleFor(tester);
      expect(
        tester.getRect(find.byType(GradeSubjectEntry).last).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });
  });

  group('glass', () {
    testWidgets('only the header and the bar blur, nothing in the list',
        (tester) async {
      await _pumpGrades(tester, _gradesState());
      await _tapOpen(tester, 'Fach1');

      expect(
        find.descendant(
          of: find.byKey(const Key('grades-list')),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GradesPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    testWidgets('high contrast has no blur and no light', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpGrades(tester, _gradesState());

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GradesPageNew),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is GlassSheenPainter,
          ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('without blur the header stays readable', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      addTearDown(GlassPerformance.instance.reset);
      await _pumpGrades(tester, _gradesState());

      expect(
        find.descendant(
          of: find.byType(GradesPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('grades-header-title')), findsOneWidget);
    });
  });

  group('languages', () {
    for (final (code, average) in [
      ('de', '7,50'),
      ('it', '7,50'),
      ('en', '7.50'),
      ('lld', '7,50'),
    ]) {
      testWidgets('numbers in $code', (tester) async {
        await _pumpGrades(
          tester,
          _gradesState(
            updates: (b) => b.settingsState.languageCode = code,
          ),
        );

        expect(
          find.descendant(
            of: find.byKey(_open('Fach1')),
            matching: find.text(average),
          ),
          findsOneWidget,
        );
        await _tapOpen(tester, 'Fach1');
        await tester.tap(find.byKey(const ValueKey('grades-grade-0')));
        await settleFor(tester, duration: const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('dates follow the language', (tester) async {
      await _pumpGrades(
        tester,
        _gradesState(updates: (b) => b.settingsState.languageCode = 'en'),
      );
      await _tapOpen(tester, 'Fach1');

      expect(find.text('1/2'), findsOneWidget);
    });

    test('averages are read from the text of the state', () {
      expect(parseAverageHundredths('7,64'), moreOrLessEquals(764));
      expect(parseAverageHundredths('/'), isNull);
    });
  });
}
