import 'dart:math' as math;

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart' show Pages;
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/sorted_grades_widget.dart' show gradesPageFocusSubject;
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 10, 20);
final _sent = UtcDateTime(2026, 10, 20, 8, 12);

const _eight = 'Neue Bewertung "Mathematik" "Schularbeit" "8"';
const _four = 'Neue Bewertung "Latein" "Test" "4"';

/// The dashboard of a signed-in account. Without [updates] it has no grades
/// and no grade on the dashboard: only the feed entries know the grade.
AppState _state(List<Notification> notifications,
        {void Function(AppStateBuilder)? updates}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>([buildDay(date: _today)]);
      b.notificationState
        ..notifications = ListBuilder<Notification>(notifications)
        ..lastFetched = _today;
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://school.example';
      b.noInternet = true;
      updates?.call(b);
    });

Notification _grade(String? title, {String? subTitle, String type = 'grade'}) =>
    buildNotification(
      id: 5,
      type: type,
      title: title ?? 'Neue Bewertung',
      subTitle: subTitle,
      objectId: 77,
      timeSent: _sent,
    );

/// The subject Geschichte with the grade 77 of [hundredths], which the feed
/// entry points at through its objectId.
void _withGrade(AppStateBuilder b, int hundredths) {
  final date = UtcDateTime(2026, 10, 19);
  b.gradesState
    ..semester = Semester.first.toBuilder()
    ..subjects = ListBuilder<Subject>([
      buildSubject(
        name: 'Geschichte',
        gradesAll: {
          Semester.first: BuiltList([
            buildGradeAll(date: date, grade: hundredths),
            buildGradeAll(date: UtcDateTime(2026, 9, 30), grade: 650),
          ]),
        },
        grades: {
          Semester.first: BuiltList([
            buildGradeDetail(
              id: 77,
              date: date,
              grade: hundredths,
              name: '1. Schularbeit',
            ),
          ]),
        },
      ),
    ]);
}

Future<Store<AppState, AppStateBuilder, AppActions>> _pump(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(400, 800),
  ThemeMode themeMode = ThemeMode.light,
  bool withMiddleware = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: state,
    newDesign: true,
    withMiddleware: withMiddleware,
  );
  await pumpApp(tester,
      store: store, home: DaysContainer(), themeMode: themeMode);
  await settleFor(tester);
  return store;
}

Finder _inBanner(Finder matching) =>
    find.descendant(of: find.byType(EventBanner), matching: matching);

Color _fill(WidgetTester tester) {
  final ink = tester.widget<Ink>(_inBanner(find.byType(Ink)));
  return (ink.decoration! as BoxDecoration).color!;
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('the event of a new grade reads its text (#154)', () {
    test('subject, kind and grade, with no grade loaded', () {
      final event = dashboardEvents(_state([_grade(_eight)])).single;
      expect(event.kind, DashboardEventKind.grade);
      expect(event.subject, 'Mathematik');
      expect(event.description, 'Schularbeit');
      expect(event.gradeText, '8');
      expect(event.gradeHundredths, 800);
      expect(event.gradePercent, 80);
      expect((event.averageBefore, event.averageAfter), (null, null));
      expect(event.detail, isNull);
      expect(event.time, _sent);
    });

    test('a failing grade and the notation of the grades page', () {
      for (final (title, text, hundredths) in [
        (_four, '4', 400),
        ('Neue Bewertung "Latein" "Test" "7½"', '7/8', 750),
        ('Neue Bewertung "Latein" "Test" "8-"', '8-', 775),
        ('Neue Bewertung "Latein" "Test" "10"', '10', 1000),
      ]) {
        final event = dashboardEvents(_state([_grade(title)])).single;
        expect((event.gradeText, event.gradeHundredths), (text, hundredths),
            reason: title);
      }
    });

    test('a short grade it cannot read is shown as written', () {
      final event = dashboardEvents(
              _state([_grade('Neue Bewertung "Religion" "Mündlich" "gut"')]))
          .single;
      expect((event.gradeText, event.gradeHundredths, event.gradePercent),
          ('gut', null, null));
      expect(event.subject, 'Religion');
    });

    test('the title first, then the second line', () {
      final second = dashboardEvents(
        _state([_grade('Neue Bewertung', subTitle: '"Deutsch" "Test" "6"')]),
      ).single;
      expect((second.subject, second.gradeText), ('Deutsch', '6'));
      final first = dashboardEvents(
        _state([_grade(_eight, subTitle: '"Deutsch" "Test" "6"')]),
      ).single;
      expect((first.subject, first.gradeText), ('Mathematik', '8'));
    });

    test('the type in any letter case', () {
      final event =
          dashboardEvents(_state([_grade(_eight, type: 'GRADE')])).single;
      expect(event.gradeText, '8');
    });

    test('without parts in the text and no grade, the plain entry stays', () {
      final event = dashboardEvents(
        _state([_grade('Neue Bewertung', subTitle: 'Mathematik')]),
      ).single;
      expect(event.kind, DashboardEventKind.grade);
      expect(event.description, 'Neue Bewertung');
      expect(event.detail, 'Mathematik');
      expect((event.gradeText, event.subject), (null, null));
    });

    test('the loaded grade adds its name and the averages', () {
      final event = dashboardEvents(_state(
        [_grade('Neue Bewertung "Geschichte" "Schularbeit" "7½"')],
        updates: (b) => _withGrade(b, 750),
      )).single;
      expect(event.subject, 'Geschichte');
      expect(event.description, '1. Schularbeit');
      expect((event.gradeText, event.gradeHundredths), ('7/8', 750));
      expect((event.averageBefore, event.averageAfter), (650, 700));
    });

    test('when the loaded grade differs, the text wins and no average', () {
      final event = dashboardEvents(_state(
        [_grade('Neue Bewertung "Geschichte" "Schularbeit" "8"')],
        updates: (b) => _withGrade(b, 750),
      )).single;
      expect((event.gradeText, event.gradeHundredths), ('8', 800));
      expect(event.description, '1. Schularbeit');
      expect(event.subject, 'Geschichte');
      expect((event.averageBefore, event.averageAfter), (null, null));
    });

    test('without parts in the text, the loaded grade as before', () {
      final event = dashboardEvents(
          _state([_grade(null)], updates: (b) => _withGrade(b, 750))).single;
      expect((event.gradeText, event.description), ('7/8', '1. Schularbeit'));
      expect((event.averageBefore, event.averageAfter), (650, 700));
    });
  });

  group('the banner of a new grade (#154)', () {
    for (final (size, layout) in [
      (const Size(400, 800), 'phone'),
      (const Size(1280, 800), 'wide'),
    ]) {
      for (final scale in [1.0, 2.0]) {
        for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
          for (final (title, subject, kind, grade, hundredths) in [
            (_eight, 'M', 'Schularbeit', '8', 800),
            (_four, 'L', 'Test', '4', 400),
          ]) {
            testWidgets('$grade, $layout, text at $scale, ${themeMode.name}',
                (tester) async {
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(
                  tester.platformDispatcher.clearTextScaleFactorTestValue);
              await _pump(tester, _state([_grade(title)]),
                  size: size, themeMode: themeMode);

              expect(find.byType(EventBanner), findsOneWidget);
              expect(_inBanner(find.text('Neue Bewertung • $subject')),
                  findsOneWidget);
              expect(_inBanner(find.byKey(const Key('event-banner-grade'))),
                  findsOneWidget);
              expect(_inBanner(find.text(grade)), findsOneWidget);
              expect(_inBanner(find.text(kind)), findsOneWidget);
              expect(_inBanner(find.text(title)), findsNothing);

              // Coloured as the grade badges of the grades page.
              final scheme = Theme.of(tester.element(find.byType(EventBanner)))
                  .colorScheme;
              final (foreground, background) =
                  gradeBadgeColors(scheme, hundredths)!;
              expect(_fill(tester), background.withValues(alpha: 0.92));
              expect(
                  background,
                  hundredths < 550
                      ? scheme.errorContainer
                      : scheme.successContainer);
              final text = tester.widget<Text>(
                  _inBanner(find.byKey(const Key('event-banner-grade'))));
              expect(text.style!.color, foreground);
              final behind = Color.alphaBlend(_fill(tester), scheme.surface);
              expect(_contrast(foreground, behind), greaterThanOrEqualTo(4.5));
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    }

    testWidgets('with grade colours off, it is neutral', (tester) async {
      await _pump(
        tester,
        _state([_grade(_four)],
            updates: (b) => b.settingsState.gradeColorsTurnedOff = true),
      );
      final scheme =
          Theme.of(tester.element(find.byType(EventBanner))).colorScheme;
      expect(
          _fill(tester), scheme.surfaceContainerHigh.withValues(alpha: 0.92));
      expect(_inBanner(find.text('4')), findsOneWidget);
    });

    testWidgets('an unreadable text keeps the plain entry', (tester) async {
      await _pump(tester,
          _state([_grade('Neue Bewertung', subTitle: 'Bitte nachsehen')]));
      expect(_inBanner(find.text('Neue Bewertung')), findsWidgets);
      expect(
          _inBanner(find.byKey(const Key('event-banner-grade'))), findsNothing);
    });

    testWidgets('a tap opens the grades of its subject and marks it seen',
        (tester) async {
      final focused = <String?>[];
      void record() => focused.add(gradesPageFocusSubject.value);
      gradesPageFocusSubject.addListener(record);
      addTearDown(() => gradesPageFocusSubject.removeListener(record));

      final store = await _pump(
        tester,
        _state([_grade(_eight)], updates: (b) => b.noInternet = false),
        withMiddleware: true,
      );
      await tester.tap(find.byType(EventBanner));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(scaffoldKey!.currentState!.currentSelected, Pages.grades);
      expect(focused.first, 'Mathematik');
      expect(store.state.notificationState.notifications, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
