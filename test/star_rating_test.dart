import 'dart:convert';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:dr/star_rating.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'parse_test.dart' as fixtures;
import 'parse_webpage_test.dart' as webpage;

void main() {
  setUpAll(() => initializeDateFormatting());
  for (final scale in [5, 6, 7, 12, 1000]) {
    test('reads school scale $scale from existing webpage structure', () {
      final config = Wrapper.parseConfig(webpage.source.replaceFirst(
          'competence_stars_scale: 5', 'competence_stars_scale: $scale'));
      expect(config.competenceStarsScale, scale);
      final restored = serializers.deserializeWith(Config.serializer,
          serializers.serializeWith(Config.serializer, config))!;
      expect(restored.competenceStarsScale, scale);
    });
  }
  test('missing, malformed and conflicting school metadata remain unknown', () {
    for (final raw in [
      'null',
      'false',
      '0',
      '-1',
      '6.5',
      'NaN',
      'Infinity',
      '{}',
      '[]',
      '"bad"',
      '99999999999999999999'
    ]) {
      expect(
          Wrapper.parseConfig(webpage.source.replaceFirst(
                  'competence_stars_scale: 5', 'competence_stars_scale: $raw'))
              .competenceStarsScale,
          isNull,
          reason: raw);
    }
    expect(
        Wrapper.parseConfig(
                webpage.source.replaceFirst('competence_stars_scale: 5,', ''))
            .competenceStarsScale,
        isNull);
    expect(
        Wrapper.parseConfig(webpage.source.replaceFirst(
                'competence_stars_scale: 5,',
                'competence_stars_scale: 5, competence_stars_scale: 6,'))
            .competenceStarsScale,
        isNull);
    for (final raw in ['"6"', "'7'", '8.0']) {
      expect(
          Wrapper.parseConfig(webpage.source.replaceFirst(
                  'competence_stars_scale: 5', 'competence_stars_scale: $raw'))
              .competenceStarsScale,
          isNotNull);
    }
  });

  test('whole ratings are accepted without imposing a five-star limit', () {
    for (final value in [0, 5, 6, 7, 12, 1000]) {
      expect(parseStarCount(value), value);
      expect(parseStarCount('$value.00'), value);
      expect(parseStarCount(value.toDouble()), value);
    }
    for (final value in [
      null,
      true,
      [],
      {},
      -1,
      '-1',
      'bad',
      'NaN',
      double.nan,
      double.infinity,
      4.9,
      '4.9',
      1e30
    ]) {
      expect(parseStarCount(value), isNull, reason: '$value');
    }
  });

  late Store<AppState, AppStateBuilder, AppActions> store;
  setUp(() {
    store = Store(appReducerBuilder.build(), AppState(), AppActions());
    store.actions.gradesActions.loaded(SubjectsLoadedPayload((b) => b
      ..data = fixtures.subjectsPayload
      ..semester = Semester.first.toBuilder()));
  });

  GradeDetail load(Object? competences) {
    final original =
        (fixtures.subjectDetailsPayload['grades'] as List).first as Map;
    store.actions.gradesActions
        .detailsLoaded(SubjectDetailLoadedPayload((b) => b
          ..data = {
            'grades': [
              {...original, 'competences': competences}
            ],
            'observations': []
          }
          ..subject = store.state.gradesState.subjects.first.toBuilder()
          ..semester = Semester.first.toBuilder()));
    return store
        .state.gradesState.subjects.first.grades[Semester.first]!.single;
  }

  test('real detail response retains ordinary grades and nullable competencies',
      () {
    final grade = load([
      for (final value in ['4', '6.00', 7, 12, null, -1, '4.5', {}, 'NaN'])
        {'typeName': 'Reading', 'grade': value},
      null,
      false,
      {},
      {'typeName': [], 'grade': 3},
    ]);
    expect(grade.grade, 750);
    expect(grade.competences.map((c) => c.grade),
        [4, 6, 7, 12, null, null, null, null, null, null, null, null, 3]);
    final restored = serializers.deserializeWith(GradeDetail.serializer,
        serializers.serializeWith(GradeDetail.serializer, grade))!;
    expect(restored, grade);
  });

  test('missing, empty, encoded or malformed lists never break grade loading',
      () {
    for (final value in [null, [], false, {}, 'bad', '{}', 'null', 42]) {
      expect(load(value).competences, isEmpty);
      expect(load(value).grade, 750);
    }
    expect(
        load(jsonEncode([
          {'typeName': 'Reading', 'grade': '7'}
        ])).competences.single.grade,
        7);
    final original =
        (fixtures.subjectDetailsPayload['grades'] as List).first as Map;
    final missing = Map.of(original)..remove('competences');
    store.actions.gradesActions
        .detailsLoaded(SubjectDetailLoadedPayload((b) => b
          ..data = {
            'grades': [missing],
            'observations': []
          }
          ..subject = store.state.gradesState.subjects.first.toBuilder()
          ..semester = Semester.first.toBuilder()));
    expect(
        store.state.gradesState.subjects.first.grades[Semester.first]!.single
            .competences,
        isEmpty);
  });

  test('encoded competence objects preserve existing parser support', () {
    final grade = load([
      jsonEncode({'typeName': 'Reading', 'grade': '6.0'}),
      'bad',
      'null',
      '[]',
    ]);
    expect(grade.competences.map((c) => c.grade), [6, null, null, null]);
  });

  test('school scales are replaced and never inferred from high ratings', () {
    load([
      {'typeName': 'Reading', 'grade': '12'}
    ]);
    for (final raw in ['7', '5', 'null', '6']) {
      store.actions.setConfig(Wrapper.parseConfig(webpage.source.replaceFirst(
          'competence_stars_scale: 5', 'competence_stars_scale: $raw')));
      expect(SortedGradesViewModel.from(store.state).competenceStarsScale,
          int.tryParse(raw));
    }
  });

  Future<void> pumpRating(WidgetTester tester, int? value, int? scale,
          {double width = 320}) =>
      tester.pumpWidget(MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      child: CompetenceWidget(
                          competence: Competence((b) => b
                            ..typeName = 'Reading'
                            ..grade = value),
                          cancelled: false,
                          competenceStarsScale: scale))))));

  for (final scale in [5, 6, 7, 12]) {
    for (final value in [0, 4, scale]) {
      testWidgets('renders $value of $scale with wrapping on narrow screens',
          (tester) async {
        await pumpRating(tester, value, scale, width: 160);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.star), findsNWidgets(value));
        expect(find.byIcon(Icons.star_border), findsNWidgets(scale - value));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'unknown, invalid, conflicting and huge scales have safe fallbacks',
      (tester) async {
    for (final entry in <(int?, int?, String)>[
      (4, null, '4 ★ / ?'),
      (4, 0, '4 ★ / ?'),
      (null, 6, '—'),
      (-1, 6, '—'),
      (8, 6, '8 / 6 ?'),
      (777, 1000, '777 / 1000 ★')
    ]) {
      await pumpRating(tester, entry.$1, entry.$2);
      await tester.pumpAndSettle();
      expect(find.text(entry.$3), findsOneWidget);
      expect(find.byType(Star), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('type and date grouping forward the school scale',
      (tester) async {
    final grade = load([
      {'typeName': 'Reading', 'grade': '4'}
    ]);
    for (final grouped in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: grouped
                  ? GradeTypeWidget(
                      typeName: 'Test',
                      entries: [grade],
                      colorGrades: false,
                      competenceStarsScale: 7)
                  : GradeWidget(grade: grade, competenceStarsScale: 7))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsNWidgets(4));
      expect(find.byIcon(Icons.star_border), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }
  });
}
