import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart' show Pages;
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/exam_calendar_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

const _phone = Size(412, 900);
const _wide = Size(1280, 800);

/// The study plan follows the clock of the app, so the data is relative to
/// the real day.
final DateTime _today = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}();

UtcDateTime _day(int offset) {
  final date = _today.add(Duration(days: offset));
  return UtcDateTime(date.year, date.month, date.day);
}

Homework _exam(int id, String subject, String title) => buildHomework(
      id: id,
      type: HomeworkType.gradeGroup,
      warning: true,
      title: 'Test',
      subtitle: title,
      label: subject,
    );

AppState _state({bool withExams = true, String languageCode = 'de'}) =>
    AppState((b) {
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
      b.dashboardState.allDays = ListBuilder<Day>([
        if (withExams) ...[
          buildDay(date: _day(-6), homework: [
            _exam(1, 'Geschichte', 'Industrialisierung'),
          ]),
          buildDay(date: _day(0), homework: [
            _exam(2, 'Mathematik', 'Gleichungen'),
          ]),
          buildDay(date: _day(2), homework: [
            _exam(3, 'Deutsch', 'Erörterung'),
          ]),
          buildDay(date: _day(9), homework: [
            _exam(4, 'Englisch', 'Vocabulary'),
          ]),
        ],
      ]);
    });

Future<Store<AppState, AppStateBuilder, AppActions>> _pumpExams(
  WidgetTester tester, {
  AppState? state,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(initialState: state ?? _state(), newDesign: true);
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
      .selectContentWidget(const ExamCalendarContainer(), Pages.examCalendar);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 800));

final _header = find.byKey(const Key('exam-calendar-app-header'));
final _detailHeader = find.byKey(const Key('exam-detail-app-header'));
final _weekHeader = find.byKey(const Key('exam-week-app-header'));
Finder _card(int id) => find.byKey(Key('exam-card-assessment-$id'));

Future<void> _openDetail(WidgetTester tester, int id) async {
  await tester.tap(_card(id));
  await _settle(tester);
}

Future<void> _openWeek(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('exam-calendar-week-view')));
  await _settle(tester);
}

void _expectNoBlurBelowHeader(WidgetTester tester, Finder header) {
  final inHeader =
      find.descendant(of: header, matching: find.byType(BackdropFilter));
  expect(inHeader, findsOneWidget);
  // The navigation bar blurs as well; nothing else of the page does.
  final all = find.byType(BackdropFilter).evaluate().length;
  final navigation = find
      .descendant(
        of: find.byKey(const Key('app-navigation-bar')),
        matching: find.byType(BackdropFilter),
      )
      .evaluate()
      .length;
  expect(all - navigation, 1);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  group('design switch', () {
    testWidgets('the new design shows the glass header with the switch',
        (tester) async {
      await _pumpExams(tester);

      expect(find.byType(ExamCalendarPage), findsOneWidget);
      expect(_header, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ExamCalendarPage),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _header,
          matching: find.byKey(const Key('calendar-view-switcher')),
        ),
        findsOneWidget,
      );
      for (final key in ['exam-timeline-view', 'exam-calendar-week-view']) {
        expect(
          find.descendant(of: _header, matching: find.byKey(Key(key))),
          findsOneWidget,
        );
      }
      // A destination of the navigation has no way back.
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await pumpApp(
        tester,
        store: createStore(initialState: _state()),
        home: const ExamCalendarContainer(),
      );
      await settleFor(tester);

      expect(find.byType(GlassPageHeader), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('switching applies at once, in both directions',
        (tester) async {
      final store = await _pumpExams(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(GlassPageHeader), findsNothing);
      expect(tester.takeException(), isNull);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('list', () {
    testWidgets('shows the coming assessments as glass cards', (tester) async {
      await _pumpExams(tester);

      expect(find.text('Gleichungen'), findsOneWidget);
      expect(find.text('Erörterung'), findsOneWidget);
      expect(find.text('Vocabulary'), findsOneWidget);
      expect(
        find.descendant(of: _card(2), matching: find.byType(GlassCard)),
        findsOneWidget,
      );
      // The countdown chips and the progress of the study plans.
      expect(find.text('Heute'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      // The past one stays folded and is not built.
      expect(find.text('Industrialisierung'), findsNothing);
    });

    testWidgets('each card is one button for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpExams(tester);

      final node = tester.getSemantics(_card(3));
      expect(
        node,
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(node.label, startsWith('Erörterung, Deutsch'));
      expect(node.label, contains('Lernphasen erledigt'));
      semantics.dispose();
    });

    testWidgets('the past assessments open and close', (tester) async {
      await _pumpExams(tester);

      final toggle = find.byKey(const Key('exam-past-toggle'));
      await tester.scrollUntilVisible(toggle, 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(toggle);
      await _settle(tester);
      expect(find.text('Industrialisierung'), findsOneWidget);

      await tester.tap(toggle);
      await _settle(tester);
      expect(find.text('Industrialisierung'), findsNothing);
    });

    testWidgets('only past assessments still say that none are coming',
        (tester) async {
      await _pumpExams(
        tester,
        state: _state()
            .rebuild((b) => b.dashboardState.allDays = ListBuilder<Day>([
                  buildDay(
                      date: _day(-3), homework: [_exam(9, 'Physik', 'Optik')])
                ])),
      );
      expect(find.text('Keine kommenden Prüfungen'), findsOneWidget);
      expect(find.byKey(const Key('exam-past-toggle')), findsOneWidget);
    });
  });

  group('timeline', () {
    testWidgets('shows the week and the assessments of the day',
        (tester) async {
      await _pumpExams(tester);
      await tester.tap(find.byKey(const Key('exam-timeline-view')));
      await _settle(tester);

      expect(find.byKey(const Key('exam-timeline')), findsOneWidget);
      // Today has the maths test.
      expect(find.text('Gleichungen'), findsOneWidget);
      expect(find.text('Erörterung'), findsNothing);

      final inTwoDays = DateTime(_today.year, _today.month, _today.day + 2);
      final key = 'timeline-day-${inTwoDays.year}-'
          '${inTwoDays.month.toString().padLeft(2, '0')}-'
          '${inTwoDays.day.toString().padLeft(2, '0')}';
      await tester.tap(find.byKey(Key(key)));
      await _settle(tester);
      expect(find.text('Erörterung'), findsOneWidget);

      await tester.tap(find.byKey(const Key('timeline-next-assessment')));
      await _settle(tester);
      expect(find.text('Vocabulary'), findsOneWidget);

      await tester.tap(find.byKey(const Key('timeline-today')));
      await _settle(tester);
      expect(find.text('Gleichungen'), findsOneWidget);

      // Back to the list.
      await tester.tap(find.byKey(const Key('exam-timeline-view')));
      await _settle(tester);
      expect(find.byKey(const Key('exam-timeline')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('details', () {
    testWidgets('open with a glass header and back closes them',
        (tester) async {
      await _pumpExams(tester);
      await _openDetail(tester, 3);

      expect(_detailHeader, findsOneWidget);
      expect(find.text('Prüfungsdetails'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('exam-detail-list')),
          matching: find.text('Erörterung'),
        ),
        // The title, and the topic as the material.
        findsWidgets,
      );
      for (final title in ['Lernplan', 'Prüfungsstoff', 'Lokale Dateien']) {
        expect(find.textContaining(title, findRichText: true), findsOneWidget);
      }
      expect(find.byKey(const Key('exam-add-file')), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(_detailHeader, findsNothing);
      expect(_header, findsOneWidget);
    });

    testWidgets('checking a phase and the note are saved', (tester) async {
      final store = await _pumpExams(tester);
      await _openDetail(tester, 4);

      final first = find.byType(CheckboxListTile).first;
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pump();
      expect(completedPhaseIds(store.state, 'assessment-4'), isNotEmpty);

      await tester.enterText(find.byKey(const Key('exam-notes')), 'Kapitel 4');
      await tester.pump();
      expect(
        store.state.settingsState.assessmentStudyNotes['assessment-4'],
        'Kapitel 4',
      );
    });

    testWidgets('the phases are edited in sheets, with the date picker',
        (tester) async {
      final store = await _pumpExams(tester);
      await _openDetail(tester, 4);

      await tester.tap(find.byKey(const Key('exam-edit-phases')));
      await _settle(tester);
      expect(find.byKey(const Key('exam-phase-editor')), findsOneWidget);
      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byKey(const Key('exam-add-phase')));
      await _settle(tester);
      expect(find.byKey(const Key('exam-phase-form')), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Vokabeln lernen');

      await tester.tap(find.byKey(const Key('exam-phase-date')));
      await _settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // It has the rim of the glass from the page below.
      expect(
        Theme.of(tester.element(find.byType(DatePickerDialog)))
            .datePickerTheme
            .shape,
        isA<GlassRimBorder>(),
      );
      await tester.tap(find.text('OK'));
      await _settle(tester);

      await tester.tap(find.text('Fertig'));
      await _settle(tester);
      expect(find.byKey(const Key('exam-phase-form')), findsNothing);
      expect(find.text('Vokabeln lernen'), findsOneWidget);

      await tester.tap(find.text('Speichern'));
      await _settle(tester);
      expect(find.byKey(const Key('exam-phase-editor')), findsNothing);
      expect(find.text('Vokabeln lernen'), findsOneWidget);
      final saved = decodeStudyPhases(
        store.state.settingsState.assessmentStudyPhases['assessment-4'],
      );
      expect(saved.map((phase) => phase.title), contains('Vokabeln lernen'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling the editor changes nothing', (tester) async {
      final store = await _pumpExams(tester);
      await _openDetail(tester, 4);
      await tester.tap(find.byKey(const Key('exam-edit-phases')));
      await _settle(tester);
      await tester.tap(find.text('Abbrechen'));
      await _settle(tester);
      expect(find.byKey(const Key('exam-phase-editor')), findsNothing);
      expect(
        store.state.settingsState.assessmentStudyPhases['assessment-4'],
        isNull,
      );
    });
  });

  group('week', () {
    testWidgets('opens with a glass header, back and the week controls',
        (tester) async {
      await _pumpExams(tester);
      await _openWeek(tester);

      expect(_weekHeader, findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byKey(const Key('exam-week-range')), findsOneWidget);
      expect(find.byKey(const Key('exam-week-today')), findsOneWidget);
      expect(find.byKey(const Key('week-exam-assessment-2')), findsOneWidget);
      // On the current week there is no way back to it.
      final current = find.byKey(const Key('exam-week-current'));
      expect(current, findsNothing);

      await tester.tap(find.byKey(const Key('exam-week-next')));
      await _settle(tester);
      expect(find.byKey(const Key('exam-week-today')), findsNothing);
      expect(current, findsOneWidget);
      await tester.tap(current);
      await _settle(tester);
      expect(find.byKey(const Key('exam-week-today')), findsOneWidget);

      await tester.tap(find.byKey(const Key('exam-week-previous')));
      await _settle(tester);
      expect(current, findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(_header, findsOneWidget);
    });

    testWidgets('the range opens the date picker', (tester) async {
      await _pumpExams(tester);
      await _openWeek(tester);
      await tester.tap(find.byKey(const Key('exam-week-range')));
      await _settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('an assessment opens its details, which show the saved state',
        (tester) async {
      final store = await _pumpExams(tester);
      await _openWeek(tester);

      final tile = find.byKey(const Key('week-exam-assessment-2'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await _settle(tester);
      expect(_detailHeader, findsOneWidget);
      await tester.enterText(find.byKey(const Key('exam-notes')), 'Notiz');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(store.state.settingsState.assessmentStudyNotes['assessment-2'],
          'Notiz');

      await tester.tap(tile);
      await _settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('exam-notes')))
            .controller!
            .text,
        'Notiz',
      );
    });
  });

  group('states', () {
    testWidgets('without assessments a state card explains them',
        (tester) async {
      await _pumpExams(tester, state: _state(withExams: false));

      expect(find.byKey(const Key('exam-calendar-empty')), findsOneWidget);
      expect(find.byType(GlassStateCard), findsOneWidget);
      expect(find.text('Noch keine Prüfungen'), findsOneWidget);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the header is a band', (tester) async {
      await _pumpExams(tester);
      final header = tester.getRect(_header);
      expect(header.left, 0);
      expect(header.top, 0);
      expect(tester.getRect(_card(2)).top, greaterThanOrEqualTo(header.bottom));
    });

    testWidgets('wide windows float the header like the calendar',
        (tester) async {
      await _pumpExams(tester, size: _wide);
      final header = tester.getRect(_header);
      expect(header.top, DesignTokens.gutter);
      // The next assessment and the past ones stay beside the list.
      final side = find.byKey(const Key('dashboard-side-column'));
      expect(side, findsOneWidget);
      expect(
        find.descendant(
          of: side,
          matching: find.byKey(const Key('exam-past-toggle')),
        ),
        findsOneWidget,
      );
      expect(find.text('Nächste Prüfung'), findsOneWidget);
      // The cards line up with the floating header.
      expect(
        tester.getRect(find.byKey(const Key('exam-past-toggle'))).left,
        greaterThanOrEqualTo(header.left - 1),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('exam-timeline-view')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _openWeek(tester);
      expect(tester.getRect(_weekHeader).top, DesignTokens.gutter);
      expect(tester.takeException(), isNull);
    });

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px with text at 2.0, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpExams(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const Key('exam-timeline-view')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('exam-timeline-view')));
        await _settle(tester);

        await _openDetail(tester, 2);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('exam-edit-phases')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Abbrechen'));
        await _settle(tester);
        await tester.tap(find.text('Abbrechen'));
        await _settle(tester);
        await tester.tap(find.byType(BackButton));
        await _settle(tester);

        await _openWeek(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, on every page', (tester) async {
      await _pumpExams(tester);
      _expectNoBlurBelowHeader(tester, _header);

      await tester.tap(find.byKey(const Key('exam-timeline-view')));
      await _settle(tester);
      _expectNoBlurBelowHeader(tester, _header);
      await tester.tap(find.byKey(const Key('exam-timeline-view')));
      await _settle(tester);

      await _openDetail(tester, 2);
      _expectNoBlurBelowHeader(tester, _detailHeader);
      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      await _openWeek(tester);
      _expectNoBlurBelowHeader(tester, _weekHeader);
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('high contrast has no blur and no light, ${themeMode.name}',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpExams(tester, themeMode: themeMode);

        Finder sheen() => find.descendant(
              of: find.byType(ExamCalendarPage),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.painter is GlassSheenPainter,
              ),
            );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(sheen(), findsNothing);
        await _openWeek(tester);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion opens the past assessments at once',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpExams(tester);

      final toggle = find.byKey(const Key('exam-past-toggle'));
      await tester.scrollUntilVisible(toggle, 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('Industrialisierung'), findsOneWidget);
      // Nothing grows: the rows are there in full after one frame.
      expect(
        find.ancestor(
          of: find.text('Industrialisierung'),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpExams(
          tester,
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );
        final l10n = tester.element(find.byType(ExamCalendarPage)).l10n;
        for (final key in const [
          'exam.title',
          'exam.upcoming',
          'exam.past',
          'exam.timelineView',
          'exam.calendarView',
          'exam.details',
          'exam.editPhases',
          'calendar.currentWeek',
        ]) {
          expect(l10n.text(key), isNot(key));
        }
        expect(find.byTooltip(l10n.text('exam.calendarView')), findsOneWidget);
        await _openWeek(tester);
        expect(find.byTooltip(l10n.text('exam.nextWeek')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
