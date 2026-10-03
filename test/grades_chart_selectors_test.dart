import 'package:built_collection/built_collection.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/chart_legend_entry_container.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final early = UtcDateTime(2026, 1, 10);
  final late = UtcDateTime(2026, 4, 10);
  final firstGrade = buildGradeAll(date: early, grade: 725, type: 'Test');
  final secondGrade = buildGradeAll(date: late, grade: 850, type: 'Mündlich');
  final configuredTheme = SubjectTheme((b) => b
    ..color = 0xFFFF0000
    ..thick = 3);

  AppState stateWith(Subject subject,
      {Semester? semester, bool loading = false}) {
    return AppState((b) => b.gradesState
      ..subjects = ListBuilder<Subject>([subject])
      ..semester = (semester ?? Semester.all).toBuilder()
      ..loading = loading);
  }

  void expectNoAverage(AppSelectors selectors, AppState state) {
    expect(overallGradeAverage(state), isNull);
    expect(selectors.allSubjectsAverage(state), '/');
    expect(selectors.certificateAverage(state), '/');
  }

  for (final loading in [false, true]) {
    test('initial/empty subjects are safe with loading=$loading', () {
      final selectors = AppSelectors();
      final state = AppState((b) => b.gradesState.loading = loading);
      expect(selectors.chartGraphs(state), isEmpty);
      expect(selectors.hasGradesData(state), isFalse);
      expectNoAverage(selectors, state);
      expect(
          identical(selectors.chartGraphs(state), selectors.chartGraphs(state)),
          isTrue);
    });
  }

  test('missing theme retains real grades and uses the same legend fallback',
      () {
    final selectors = AppSelectors();
    final state = stateWith(buildSubject(name: 'Neu', gradesAll: {
      Semester.first: BuiltList<GradeAll>([firstGrade]),
    }));
    final graphs = selectors.chartGraphs(state);
    expect(graphs.keys.single.name, 'Neu');
    expect(graphs.keys.single.grades[early]?.item1, 725);
    expect(graphs.keys.single.grades[early]?.item2, 'Test');
    expect(graphs.values.single.color, 0xFF9E9E9E);
    expect(graphs.values.single.thick, 1);
    expect(ChartLegendEntryVM.from(state, 'Neu').config, graphs.values.single);
    // A legend entry may outlive its theme during a state reset.
    expect(ChartLegendEntryVM.from(AppState(), 'Neu').config,
        graphs.values.single);
  });

  test('partial themes preserve configured and hidden themes', () {
    final hidden = configuredTheme.rebuild((b) => b.thick = 0);
    final state = AppState((b) {
      b.gradesState.subjects = ListBuilder<Subject>([
        for (final name in ['Configured', 'Hidden', 'Missing'])
          buildSubject(name: name, gradesAll: {
            Semester.first: BuiltList<GradeAll>([firstGrade]),
          }),
      ]);
      b.settingsState.subjectThemes = MapBuilder<String, SubjectTheme>({
        'Configured': configuredTheme,
        'Hidden': hidden,
      });
    });
    final graphs = AppSelectors().chartGraphs(state);
    final themes = {
      for (final entry in graphs.entries) entry.key.name: entry.value
    };
    expect(themes['Configured'], configuredTheme);
    expect(themes['Hidden'], hidden);
    expect(themes['Missing']?.thick, 1);
    expect(state.settingsState.subjectThemes.containsKey('Missing'), isFalse);
  });

  final incompleteSubjects = <String, Subject>{
    'missing semester': buildSubject(name: 'Fach'),
    'empty semester': buildSubject(name: 'Fach', gradesAll: {
      Semester.first: BuiltList<GradeAll>(),
    }),
    'null and cancelled grades': buildSubject(name: 'Fach', gradesAll: {
      Semester.first: BuiltList<GradeAll>([
        firstGrade.rebuild((b) => b.grade = null),
        secondGrade.rebuild((b) => b.cancelled = true),
      ]),
    }),
  };
  for (final entry in incompleteSubjects.entries) {
    for (final semester in [Semester.first, Semester.second, Semester.all]) {
      test('${entry.key} is safe in ${semester.name}', () {
        final selectors = AppSelectors();
        final state = stateWith(entry.value, semester: semester, loading: true);
        // Keep empty subject series for compatibility; invent no chart points.
        expect(selectors.chartGraphs(state).keys.single.grades, isEmpty);
        expectNoAverage(selectors, state);
        expect(entry.value.basicGrades(semester),
            anyOf(isNull, isA<List<GradeAll>>()));
        expect(entry.value.detailEntries(semester), isNull);
        // hasGradesData distinguishes fetched semester data from missing data.
        final hasData = semester == Semester.all
            ? entry.value.gradesAll.isNotEmpty
            : entry.value.gradesAll.containsKey(semester);
        expect(selectors.hasGradesData(state), hasData);
      });
    }
  }

  test(
      'cache follows data, themes and semester while retaining data on refresh',
      () {
    final selectors = AppSelectors();
    final initial = AppState();
    expect(selectors.chartGraphs(initial), isEmpty);
    final loaded = stateWith(buildSubject(name: 'Fach', gradesAll: {
      Semester.second: BuiltList<GradeAll>([secondGrade]),
      Semester.first: BuiltList<GradeAll>([
        firstGrade,
        secondGrade.rebuild((b) => b.grade = null),
        secondGrade.rebuild((b) => b.cancelled = true),
      ]),
    }));
    final graphs = selectors.chartGraphs(loaded);
    expect(graphs.keys.single.grades.keys, [early, late]);
    expect(graphs.keys.single.grades.values.map((g) => g.item1), [725, 850]);
    expect(selectors.allSubjectsAverage(loaded), '7,88');
    expect(selectors.certificateAverage(loaded), '8,00');
    expect(identical(selectors.chartGraphs(loaded), graphs), isTrue);
    expect(
        identical(
            selectors.chartGraphs(
                loaded.rebuild((b) => b.gradesState.loading = true)),
            graphs),
        isTrue);
    final themed = loaded.rebuild(
        (b) => b.settingsState.subjectThemes['Fach'] = configuredTheme);
    expect(selectors.chartGraphs(themed).values.single, configuredTheme);
    final firstOnly = themed
        .rebuild((b) => b.gradesState.semester = Semester.first.toBuilder());
    expect(selectors.chartGraphs(firstOnly).keys.single.grades.keys, [early]);
    expect(selectors.chartGraphs(initial), isEmpty);
    expectNoAverage(selectors, initial);
  });

  test('single-semester points are chronological even for unsorted data', () {
    final state = stateWith(
        buildSubject(name: 'Fach', gradesAll: {
          Semester.first: BuiltList<GradeAll>([secondGrade, firstGrade]),
        }),
        semester: Semester.first);
    expect(AppSelectors().chartGraphs(state).keys.single.grades.keys,
        [early, late]);
    expect(state.gradesState.subjects.single.gradesAll[Semester.first]?.first,
        secondGrade);
  });

  test('incomplete detailed grades return no entries until both lists exist',
      () {
    final subject = buildSubject(name: 'Fach', grades: {
      Semester.first: BuiltList<GradeDetail>(),
    });
    expect(subject.detailEntries(Semester.first), isNull);
    final complete = subject.rebuild(
        (b) => b.observations[Semester.first] = BuiltList<Observation>());
    expect(complete.detailEntries(Semester.first), isEmpty);
  });
}
