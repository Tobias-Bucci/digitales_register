import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show actions, scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/calendar.dart';
import 'package:dr/ui/calendar_detail.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 10, 21);
final _monday = toMonday(_today);
final _tuesday = _monday.add(const Duration(days: 1));

const _phone = Size(412, 900);
const _wide = Size(1280, 800);

CalendarHour _hour(
  String subject,
  int from,
  int to, {
  bool warning = false,
  bool substitute = false,
}) =>
    buildCalendarHour(
      subject: subject,
      fromHour: from,
      toHour: to,
      rooms: const ['2B'],
      teachers: [buildTeacher(firstName: 'Anna', lastName: 'Rossi')],
      homeworkExams: warning
          ? [
              buildHomeworkExam(
                name: 'Schularbeit',
                typeName: 'Schularbeit',
                homework: false,
                warning: true,
              ),
            ]
          : const [],
      isDetectedSubstitute: substitute,
    );

AppState _state({
  bool withDays = true,
  bool noInternet = false,
  bool nicksBar = false,
  bool substituteBar = false,
  String languageCode = 'de',
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.noInternet = noInternet;
      b.settingsState
        ..languageCode = languageCode
        ..calendarColorBackground = true
        ..showCalendarNicksBar = nicksBar
        ..showCalendarSubstituteBar = substituteBar
        ..subjectNicks = MapBuilder<String, String>()
        ..subjectThemes = MapBuilder<String, SubjectTheme>({
          for (final (subject, color) in const [
            ('Deutsch', 0xFFE57373),
            ('Mathematik', 0xFF64B5F6),
            ('Religion', 0xFFA1887F),
            ('Geschichte', 0xFFFFB74D),
          ])
            subject: SubjectTheme((t) => t
              ..color = color
              ..thick = 2),
        });
      b.calendarState.currentMonday = _monday;
      if (withDays) {
        final week = <List<CalendarHour>>[
          [_hour('Deutsch', 1, 2), _hour('Mathematik', 3, 3, warning: true)],
          [
            _hour('Geschichte', 1, 1),
            _hour('Religion', 4, 4, substitute: true)
          ],
          [_hour('Mathematik', 1, 2), _hour('Deutsch', 3, 3)],
          [_hour('Geschichte', 1, 1)],
          [],
        ];
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          for (var d = 0; d < 5; d++)
            _monday.add(Duration(days: d)): buildCalendarDay(
              date: _monday.add(Duration(days: d)),
              hours: week[d],
            ),
        });
      }
    });

/// Opens the calendar as the navigation does, below the shell of the new
/// design.
Future<Store<AppState, AppStateBuilder, AppActions>> _pumpCalendar(
  WidgetTester tester, {
  AppState? state,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The lessons select through the global actions, as in the app.
  final store = createStore(
    initialState: state ?? _state(),
    newDesign: true,
    appActions: actions,
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
      .selectContentWidget(CalendarContainer(), Pages.calendar);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 800));

final _header = find.byKey(const Key('calendar-app-header'));

Finder _lesson(String subject) => find.bySemanticsLabel(RegExp('^$subject'));

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: _today);
  });

  tearDown(resetTestState);

  group('design switch', () {
    testWidgets('the new design shows the glass header', (tester) async {
      await _pumpCalendar(tester);

      expect(find.byType(Calendar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Calendar),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
      expect(_header, findsOneWidget);
      expect(find.byKey(const Key('calendar-view-switcher')), findsOneWidget);
      // The exam calendar is a segment of the switcher, not a button.
      expect(
          find.byKey(const Key('calendar-open-exam-calendar')), findsNothing);
      // A destination of the navigation has no way back.
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await pumpApp(
        tester,
        store: createStore(initialState: _state()),
        home: CalendarContainer(),
      );
      await settleFor(tester);

      expect(find.byType(GlassPageHeader), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.byKey(const Key('calendar-open-exam-calendar')),
        findsOneWidget,
      );
    });

    testWidgets('switching applies at once, in both directions',
        (tester) async {
      final store = await _pumpCalendar(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(GlassPageHeader), findsNothing);
      expect(find.byType(FloatingNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('week', () {
    testWidgets('shows the lessons of the week with today marked',
        (tester) async {
      await _pumpCalendar(tester);

      expect(find.text('Religion'), findsOneWidget);
      expect(find.text('Mathematik'), findsNWidgets(2));
      expect(find.byKey(const Key('calendar-today-indicator')), findsOneWidget);
      expect(find.text('19.10.26 – 23.10.26'), findsOneWidget);
      // Free days say so.
      expect(find.text('Frei'), findsOneWidget);
    });

    testWidgets('each lesson is one button for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCalendar(tester);

      expect(
        tester.getSemantics(_lesson('Religion')),
        isSemantics(
          label: 'Religion, Rossi',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the arrows turn the weeks and "current week" comes back',
        (tester) async {
      final store = await _pumpCalendar(tester);
      final currentWeek = find.byKey(const Key('calendar-current-week'));
      expect(currentWeek, findsNothing);

      await tester.tap(find.byKey(const Key('calendar-next-week')));
      await _settle(tester);
      expect(
        store.state.calendarState.currentMonday,
        _monday.add(const Duration(days: 7)),
      );
      expect(currentWeek, findsOneWidget);
      expect(
        find.descendant(of: _header, matching: currentWeek),
        findsOneWidget,
      );

      await tester.tap(currentWeek);
      await _settle(tester);
      expect(store.state.calendarState.currentMonday, _monday);
      expect(currentWeek, findsNothing);

      await tester.tap(find.byKey(const Key('calendar-previous-week')));
      await _settle(tester);
      expect(
        store.state.calendarState.currentMonday,
        _monday.subtract(const Duration(days: 7)),
      );
    });

    testWidgets('the date opens the date picker', (tester) async {
      await _pumpCalendar(tester);

      await tester.tap(find.byKey(const Key('calendar-week-range')));
      await _settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('lessons keep their markers for tests and substitutes',
        (tester) async {
      await _pumpCalendar(tester);
      final scheme =
          Theme.of(tester.element(find.byType(Calendar))).colorScheme;

      Border borderOf(String subject) {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: _lesson(subject),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).border! as Border;
      }

      // The first Mathematik lesson, on Monday, is a test.
      expect(borderOf('Religion').right.color, scheme.warning);
      expect(borderOf('Religion').left, BorderSide.none);
      expect(
        find.descendant(
          of: find.byType(Calendar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                ((widget.decoration as BoxDecoration).border as Border?)
                        ?.left
                        .color ==
                    scheme.exam,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('day detail', () {
    testWidgets('on a phone a lesson opens the day, and back closes it',
        (tester) async {
      final store = await _pumpCalendar(tester);

      await tester.tap(find.text('Religion'));
      await _settle(tester);

      expect(store.state.calendarState.selection?.date, _tuesday);
      expect(store.state.calendarState.selection?.hour, 4);
      expect(find.byKey(const Key('calendar-detail-header')), findsOneWidget);
      expect(find.byType(CalendarDetailPage), findsOneWidget);
      // The lesson is a glass card, with its substitute marker.
      expect(
        find.descendant(
          of: find.byType(CalendarDetailPage),
          matching: find.byType(GlassCard),
        ),
        findsWidgets,
      );
      expect(find.byKey(const Key('calendar-substitute-chip')), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar-detail-next')));
      await _settle(tester);
      expect(
        store.state.calendarState.selection?.date,
        _tuesday.add(const Duration(days: 1)),
      );

      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      // Only the panel of wide windows stays, closed.
      expect(find.byKey(const Key('calendar-detail-header')), findsNothing);
      expect(store.state.calendarState.selection, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a day without lessons shows a state card', (tester) async {
      final store = await _pumpCalendar(tester);
      await tester.tap(find.text('Religion'));
      await _settle(tester);

      // Friday has no lessons.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('calendar-detail-next')));
        await _settle(tester);
      }
      expect(
        store.state.calendarState.selection?.date,
        _monday.add(const Duration(days: 4)),
      );
      expect(
        find.byKey(const Key('calendar-detail-no-school')),
        findsOneWidget,
      );
      expect(find.text('Keine Schule'), findsOneWidget);
    });

    testWidgets('on wide windows the day is a panel beside the week',
        (tester) async {
      final store = await _pumpCalendar(tester, size: _wide);

      expect(find.byType(AppNavigationRail), findsOneWidget);
      await tester.tap(find.text('Religion'));
      await _settle(tester);

      final panel = find.byKey(const Key('calendar-detail-panel'));
      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('calendar-detail-header')), findsNothing);
      final header = tester.getRect(_header);
      final panelRect = tester.getRect(panel);
      final week = tester.getRect(find.byKey(const Key('calendar-week-range')));
      expect(panelRect.left, greaterThan(week.right));
      expect(panelRect.right, moreOrLessEquals(header.right, epsilon: 1));
      expect(panelRect.top, greaterThanOrEqualTo(header.bottom));
      // The lesson shows in the panel.
      expect(
        find.descendant(of: panel, matching: find.text('Religion')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('calendar-detail-close')));
      await _settle(tester);
      expect(store.state.calendarState.selection, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('states', () {
    testWidgets('offline without data shows a state card to try again',
        (tester) async {
      await _pumpCalendar(
        tester,
        state: _state(withDays: false, noInternet: true),
      );

      expect(find.byKey(const Key('calendar-week-offline')), findsOneWidget);
      expect(find.text('Keine Verbindung'), findsOneWidget);
      expect(find.text('Erneut laden'), findsOneWidget);
    });

    testWidgets('a week without data can be loaded again', (tester) async {
      await _pumpCalendar(tester, state: _state(withDays: false));

      expect(find.byKey(const Key('calendar-retry-week')), findsOneWidget);
      await tester.tap(find.text('Erneut laden'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline with data shows the hint instead of the black pill',
        (tester) async {
      await _pumpCalendar(tester, state: _state(noInternet: true));

      expect(find.byKey(const Key('calendar-last-fetched')), findsOneWidget);
      expect(find.byType(GlassOfflineHint), findsOneWidget);
    });
  });

  group('helper bars', () {
    testWidgets('the nickname bar opens and closes', (tester) async {
      final store = await _pumpCalendar(tester, state: _state(nicksBar: true));

      expect(find.text('Kürzel bearbeiten'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar-close-nicks-bar')));
      await _settle(tester);
      expect(store.state.settingsState.showCalendarNicksBar, isFalse);
    });

    testWidgets('the substitute bar fits a 412 px phone and hides once used',
        (tester) async {
      final store =
          await _pumpCalendar(tester, state: _state(substituteBar: true));

      expect(tester.takeException(), isNull);
      final bar = find.byKey(const Key('calendar-substitute-bar'));
      expect(bar, findsOneWidget);
      expect(tester.getRect(bar).right, lessThanOrEqualTo(_phone.width));
      // Above the floating navigation bar.
      expect(
        tester.getRect(bar).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );

      await tester.tap(bar);
      await _settle(tester);
      expect(store.state.settingsState.showCalendarSubstituteBar, isFalse);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the header is a band and the week below it',
        (tester) async {
      await _pumpCalendar(tester);

      final header = tester.getRect(_header);
      expect(header.left, 0);
      expect(header.top, 0);
      expect(
        tester.getRect(find.byKey(const Key('calendar-week-range'))).top,
        greaterThanOrEqualTo(header.bottom),
      );
    });

    for (final size in const [
      Size(1280, 800),
      Size(1920, 1080),
      Size(800, 600)
    ]) {
      testWidgets('at ${size.width} x ${size.height} the header floats',
          (tester) async {
        await _pumpCalendar(tester, size: size);

        final header = tester.getRect(_header);
        expect(header.top, DesignTokens.gutter);
        final previous =
            tester.getRect(find.byKey(const Key('calendar-previous-week')));
        expect(previous.left, greaterThanOrEqualTo(header.left));
        expect(previous.top, greaterThanOrEqualTo(header.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a phone held sideways keeps the lessons readable',
        (tester) async {
      await _pumpCalendar(tester, size: const Size(915, 412));

      expect(tester.takeException(), isNull);
      // The subject keeps its full line height in the small cells.
      final text = find.text('Religion');
      expect(text, findsOneWidget);
      final cell = find.ancestor(of: text, matching: find.byType(InkWell));
      expect(
        tester.getRect(text).height,
        lessThanOrEqualTo(tester.getRect(cell).height),
      );
      expect(tester.getRect(text).height, greaterThanOrEqualTo(12));
    });

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px with text at 2.0, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpCalendar(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
          state: _state(nicksBar: true, substituteBar: true),
        );

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Religion'));
        await _settle(tester);
        expect(find.byKey(const Key('calendar-detail-header')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the week or the panel',
        (tester) async {
      await _pumpCalendar(tester, size: _wide);
      await tester.tap(find.text('Religion'));
      await _settle(tester);

      final inPage = find.descendant(
        of: find.byType(Calendar),
        matching: find.byType(BackdropFilter),
      );
      final inHeader = find.descendant(
        of: _header,
        matching: find.byType(BackdropFilter),
      );
      expect(inHeader, findsOneWidget);
      expect(inPage.evaluate().length, inHeader.evaluate().length);
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('high contrast has no blur and no light, ${themeMode.name}',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpCalendar(tester, themeMode: themeMode);

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(Calendar),
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

    testWidgets('reduced motion turns the week at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final store = await _pumpCalendar(tester);

      await tester.tap(find.byKey(const Key('calendar-next-week')));
      await tester.pump();
      expect(
        store.state.calendarState.currentMonday,
        _monday.add(const Duration(days: 7)),
      );
      await _settle(tester);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpCalendar(
          tester,
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );
        final l10n = tester.element(find.byType(Calendar)).l10n;
        for (final key in const [
          'calendar.title',
          'calendar.previousDay',
          'calendar.nextDay',
          'exam.previousWeek',
          'exam.nextWeek',
        ]) {
          expect(l10n.text(key), isNot(key));
        }
        expect(
          find.byTooltip(l10n.text('exam.nextWeek')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
