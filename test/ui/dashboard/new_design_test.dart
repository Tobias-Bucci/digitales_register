import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/profile_menu_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/dashboard_events.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/compact_day_list.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:dr/ui/profile_menu.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter/rendering.dart'
    show RenderRepaintBoundary, RendererBinding, debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 10, 20);

Homework _test({bool checked = false}) => buildHomework(
      id: 1,
      title: 'Test',
      subtitle: 'Literarische Gattungen',
      label: 'Deutsch',
      type: HomeworkType.gradeGroup,
      checkable: true,
      checked: checked,
      warning: true,
    );

Homework _homework({bool checked = true}) => buildHomework(
      id: 2,
      title: 'Hausaufgabe',
      subtitle: 'Finish reading Chapter 3.',
      label: 'Englisch',
      checkable: true,
      checked: checked,
    );

AppState _dashboardState({
  List<Homework>? homework,
  List<Notification> notifications = const [],
  void Function(AppStateBuilder)? updates,
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>([
        buildDay(date: _today, homework: homework ?? [_test(), _homework()]),
      ]);
      b.notificationState
        ..notifications = ListBuilder<Notification>(notifications)
        ..lastFetched = _today;
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://franziskanergymnasium.digitalesregister.it';
      b.noInternet = true;
      updates?.call(b);
    });

Future<Store<AppState, AppStateBuilder, AppActions>> _pumpDashboard(
  WidgetTester tester,
  AppState state, {
  Size size = const Size(400, 800),
  bool newDesign = true,
  bool withMiddleware = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: state,
    newDesign: newDesign,
    withMiddleware: withMiddleware,
  );
  await pumpApp(tester, store: store, home: DaysContainer());
  await settleFor(tester);
  return store;
}

/// Lets the timers of the middleware run out after a test that navigates.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

DashboardEvent _gradeEvent(String text, int hundredths) => DashboardEvent(
      kind: DashboardEventKind.grade,
      time: _today,
      description: '1. Schularbeit',
      gradeText: text,
      gradeHundredths: hundredths,
      gradePercent: gradePercentOf(hundredths),
      notification: buildNotification(type: 'grade'),
    );

DashboardEvent _plainEvent(DashboardEventKind kind) => DashboardEvent(
      kind: kind,
      time: _today,
      description: 'Elternsprechtag',
      notification: buildNotification(id: 7, type: kind.name),
    );

/// The 16:9 windows of a desktop.
const _wideWindows = [
  Size(1920, 1080),
  Size(1600, 900),
  Size(1366, 768),
  Size(1280, 720),
];

/// What paints the light of the glass.
Iterable<CustomPaint> _glassPaints(WidgetTester tester) =>
    tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((paint) =>
        paint.painter is GlassSheenPainter ||
        paint.foregroundPainter is GlassRimPainter);

List<ColorScheme> _allSchemes() => [
      for (final accent in AppAccent.values)
        for (final (brightness, amoled) in const [
          (Brightness.light, false),
          (Brightness.dark, false),
          (Brightness.dark, true),
        ])
          AppPalette.scheme(
              brightness: brightness, amoled: amoled, accent: accent),
    ];

class _SheetCosts {
  int states = 0, builds = 0, paints = 0;
}

class _CountingPainter extends CustomPainter {
  const _CountingPainter(this.costs);

  final _SheetCosts costs;

  @override
  void paint(Canvas canvas, Size size) => costs.paints++;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

/// Content of a sheet that keeps count of what happens to it.
class _CountingContent extends StatefulWidget {
  const _CountingContent(this.costs);

  final _SheetCosts costs;

  @override
  State<_CountingContent> createState() => _CountingContentState();
}

class _CountingContentState extends State<_CountingContent> {
  @override
  void initState() {
    super.initState();
    widget.costs.states++;
  }

  @override
  Widget build(BuildContext context) {
    widget.costs.builds++;
    return CustomPaint(
      painter: _CountingPainter(widget.costs),
      child: const SizedBox(height: 300),
    );
  }
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: _today);
  });
  tearDown(resetTestState);

  group('compact day list', () {
    testWidgets('shows one slim row per entry, as in the sketch',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(find.byType(CompactEntryRow), findsNWidgets(2));
      expect(find.byType(ItemWidget), findsNothing);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      final text =
          tester.widget<Text>(find.byKey(const ValueKey('compact-row-text-1')));
      expect(text.textSpan!.toPlainText(), 'Test  Literarische Gattungen');
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.byKey(const ValueKey('compact-row-1'))).height,
        compactRowHeight,
      );
    });

    testWidgets('heads each day with its date and the done counter',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(find.text('Heute, Dienstag 20. Oktober'), findsOneWidget);
      expect(find.text('1/2 erledigt'), findsOneWidget);
    });

    test('counts only entries that can be ticked off', () {
      final day = buildDay(date: _today, homework: [
        _test(checked: true),
        _homework(checked: false),
        buildHomework(id: 3, type: HomeworkType.grade),
      ]);
      expect(dayProgress(day), (done: 1, total: 2));
    });

    testWidgets('tests are solid red with readable text', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      final context = tester.element(find.byType(CompactDayWidget));
      final scheme = Theme.of(context).colorScheme;
      final row =
          tester.widget<Material>(find.byKey(const ValueKey('compact-row-1')));
      expect(row.color, scheme.exam);
    });

    testWidgets('done entries stay in place, greyed out and checked',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      final context = tester.element(find.byType(CompactDayWidget));
      final scheme = Theme.of(context).colorScheme;
      final row =
          tester.widget<Material>(find.byKey(const ValueKey('compact-row-2')));
      expect(row.color, scheme.surfaceContainerHigh);
      final marks = tester.widgetList<NotepadMark>(find.byType(NotepadMark));
      expect(marks.where((mark) => mark.checked), hasLength(greaterThan(0)));
      final check = find.descendant(
        of: find.byKey(const ValueKey('compact-row-check-2')),
        matching: find.byType(NotepadMark),
      );
      expect(tester.widget<NotepadMark>(check).checked, isTrue);
    });

    test('a done test is no longer red', () {
      expect(
        compactRowStyle(_test(checked: true), const [], colorTestsInRed: true),
        CompactRowStyle.done,
      );
      expect(compactRowStyle(_test(), const [], colorTestsInRed: true),
          CompactRowStyle.test);
      expect(compactRowStyle(_test(), const [], colorTestsInRed: false),
          CompactRowStyle.normal);
    });

    testWidgets('tapping the notepad toggles the entry', (tester) async {
      final store = await _pumpDashboard(
        tester,
        _dashboardState().rebuild((b) => b.noInternet = false),
        withMiddleware: false,
      );
      final toggled = <bool>[];
      store.actions.dashboardActions.toggleDone;
      store.nextState.listen((state) {
        toggled.add(state.dashboardState.allDays!.single.homework
            .firstWhere((homework) => homework.id == 1)
            .checked);
      });

      await tester.tap(find.byKey(const ValueKey('compact-row-check-1')));
      await settleFor(tester);

      expect(toggled, contains(true));
      expect(find.text('2/2 erledigt'), findsOneWidget);
    });

    testWidgets('offline, the notepad does nothing', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-check-1')));
      await settleFor(tester);

      expect(find.text('1/2 erledigt'), findsOneWidget);
    });

    testWidgets('tapping a row opens the full text', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(EntryDetailsSheet), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.byKey(const Key('entry-details-toggle')), findsOneWidget);
    });

    testWidgets('own reminders can be edited and deleted from their details',
        (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(homework: [
          buildHomework(
            title: 'Erinnerung',
            subtitle: 'Buch mitnehmen',
            type: HomeworkType.homework,
            deleteable: true,
            checkable: true,
          ),
        ]).rebuild((b) => b.noInternet = false),
      );

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byKey(const Key('entry-details-edit')), findsOneWidget);
      expect(find.byKey(const Key('entry-details-delete')), findsOneWidget);
    });

    group('new entry button', () {
      final addButton = find.byKey(ValueKey('day-add-entry-$_today'));

      AppState online({List<Homework>? homework}) =>
          _dashboardState(homework: homework).rebuild(
            (b) => b.noInternet = false,
          );

      testWidgets('is an icon in the heading of each day', (tester) async {
        await _pumpDashboard(tester, online());

        expect(find.text('Neuer Eintrag'), findsNothing);
        expect(
          find.descendant(
            of: addButton,
            matching: find.byIcon(Icons.add_rounded),
          ),
          findsOneWidget,
        );
        expect(
          tester.getCenter(addButton).dy,
          moreOrLessEquals(
            tester.getCenter(find.byKey(ValueKey('day-heading-$_today'))).dy,
            epsilon: 1,
          ),
        );
      });

      testWidgets('stands above the notepads', (tester) async {
        await _pumpDashboard(tester, online());

        expect(
          tester.getCenter(addButton).dx,
          tester
              .getCenter(find.byKey(const ValueKey('compact-row-check-1')))
              .dx,
        );
      });

      testWidgets('is there on a day without entries', (tester) async {
        await _pumpDashboard(tester, online(homework: const []));

        expect(find.byType(CompactDayWidget), findsOneWidget);
        expect(addButton, findsOneWidget);
      });

      for (final (name, platform) in const [
        ('touch', TargetPlatform.android),
        ('desktop', TargetPlatform.windows),
      ]) {
        testWidgets('has a full touch target on $name, around a small disc',
            (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          await _pumpDashboard(tester, online());

          final target = tester.getSize(addButton);
          final disc = tester.getSize(find.descendant(
            of: addButton,
            matching: find.byType(Material),
          ));
          debugDefaultTargetPlatformOverride = null;
          expect(target, const Size.square(48));
          expect(disc, const Size.square(30));
        });
      }

      testWidgets('has the localised label for tooltip and screen readers',
          (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpDashboard(tester, online());

        expect(find.byTooltip('Neuer Eintrag'), findsOneWidget);
        expect(
          tester.getSemantics(addButton),
          containsSemantics(
            tooltip: 'Neuer Eintrag',
            isButton: true,
            hasTapAction: true,
          ),
        );
        handle.dispose();
      });

      testWidgets('can be reached and activated with the keyboard',
          (tester) async {
        await _pumpDashboard(tester, online());

        final focus = Focus.of(tester.element(find.descendant(
          of: addButton,
          matching: find.byIcon(Icons.add_rounded),
        )));
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFor(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('a tap asks for the text of the entry', (tester) async {
        await _pumpDashboard(tester, online());

        await tester.tap(addButton);
        await settleFor(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('offline, it stays visible but does nothing', (tester) async {
        await _pumpDashboard(tester, _dashboardState());

        expect(addButton, findsOneWidget);
        await tester.tap(addButton, warnIfMissed: false);
        await settleFor(tester);
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('leaves more room for the date on a small phone',
          (tester) async {
        await _pumpDashboard(tester, online(), size: const Size(320, 640));

        final progress =
            tester.widget<Text>(find.byKey(ValueKey('day-progress-$_today')));
        expect(progress.data, '1/2');
        expect(progress.semanticsLabel, '1/2 erledigt');
      });
    });

    testWidgets('fits at least twice as many entries as the legacy list',
        (tester) async {
      Homework entry(int id) => buildHomework(
            id: id,
            title: 'Hausaufgabe',
            subtitle: 'Seite $id lesen',
            label: 'Deutsch',
            checkable: true,
          );
      final state =
          _dashboardState(homework: [for (var i = 1; i < 4; i++) entry(i)]);

      await _pumpDashboard(tester, state, newDesign: false);
      final legacy = tester.getTopLeft(find.byType(ItemWidget).at(1)).dy -
          tester.getTopLeft(find.byType(ItemWidget).at(0)).dy;

      await _pumpDashboard(tester, state);
      final compact = tester.getTopLeft(find.byType(CompactEntryRow).at(1)).dy -
          tester.getTopLeft(find.byType(CompactEntryRow).at(0)).dy;

      expect(legacy / compact, greaterThanOrEqualTo(2));
    });
  });

  group('notepad checkbox', () {
    testWidgets('the check mark is animated, but not with reduced motion',
        (tester) async {
      Future<NotepadPainter> painterAfter(bool reduceMotion) async {
        Widget build({required bool checked}) => MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: MaterialApp(
                home:
                    NotepadMark(key: ValueKey(reduceMotion), checked: checked),
              ),
            );
        await tester.pumpWidget(build(checked: false));
        await tester.pumpWidget(build(checked: true));
        await tester.pump(const Duration(milliseconds: 50));
        final paint = tester.widget<CustomPaint>(find.descendant(
          of: find.byType(NotepadMark),
          matching: find.byType(CustomPaint),
        ));
        return paint.painter! as NotepadPainter;
      }

      expect((await painterAfter(false)).progress, inExclusiveRange(0, 1));
    });
  });

  group('event banner', () {
    test('7/8 is 7.50, so 75 percent', () {
      expect(gradePercentOf(750), 75);
    });

    test('percentages rise with the grade', () {
      final percents = [600, 700, 750, 800, 825].map(gradePercentOf).toList();
      expect(percents, [60, 70, 75, 80, 82.5]);
      expect(gradePercentOf(null), isNull);
    });

    test('percentages follow the language', () async {
      Future<String> format(AppLanguage language) async => formatPercent(
          await AppLocalizations.delegate.load(language.locale), 82.5);
      expect(await format(AppLanguage.de), '82,5\u00A0%');
      expect(await format(AppLanguage.en), '82.5%');
      expect(await format(AppLanguage.it), '82,5%');
      expect(await format(AppLanguage.lld), '82,5\u00A0%');
    });

    test('grade colours follow gradeCategory without changing it', () {
      final scheme = AppPalette.light;
      EventBannerColors colors(int grade) =>
          eventBannerColors(scheme, _gradeEvent('$grade', grade),
              colorGrades: true);
      expect(colors(500).background, scheme.errorContainer);
      expect(colors(549).background, scheme.errorContainer);
      expect(colors(550).background, scheme.warningContainer);
      expect(colors(575).background, scheme.warningContainer);
      expect(colors(600).background, scheme.successContainer);
      expect(colors(750).background, scheme.successContainer);
    });

    test('the other kinds have their own colour on every accent', () {
      for (final scheme in _allSchemes()) {
        EventBannerColors colors(DashboardEventKind kind) =>
            eventBannerColors(scheme, _plainEvent(kind), colorGrades: true);
        final message = colors(DashboardEventKind.message).background;
        final absence = colors(DashboardEventKind.absence).background;
        final observation = colors(DashboardEventKind.observation).background;
        expect(message, scheme.infoContainer);
        expect(absence, scheme.noticeContainer);
        expect(observation, scheme.observationContainer);
        expect({
          message,
          absence,
          observation,
          scheme.warningContainer,
          scheme.errorContainer,
          scheme.successContainer,
        }, hasLength(6));
      }
      // Independent of the accent: a message stays blue on a green accent.
      final green = AppPalette.scheme(
          brightness: Brightness.light, amoled: false, accent: AppAccent.green);
      expect(green.infoContainer, AppPalette.light.infoContainer);
    });

    test('without grade colours, a grade banner is neutral', () {
      final scheme = AppPalette.light;
      final colors =
          eventBannerColors(scheme, _gradeEvent('4', 400), colorGrades: false);
      expect(colors.background, scheme.surfaceContainerHigh);
    });

    test('banner text meets WCAG AA in every theme and accent', () {
      for (final scheme in _allSchemes()) {
        for (final event in [
          _gradeEvent('4', 400),
          _gradeEvent('5/6', 550),
          _gradeEvent('8', 800),
          for (final kind in DashboardEventKind.values)
            if (kind != DashboardEventKind.grade) _plainEvent(kind),
        ]) {
          final colors = eventBannerColors(scheme, event, colorGrades: true);
          // The fill is slightly translucent, over the page background.
          final fill = Color.alphaBlend(
              colors.background.withValues(alpha: 0.92), scheme.surface);
          expect(
            AppPalette.contrastRatio(colors.foreground, fill),
            greaterThanOrEqualTo(4.5),
            reason: '${event.kind} on ${scheme.brightness}',
          );
        }
      }
    });

    test('red test rows and done rows meet WCAG AA in every theme', () {
      for (final scheme in _allSchemes()) {
        expect(AppPalette.contrastRatio(scheme.onExam, scheme.exam),
            greaterThanOrEqualTo(4.5));
        expect(
          AppPalette.contrastRatio(
              scheme.onSurfaceVariant, scheme.surfaceContainerHigh),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    Color over(Color top, double alpha, Color below) =>
        Color.alphaBlend(top.withValues(alpha: alpha), below);

    test('text on the glass surfaces stays readable over anything', () {
      for (final scheme in _allSchemes()) {
        final light = GlassLight.of(scheme);
        Color lit(Color surface) =>
            over(light.highlight, light.sheenStrength, surface);
        // The worst case is content of the opposite brightness below.
        final behind = scheme.brightness == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);
        final header = over(scheme.surface, DesignTokens.headerOpacity, behind);
        for (final surface in [header, lit(header)]) {
          expect(AppPalette.contrastRatio(scheme.onSurface, surface),
              greaterThanOrEqualTo(4.5));
          expect(AppPalette.contrastRatio(scheme.onSurfaceVariant, surface),
              greaterThanOrEqualTo(4.5));
        }
        final bar = over(
          navigationBarTint(scheme),
          DesignTokens.navigationBarOpacity,
          behind,
        );
        expect(AppPalette.contrastRatio(scheme.onSurfaceVariant, bar),
            greaterThanOrEqualTo(4.5));
        // The bar holds only icons, and the sheen hardly reaches them.
        expect(AppPalette.contrastRatio(scheme.onSurfaceVariant, lit(bar)),
            greaterThanOrEqualTo(3));
        // With blur off, the bar below the lens is solid.
        for (final below in [bar, navigationBarTint(scheme)]) {
          final lens = Color.alphaBlend(navigationLensFill(scheme), below);
          for (final surface in [
            lens,
            over(light.highlight, light.glowStrength, lens),
            over(light.highlight, light.reflectionStrength, lens),
          ]) {
            expect(AppPalette.contrastRatio(scheme.onPrimaryContainer, surface),
                greaterThanOrEqualTo(4.5));
          }
          // The ring of the keyboard is no text, 3:1 is what it needs.
          for (final surface in [below, lens]) {
            expect(
              AppPalette.contrastRatio(navigationFocusRing(scheme), surface),
              greaterThanOrEqualTo(3),
            );
          }
        }
      }
    });

    test('text on a glass sheet stays readable over anything', () {
      for (final scheme in _allSchemes()) {
        final light = GlassLight.of(scheme);
        for (final page in [
          const Color(0xFF000000),
          const Color(0xFFFFFFFF),
          scheme.surface,
          scheme.exam,
        ]) {
          // Between the sheet and the page lies the scrim of the route.
          final scrim = over(const Color(0xFF000000), 0.54, page);
          final sheet =
              over(scheme.surfaceContainer, DesignTokens.sheetOpacity, scrim);
          for (final surface in [
            sheet,
            over(light.highlight, light.sheenStrength, sheet),
          ]) {
            for (final text in [
              scheme.onSurface,
              scheme.onSurfaceVariant,
              scheme.onPrimaryContainer,
            ]) {
              expect(AppPalette.contrastRatio(text, surface),
                  greaterThanOrEqualTo(4.5));
            }
          }
        }
      }
    });

    test('text on a banner stays readable below the sheen', () {
      for (final scheme in _allSchemes()) {
        final light = GlassLight.of(scheme);
        for (final kind in DashboardEventKind.values) {
          final colors = eventBannerColors(
            scheme,
            kind == DashboardEventKind.grade
                ? _gradeEvent('7/8', 750)
                : _plainEvent(kind),
            colorGrades: true,
          );
          final banner = over(colors.background, 0.92, scheme.surface);
          expect(
            AppPalette.contrastRatio(
              colors.foreground,
              over(light.highlight, light.sheenStrength, banner),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    });

    test('text on glass controls stays readable', () {
      for (final scheme in _allSchemes()) {
        final light = GlassLight.of(scheme);
        for (final page in [
          scheme.surface,
          over(scheme.surfaceContainerLowest, 0.72, scheme.surface),
          over(scheme.primaryContainer, 0.42, scheme.surface),
        ]) {
          final control = over(
            scheme.secondaryContainer,
            DesignTokens.controlOpacity,
            page,
          );
          for (final surface in [
            control,
            over(light.highlight, light.sheenStrength, control),
          ]) {
            expect(
                AppPalette.contrastRatio(scheme.onSecondaryContainer, surface),
                greaterThanOrEqualTo(4.5));
          }
        }
      }
    });

    AppState gradeState({int grade = 750}) {
      final date = UtcDateTime(2026, 10, 19);
      return _dashboardState(
        notifications: [
          buildNotification(
            id: 5,
            type: 'grade',
            title: 'Neue Bewertung',
            objectId: 77,
            timeSent: UtcDateTime(2026, 10, 20, 8, 12),
          ),
        ],
        updates: (b) {
          b.noInternet = false;
          b.gradesState
            ..semester = Semester.first.toBuilder()
            ..subjects = ListBuilder<Subject>([
              buildSubject(
                name: 'Geschichte',
                gradesAll: {
                  Semester.first: BuiltList([
                    buildGradeAll(date: date, grade: grade),
                    buildGradeAll(date: UtcDateTime(2026, 9, 30), grade: 650),
                  ]),
                },
                grades: {
                  Semester.first: BuiltList([
                    buildGradeDetail(
                      id: 77,
                      date: date,
                      grade: grade,
                      name: '1. Schularbeit',
                    ),
                  ]),
                },
              ),
            ]);
        },
      );
    }

    Color bannerFill(WidgetTester tester) {
      final ink = tester.widget<Ink>(find.descendant(
        of: find.byType(EventBanner),
        matching: find.byType(Ink),
      ));
      return (ink.decoration! as BoxDecoration).color!;
    }

    ColorScheme schemeOf(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(EventBanner))).colorScheme;

    for (final (grade, name) in const [
      (500, 'red'),
      (550, 'orange'),
      (750, 'green'),
    ]) {
      testWidgets('an untouched setting colours the grade $grade $name',
          (tester) async {
        final store = await _pumpDashboard(tester, gradeState(grade: grade));
        expect(store.state.settingsState.colorGrades, isFalse);

        final scheme = schemeOf(tester);
        final expected = switch (name) {
          'red' => scheme.errorContainer,
          'orange' => scheme.warningContainer,
          _ => scheme.successContainer,
        };
        expect(bannerFill(tester), expected.withValues(alpha: 0.92));
      });
    }

    testWidgets('turning grade colours off makes the banner neutral',
        (tester) async {
      final store = await _pumpDashboard(tester, gradeState());
      final scheme = schemeOf(tester);

      await store.actions.settingsActions.colorGrades(true);
      await settleFor(tester);
      expect(
        bannerFill(tester),
        scheme.successContainer.withValues(alpha: 0.92),
      );

      await store.actions.settingsActions.colorGrades(false);
      await settleFor(tester);
      expect(
        bannerFill(tester),
        scheme.surfaceContainerHigh.withValues(alpha: 0.92),
      );

      await store.actions.settingsActions.colorGrades(true);
      await settleFor(tester);
      expect(
        bannerFill(tester),
        scheme.successContainer.withValues(alpha: 0.92),
      );
    });

    test('the switch alone records the choice, its default stays off',
        () async {
      final settings = SettingsState();
      expect(settings.colorGrades, isFalse);
      expect(settings.gradeColorsTurnedOff, isFalse);

      final store = createStore();
      await store.actions.settingsActions.colorGrades(false);
      expect(store.state.settingsState.colorGrades, isFalse);
      expect(store.state.settingsState.gradeColorsTurnedOff, isTrue);
    });

    test('settings stored before the choice was recorded count as untouched',
        () {
      final stored = serializers.serialize(SettingsState())! as List<Object?>;
      final index = stored.indexOf('gradeColorsTurnedOff');
      final older = [...stored]..removeRange(index, index + 2);
      final restored = serializers.deserialize(
        json.decode(json.encode(older)) as Object,
      )! as SettingsState;
      expect(restored.gradeColorsTurnedOff, isFalse);
    });

    test('turning grade colours off survives a restart', () {
      final settings = SettingsState((b) => b.gradeColorsTurnedOff = true);
      final restored = serializers.deserialize(
        json.decode(json.encode(serializers.serialize(settings))) as Object,
      )! as SettingsState;
      expect(restored.gradeColorsTurnedOff, isTrue);
    });

    test('a grade event knows its value, average and entry time', () {
      final event = dashboardEvents(gradeState()).single;
      expect(event.kind, DashboardEventKind.grade);
      expect(event.gradeText, '7/8');
      expect(event.gradePercent, 75);
      expect(event.description, '1. Schularbeit');
      expect(event.subject, 'Geschichte');
      expect(event.averageBefore, 650);
      expect(event.averageAfter, 700);
      expect(event.time, UtcDateTime(2026, 10, 20, 8, 12));
    });

    testWidgets('shows a grade the way the sketch does', (tester) async {
      await _pumpDashboard(tester, gradeState());

      expect(find.text('Neue Bewertung • G'), findsOneWidget);
      expect(find.text('7/8'), findsOneWidget);
      expect(find.text('1. Schularbeit'), findsOneWidget);
      final facts = tester
          .widget<Text>(find.byKey(const Key('event-banner-facts')))
          .data!;
      expect(facts, contains('75\u00A0%'));
      expect(facts, contains('6,50 → 7,00'));
      expect(facts, contains('20.10.2026'));
      expect(facts, contains('08:12'));
    });

    testWidgets('sits between the summary box and the day list',
        (tester) async {
      await _pumpDashboard(tester, gradeState());

      final box = tester
          .getBottomLeft(find.byKey(const ValueKey('dashboard-header-box')));
      final banner = find.byType(EventBanner);
      final day = tester.getTopLeft(find.byType(CompactDayWidget));
      expect(tester.getTopLeft(banner).dy, greaterThanOrEqualTo(box.dy));
      expect(tester.getBottomLeft(banner).dy, lessThanOrEqualTo(day.dy));
    });

    testWidgets('dismissing marks the event as seen', (tester) async {
      final store = await _pumpDashboard(tester, gradeState());
      await tester
          .tap(find.byKey(const ValueKey('event-banner-close-notification-5')));
      await settleFor(tester);

      expect(find.byType(EventBanner), findsNothing);
      expect(store.state.notificationState.notifications, isEmpty);
    });

    testWidgets('swiping dismisses it as well', (tester) async {
      final store = await _pumpDashboard(tester, gradeState());
      await tester.drag(find.byType(EventBanner), const Offset(-500, 0));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(find.byType(EventBanner), findsNothing);
      expect(store.state.notificationState.notifications, isEmpty);
    });

    testWidgets('it stays until it is opened or dismissed', (tester) async {
      await _pumpDashboard(tester, gradeState());
      await settleFor(tester, duration: const Duration(seconds: 10));

      expect(find.byType(EventBanner), findsOneWidget);
    });

    testWidgets('several events show one banner and a count', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          for (var id = 1; id <= 3; id++)
            buildNotification(
              id: id,
              type: 'message',
              title: 'Mitteilung $id',
              objectId: id,
              timeSent: UtcDateTime(2026, 10, 10 + id),
            ),
        ]),
      );

      expect(find.byType(EventBanner), findsOneWidget);
      expect(find.text('Mitteilung 3'), findsOneWidget);
      expect(find.text('+2 weitere'), findsOneWidget);

      await tester.tap(find.byKey(const Key('event-banner-more')));
      await settleFor(tester);

      expect(find.byType(EventListSheet), findsOneWidget);
      expect(find.text('Mitteilung 1'), findsOneWidget);
    });

    testWidgets('a new observation on the dashboard gets a banner',
        (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(homework: [
          buildHomework(
            title: 'Beobachtung',
            subtitle: 'Mitarbeit',
            label: 'Mathematik',
            type: HomeworkType.observation,
            isNew: true,
          ),
        ]),
      );

      expect(find.text('Neue Beobachtung • M'), findsOneWidget);
    });

    test('the kinds of the feed are recognized without case sensitivity', () {
      expect(dashboardEventKindOf('GRADE'), DashboardEventKind.grade);
      expect(dashboardEventKindOf('messageShared'), DashboardEventKind.message);
      expect(dashboardEventKindOf('absence'), DashboardEventKind.absence);
      expect(
          dashboardEventKindOf('observation'), DashboardEventKind.observation);
      expect(dashboardEventKindOf('generic'), DashboardEventKind.general);
      expect(dashboardEventKindOf(null), DashboardEventKind.general);
    });

    testWidgets('the edge only moves without reduced motion', (tester) async {
      Widget edge(bool reduceMotion) => MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: AnimatedEventEdge(color: Colors.green, child: SizedBox()),
            ),
          );
      await tester.pumpWidget(edge(true));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(Container());
      await tester.pumpWidget(edge(false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);

      // It comes to rest by itself.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('design switch', () {
    testWidgets('new is the default for a fresh install', (tester) async {
      expect(SettingsState().legacyDesign, isFalse);
    });

    test('settings stored before the switch existed open the new design', () {
      final stored = serializers.serialize(SettingsState())! as List<Object?>;
      final index = stored.indexOf('legacyDesign');
      final older = [...stored]..removeRange(index, index + 2);
      final restored =
          serializers.deserialize(json.decode(json.encode(older)) as Object)!
              as SettingsState;
      expect(restored.legacyDesign, isFalse);
    });

    test('the choice is persisted with the other settings', () {
      final settings = SettingsState((b) => b.legacyDesign = true);
      final restored = serializers.deserialize(
        json.decode(json.encode(serializers.serialize(settings))) as Object,
      )! as SettingsState;
      expect(restored.legacyDesign, isTrue);
    });

    testWidgets('new replaces the app bar, bell and sidebar', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [buildNotification(type: 'grade')]),
      );

      expect(find.byType(DashboardAppHeader), findsOneWidget);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(find.byType(NotificationIconContainer), findsNothing);
      expect(find.byType(Sidebar), findsNothing);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byType(DayWidget), findsNothing);
    });

    testWidgets('legacy keeps the app bar, bell and sidebar', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [buildNotification(type: 'grade')]),
        newDesign: false,
      );

      expect(find.byType(DashboardAppHeader), findsNothing);
      expect(find.byType(FloatingNavigationBar), findsNothing);
      expect(find.byType(NotificationIconContainer), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byType(DayWidget), findsOneWidget);
      expect(find.byType(EventBanner), findsNothing);
    });

    testWidgets('switching applies at once, without a restart', (tester) async {
      final store = await _pumpDashboard(tester, _dashboardState());
      expect(find.byType(CompactDayWidget), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(CompactDayWidget), findsNothing);
      expect(find.byType(DayWidget), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(CompactDayWidget), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
    });

    testWidgets('the settings page offers the switch', (tester) async {
      final store =
          await _pumpDashboard(tester, _dashboardState(), withMiddleware: true);
      await store.actions.routingActions.showSettings();
      await settleFor(tester);

      final switcher = find.byKey(const Key('settings-design-switch'));
      await tester.scrollUntilVisible(
        switcher,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump();
      await tester
          .tap(find.descendant(of: switcher, matching: find.text('Legacy')));
      await settleFor(tester);

      expect(store.state.settingsState.legacyDesign, isTrue);
      await _finish(tester);
    });
  });

  group('header', () {
    testWidgets('shows the school of the account', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(find.text('Franziskanergymnasium Bozen'), findsOneWidget);
      expect(find.text('Digitales Register'), findsOneWidget);
    });

    test('finds the school by its address, whatever its spelling', () {
      const url = 'https://franziskanergymnasium.digitalesregister.it';
      expect(schoolNameForUrl(url), 'Franziskanergymnasium Bozen');
      expect(schoolNameForUrl('$url/'), 'Franziskanergymnasium Bozen');
      expect(schoolNameForUrl(' ${url.toUpperCase()} '),
          'Franziskanergymnasium Bozen');
      expect(schoolNameForUrl('https://example.org'), isNull);
      expect(schoolNameForUrl(null), isNull);
    });

    testWidgets('a long name is cut off and the height stays', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(updates: (b) {
          b.url = 'https://fo-brixen.digitalesregister.it';
        }),
        size: const Size(320, 640),
      );

      final school =
          tester.widget<Text>(find.byKey(const Key('dashboard-header-school')));
      expect(school.maxLines, 1);
      expect(school.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSize(find.byKey(const Key('dashboard-app-header'))).height,
        DashboardAppHeader.height,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the filter stays reachable in the summary box',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dashboard-header-box')),
          matching: find.text('Filter'),
        ),
        findsOneWidget,
      );
    });
  });

  group('scroll to top button', () {
    final button = find.byKey(const Key('dashboard-scroll-up'));
    final header = find.byKey(const Key('dashboard-app-header'));

    AppState longList() => _dashboardState(updates: (b) {
          b.noInternet = false;
          b.dashboardState.future = true;
          b.dashboardState.allDays = ListBuilder<Day>([
            for (var day = 0; day < 14; day++)
              buildDay(
                date: _today.add(Duration(days: day)),
                homework: [
                  for (var entry = 0; entry < 1 + day % 3; entry++)
                    buildHomework(
                      id: day * 10 + entry + 1,
                      title: 'Hausaufgabe',
                      label: 'Deutsch',
                      checkable: true,
                    ),
                ],
              ),
          ]);
        });

    ScrollController list(WidgetTester tester) => tester
        .widgetList<ListView>(find.byType(ListView))
        .firstWhere((list) => list.controller != null)
        .controller!;

    Future<void> scrollTo(WidgetTester tester, double offset) async {
      list(tester).jumpTo(offset);
      await tester.pump();
    }

    for (final window in const [
      Size(320, 640),
      Size(412, 915),
      Size(800, 1100),
      Size(1100, 800),
      Size(1920, 1080),
    ]) {
      testWidgets('stays in the header at every offset in a $window window',
          (tester) async {
        await _pumpDashboard(tester, longList(), size: window);
        var checked = 0;
        final end = list(tester).position.maxScrollExtent;
        for (var offset = 0.0; offset <= end; offset += 8) {
          await scrollTo(tester, offset);
          if (button.evaluate().isEmpty) continue;
          checked++;
          final rect = tester.getRect(button);
          // The header stands above the list, so the controls of a day can
          // only be under the button where the header covers them anyway.
          expect(tester.getRect(header).expandToInclude(rect),
              tester.getRect(header));
        }
        expect(checked, greaterThan(0));
        expect(find.byType(FloatingActionButton), findsNothing);
      });
    }

    testWidgets('appears only once the list has scrolled', (tester) async {
      await _pumpDashboard(tester, longList(), size: const Size(412, 915));
      expect(button, findsNothing);

      await scrollTo(tester, 251);
      expect(button, findsOneWidget);

      await scrollTo(tester, 100);
      expect(button, findsNothing);
    });

    testWidgets('has a label and a full touch target', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpDashboard(tester, longList(), size: const Size(320, 640));
      await scrollTo(tester, 400);

      expect(
        tester.getSemantics(find.byTooltip('Nach oben')),
        matchesSemantics(
          tooltip: 'Nach oben',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(button), const Size.square(48));
      semantics.dispose();
    });

    testWidgets('scrolls back to the start', (tester) async {
      await _pumpDashboard(tester, longList(), size: const Size(412, 915));
      await scrollTo(tester, 600);

      await tester.tap(button);
      await settleFor(tester, duration: const Duration(milliseconds: 700));

      expect(list(tester).offset, 0);
      expect(button, findsNothing);
    });

    testWidgets('goes away with the list', (tester) async {
      final store =
          await _pumpDashboard(tester, longList(), size: const Size(412, 915));
      await scrollTo(tester, 600);
      expect(button, findsOneWidget);

      // All days lie ahead, so the past has nothing to show.
      store.actions.dashboardActions.switchFuture();
      await settleFor(tester);

      expect(find.byType(CompactDayWidget), findsNothing);
      expect(button, findsNothing);
    });

    testWidgets('stays a floating button in Legacy', (tester) async {
      await _pumpDashboard(
        tester,
        longList(),
        size: const Size(800, 915),
        newDesign: false,
      );
      await scrollTo(tester, 600);

      expect(button, findsNothing);
      final legacyButton =
          find.widgetWithIcon(FloatingActionButton, Icons.arrow_upward_rounded);
      await tester.tap(legacyButton);
      await settleFor(tester, duration: const Duration(milliseconds: 700));

      expect(list(tester).offset, 0);
      expect(legacyButton, findsNothing);
    });
  });

  group('new entries strip', () {
    final strip = find.byKey(const Key('dashboard-new-entries'));
    final show = find.byKey(const Key('dashboard-show-new-entries'));
    final dismiss = find.byKey(const Key('dashboard-dismiss-new-entries'));
    final header = find.byKey(const Key('dashboard-app-header'));
    const newEntryId = 101;

    // Only a day far down has a new entry, so that it starts out of view.
    AppState newEntries() => _dashboardState(updates: (b) {
          b.noInternet = false;
          b.dashboardState.future = true;
          b.dashboardState.allDays = ListBuilder<Day>([
            for (var day = 0; day < 20; day++)
              buildDay(
                date: _today.add(Duration(days: day)),
                homework: [
                  buildHomework(
                    id: day * 10 + 1,
                    title: 'Hausaufgabe',
                    label: 'Deutsch',
                    checkable: true,
                    isNew: day == 10,
                  ),
                ],
              ),
          ]);
        });

    for (final window in const [
      Size(320, 640),
      Size(412, 915),
      Size(800, 1100),
      Size(1100, 800),
      Size(1920, 1080),
    ]) {
      testWidgets('leaves the day controls free in a $window window',
          (tester) async {
        await _pumpDashboard(tester, newEntries(), size: window);

        expect(find.byType(FloatingActionButton), findsNothing);
        final bounds = tester.getRect(header);
        for (final control in [strip, show, dismiss]) {
          final rect = tester.getRect(control);
          expect(bounds.expandToInclude(rect), bounds);
        }
        // The list starts below the strip instead of passing through it at
        // rest, also where the first day stands right under the header.
        final firstDay = find.byKey(ValueKey('day-add-entry-$_today'));
        expect(
            tester.getRect(firstDay).top, greaterThanOrEqualTo(bounds.bottom));
      });
    }

    testWidgets('goes to the new entry', (tester) async {
      await _pumpDashboard(tester, newEntries(), size: const Size(412, 915));
      final row = find.byKey(const ValueKey('compact-row-$newEntryId'));
      expect(row, findsNothing);

      await tester.tap(show);
      await settleFor(tester, duration: const Duration(seconds: 3));

      expect(row, findsOneWidget);
      expect(tester.getRect(row).top,
          greaterThanOrEqualTo(tester.getRect(header).bottom));
      expect(tester.widget<FilledButton>(show).onPressed, isNull);
      expect(dismiss, findsOneWidget);
    });

    testWidgets('marks the entries as seen and goes away', (tester) async {
      final store = await _pumpDashboard(tester, newEntries(),
          size: const Size(412, 915));
      expect(
        tester.getSize(header).height,
        DashboardAppHeader.height + DashboardAppHeader.newEntriesHeight,
      );

      await tester.tap(dismiss);
      await settleFor(tester);

      expect(store.state.dashboardState.allDays![10].homework.single.isNew,
          isFalse);
      expect(strip, findsNothing);
      expect(tester.getSize(header).height, DashboardAppHeader.height);
    });

    testWidgets('has labels and full touch targets', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpDashboard(tester, newEntries(), size: const Size(320, 640));

      expect(find.text('Neue Einträge'), findsOneWidget);
      expect(find.byTooltip('Ausblenden'), findsOneWidget);
      expect(tester.getSize(dismiss), const Size.square(48));
      expect(tester.getSize(show).height, 48);
      semantics.dispose();
    });

    testWidgets('fits with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpDashboard(tester, newEntries(), size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(strip, findsOneWidget);
    });

    testWidgets('Legacy keeps its floating buttons', (tester) async {
      await _pumpDashboard(
        tester,
        newEntries(),
        size: const Size(800, 915),
        newDesign: false,
      );

      expect(strip, findsNothing);
      expect(find.text('Neue Einträge'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNWidgets(2));
    });
  });

  group('editing cards', () {
    AppState editState() => _dashboardState(
          updates: (b) {
            b.noInternet = false;
            b.settingsState.dashboardItems =
                ListBuilder(['holidays', 'gradingDeadline']);
          },
        );
    const card = ValueKey('dashboard-item-holidays');

    testWidgets('a long press starts editing, with haptic feedback',
        (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      await _pumpDashboard(tester, editState());

      await tester.longPress(find.byKey(card));
      await settleFor(tester);

      expect(find.byKey(const Key('dashboard-edit-done')), findsOneWidget);
      expect(haptics, isNotEmpty);
    });

    Future<Store<AppState, AppStateBuilder, AppActions>> startEditing(
        WidgetTester tester) async {
      final store = await _pumpDashboard(tester, editState());
      await tester.longPress(find.byKey(card));
      await settleFor(tester);
      return store;
    }

    testWidgets('reorders with the arrows', (tester) async {
      final store = await startEditing(tester);

      await tester
          .tap(find.byKey(const ValueKey('dashboard-edit-later-holidays')));
      await settleFor(tester);

      expect(store.state.settingsState.dashboardItems.toList(),
          ['gradingDeadline', 'holidays']);
    });

    testWidgets('reorders by dragging', (tester) async {
      final store = await startEditing(tester);

      final from = tester.getCenter(find.byKey(card));
      final to = tester.getCenter(
          find.byKey(const ValueKey('dashboard-item-gradingDeadline')));
      await tester.dragFrom(from, to - from);
      await settleFor(tester);

      expect(store.state.settingsState.dashboardItems.toList(),
          ['gradingDeadline', 'holidays']);
    });

    testWidgets('changes the width', (tester) async {
      final store = await startEditing(tester);

      await tester
          .tap(find.byKey(const ValueKey('dashboard-edit-width-holidays')));
      await settleFor(tester);

      expect(store.state.settingsState.dashboardItemSpans['holidays'], 1);
    });

    testWidgets('removes and adds cards', (tester) async {
      final store = await startEditing(tester);

      await tester
          .tap(find.byKey(const ValueKey('dashboard-edit-remove-holidays')));
      await settleFor(tester);
      expect(store.state.settingsState.dashboardItems.toList(),
          ['gradingDeadline']);

      await tester.tap(find.byKey(const Key('dashboard-edit-add')));
      await settleFor(tester);
      await tester.tap(find.byKey(const ValueKey('dashboard-add-holidays')));
      await settleFor(tester);
      expect(store.state.settingsState.dashboardItems.toList(),
          ['gradingDeadline', 'holidays']);
    });

    testWidgets('done leaves the edit mode', (tester) async {
      await startEditing(tester);

      await tester.tap(find.byKey(const Key('dashboard-edit-done')));
      await settleFor(tester);

      expect(find.byKey(const Key('dashboard-edit-done')), findsNothing);
    });

    testWidgets('escape leaves the edit mode', (tester) async {
      await startEditing(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFor(tester);

      expect(find.byKey(const Key('dashboard-edit-done')), findsNothing);
    });

    testWidgets('a right-click opens the context menu', (tester) async {
      final store = await _pumpDashboard(tester, editState());

      await tester.tap(find.byKey(card), buttons: kSecondaryButton);
      await settleFor(tester);
      expect(find.text('Karten bearbeiten'), findsOneWidget);

      await tester.tap(find.text('Ausblenden'));
      await settleFor(tester);
      expect(store.state.settingsState.dashboardItems.toList(),
          ['gradingDeadline']);
    });

    testWidgets('the keyboard reaches the same menu', (tester) async {
      await _pumpDashboard(tester, editState());

      final inkWell = find.descendant(
        of: find.byKey(card),
        matching: find.byType(InkWell),
      );
      tester.widget<InkWell>(inkWell.first).focusNode;
      Focus.of(tester.element(inkWell.first));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final primary = FocusManager.instance.primaryFocus!;
      expect(primary.context, isNotNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await settleFor(tester);

      expect(find.text('Karten bearbeiten'), findsOneWidget);
    });

    testWidgets('without any card, they can still be added', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(updates: (b) {
          b.settingsState.dashboardItems = ListBuilder<String>();
        }),
      );

      await tester.tap(find.byKey(const Key('dashboard-edit-empty')));
      await settleFor(tester);

      expect(find.byKey(const Key('dashboard-edit-add')), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('the bar has six destinations with tooltips', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(AppDestination.values, hasLength(6));
      for (final destination in AppDestination.values) {
        final tooltip = tester.widget<Tooltip>(find.descendant(
          of: find.byKey(ValueKey('app-navigation-${destination.name}')),
          matching: find.byType(Tooltip),
        ));
        expect(tooltip.message, isNotEmpty);
      }
    });

    testWidgets('fits a small phone', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1),
          buildNotification(id: 2, type: 'message', objectId: 2),
        ]),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      // Banner and day list stay on the screen, above the bar.
      final bar =
          tester.getTopLeft(find.byKey(const Key('app-navigation-bar'))).dy;
      expect(tester.getBottomLeft(find.byType(EventBanner)).dy,
          lessThanOrEqualTo(bar));
      // The test font is much wider than the real one, so the box is taller.
      expect(
        tester.getTopLeft(find.byType(CompactDayWidget).first).dy,
        lessThan(568),
      );
    });

    testWidgets('shows the unread messages as a badge', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(id: 1, type: 'message', objectId: 1),
          buildNotification(id: 2, type: 'message', objectId: 2),
          buildNotification(id: 3, type: 'grade'),
        ]),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('app-navigation-messages')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a wide window gets a rail with the same destinations',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1200, 800));

      expect(find.byType(FloatingNavigationBar), findsNothing);
      expect(find.byType(AppNavigationRail), findsOneWidget);
      for (final destination in AppDestination.values) {
        expect(
          find.byKey(ValueKey('app-navigation-${destination.name}')),
          findsOneWidget,
        );
      }
    });

    for (final size in _wideWindows) {
      testWidgets('the rail fits and floats at ${size.width}x${size.height}',
          (tester) async {
        await _pumpDashboard(tester, _dashboardState(), size: size);

        final rail =
            tester.getRect(find.byKey(const Key('app-navigation-rail')));
        expect(rail.center.dy, moreOrLessEquals(size.height / 2));
        expect(rail.left, DesignTokens.gutter);
        expect(rail.width, appNavigationBarHeight);
        expect(rail.bottom, lessThan(size.height));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the shadow of the rail ends inside its margin',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1280, 720));

      final glass = tester.widget<FloatingGlass>(find.descendant(
        of: find.byType(AppNavigationRail),
        matching: find.byType(FloatingGlass),
      ));
      expect(glass.shadowBlur, lessThan(DesignTokens.gutter));
    });

    testWidgets('a very low window can scroll the rail', (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(900, 280));

      expect(tester.takeException(), isNull);
      final profile = find.byKey(const ValueKey('app-navigation-profile'));
      await tester.dragUntilVisible(
        profile,
        find.descendant(
          of: find.byType(AppNavigationRail),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -60),
      );
      expect(tester.getRect(profile).bottom, lessThanOrEqualTo(280));
    });

    testWidgets('the bar does not cover the end of the list', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(homework: [
          for (var id = 1; id < 30; id++)
            buildHomework(id: id, title: 'Eintrag $id', checkable: true),
        ]),
      );

      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('compact-row-29')),
        200,
        scrollable: list,
      );
      await tester.fling(list, const Offset(0, -2000), 3000);
      await settleFor(tester, duration: const Duration(seconds: 1));

      final bar =
          tester.getTopLeft(find.byKey(const Key('app-navigation-bar'))).dy;
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('compact-row-29'))).dy,
        lessThanOrEqualTo(bar),
      );
    });

    test('every page of the old sidebar belongs to a destination', () {
      for (final page in Pages.values) {
        expect(() => destinationOf(page), returnsNormally);
      }
      expect(destinationOf(Pages.examCalendar), AppDestination.calendar);
      expect(destinationOf(Pages.classRegister), AppDestination.extras);
      expect(destinationOf(Pages.homeworkSummary), AppDestination.extras);
      expect(destinationOf(Pages.certificate), AppDestination.extras);
      expect(destinationOf(Pages.absences), AppDestination.extras);
      expect(destinationOf(Pages.courseMaterials), AppDestination.extras);
      expect(destinationOf(Pages.settings), AppDestination.profile);
    });

    Future<void> openDestination(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(ValueKey('app-navigation-$name')));
      await settleFor(tester, duration: const Duration(seconds: 1));
    }

    Pages current() => scaffoldKey!.currentState!.currentSelected;

    // Wide enough for the calendar's hints in the wide test font, while it is
    // still a phone layout.
    const phone = Size(700, 900);

    for (final (destination, page) in const [
      ('grades', Pages.grades),
      ('calendar', Pages.calendar),
      ('messages', Pages.messages),
      ('extras', Pages.extras),
    ]) {
      testWidgets('the bar reaches $destination', (tester) async {
        await _pumpDashboard(
          tester,
          _dashboardState(),
          size: phone,
          withMiddleware: true,
        );

        await openDestination(tester, destination);
        expect(current(), page);

        await openDestination(tester, 'dashboard');
        expect(current(), Pages.homework);
        await _finish(tester);
      });
    }

    for (final (key, page) in const [
      ('extras-class-register', Pages.classRegister),
      ('extras-homework-summary', Pages.homeworkSummary),
      ('extras-certificate', Pages.certificate),
      ('extras-absences', Pages.absences),
      ('extras-course-materials', Pages.courseMaterials),
    ]) {
      testWidgets('Extras reaches ${page.name} and back', (tester) async {
        await _pumpDashboard(tester, _dashboardState(), withMiddleware: true);
        await openDestination(tester, 'extras');

        await tester.tap(find.byKey(ValueKey(key)));
        await settleFor(tester, duration: const Duration(seconds: 1));
        expect(current(), page);
        // The bar keeps showing where the page belongs.
        expect(
          tester
              .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
              .selected,
          AppDestination.extras,
        );

        await tester.tap(find.byType(BackButton));
        await settleFor(tester, duration: const Duration(seconds: 1));
        expect(current(), Pages.extras);
        await _finish(tester);
      });
    }

    testWidgets('leaving a page of Extras does not stack up', (tester) async {
      await _pumpDashboard(tester, _dashboardState(), withMiddleware: true);
      await openDestination(tester, 'extras');
      await tester.tap(find.byKey(const Key('extras-absences')));
      await settleFor(tester, duration: const Duration(seconds: 1));

      await openDestination(tester, 'grades');
      expect(current(), Pages.grades);

      scaffoldKey!.currentState!.navigatorKey.currentState!.pop();
      await settleFor(tester);
      expect(current(), Pages.homework);
      await _finish(tester);
    });

    testWidgets('a grade banner opens its subject', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(
          notifications: [
            buildNotification(id: 5, type: 'grade', objectId: 77),
          ],
          updates: (b) => b.gradesState.subjects = ListBuilder<Subject>([
            buildSubject(
              id: 1,
              name: 'Geschichte',
              gradesAll: {
                Semester.first: BuiltList([
                  buildGradeAll(date: _today, grade: 750),
                ]),
              },
              grades: {
                Semester.first: BuiltList([
                  buildGradeDetail(id: 77, date: _today, grade: 750),
                ]),
              },
            ),
          ]),
        ),
        withMiddleware: true,
      );

      await tester.tap(find.byType(EventBanner));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(current(), Pages.grades);
      expect(gradesPageFocusSubject.value, isNull);
      expect(
        tester.widget<SubjectWidget>(find.byType(SubjectWidget).first).expanded,
        isTrue,
      );
      await _finish(tester);
    });

    testWidgets('the calendar merges the exam calendar', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(),
        size: phone,
        withMiddleware: true,
      );
      await openDestination(tester, 'calendar');

      final switcher = find.byKey(const Key('calendar-view-switcher'));
      expect(switcher, findsOneWidget);
      await tester.tap(find.descendant(
        of: switcher,
        matching: find.byIcon(Icons.school_outlined),
      ));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(current(), Pages.examCalendar);
      expect(find.byKey(const Key('exam-timeline-view')), findsOneWidget);
      expect(
        tester
            .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
            .selected,
        AppDestination.calendar,
      );
      await _finish(tester);
    });

    testWidgets('settings and profile are reached through the profile menu',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState(), withMiddleware: true);

      await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
      await settleFor(tester);
      await tester.tap(find.byKey(const Key('profile-menu-settings')));
      await settleFor(tester, duration: const Duration(seconds: 1));

      expect(current(), Pages.settings);
      expect(find.byType(ProfileMenu), findsNothing);
      await _finish(tester);
    });
  });

  group('profile menu', () {
    AppState profileState() => _dashboardState(updates: (b) {
          b.loginState
            ..username = 'anna'
            ..otherAccounts = ListBuilder<String>(['Ben', 'Cleo']);
        });

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
      await settleFor(tester);
    }

    testWidgets('has all entries of the sidebar', (tester) async {
      await _pumpDashboard(tester, profileState());
      await openMenu(tester);

      expect(find.text('anna'), findsOneWidget);
      expect(
        find.text('anna · Franziskanergymnasium Bozen'),
        findsOneWidget,
      );
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Cleo'), findsOneWidget);
      expect(find.text('Konto hinzufügen'), findsOneWidget);
      expect(find.text('Abmelden'), findsOneWidget);
      expect(
          find.byKey(const Key('profile-menu-remove-account')), findsOneWidget);
    });

    testWidgets('opens as a panel in a wide window', (tester) async {
      await _pumpDashboard(tester, profileState(), size: const Size(1200, 800));

      await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
      await settleFor(tester);

      expect(find.byType(ProfileMenuContainer), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('switches to another account', (tester) async {
      final store = await _pumpDashboard(tester, profileState());
      final selected = <int>[];
      final menu = ProfileMenu(
        name: 'anna',
        username: 'anna',
        account: null,
        userIcon: null,
        otherAccounts: const ['Ben'],
        showProfile: () {},
        showSettings: () {},
        selectAccount: selected.add,
        addAccount: () {},
        removeCurrentAccount: () {},
        logout: () {},
      );
      await tester.pumpWidget(buildTestApp(
        store: store,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(child: menu),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await settleFor(tester);

      await tester.tap(find.byKey(const ValueKey('profile-menu-account-0')));
      await settleFor(tester);

      expect(selected, [0]);
    });

    testWidgets('logging out needs a confirmation', (tester) async {
      var loggedOut = 0;
      final store = createStore();
      await pumpApp(
        tester,
        store: store,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: ProfileMenu(
                  name: 'anna',
                  username: 'anna',
                  account: null,
                  userIcon: null,
                  otherAccounts: const [],
                  showProfile: () {},
                  showSettings: () {},
                  selectAccount: (_) {},
                  addAccount: () {},
                  removeCurrentAccount: () {},
                  logout: () => loggedOut++,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleFor(tester);

      await tester.tap(find.byKey(const Key('profile-menu-logout')));
      await settleFor(tester);
      expect(loggedOut, 0);
      expect(find.text('Abmelden?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Abmelden'));
      await settleFor(tester);
      expect(loggedOut, 1);
    });
  });

  group('glass', () {
    tearDown(GlassPerformance.instance.reset);

    testWidgets('blur is used while the device keeps up', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(find.byType(BackdropFilter), findsWidgets);
    });

    testWidgets('a device that drops frames gets a solid surface',
        (tester) async {
      for (var frame = 0; frame < 120; frame++) {
        GlassPerformance.instance.record(const Duration(milliseconds: 30));
      }
      expect(GlassPerformance.instance.blurAllowed.value, isFalse);

      await _pumpDashboard(tester, _dashboardState());

      expect(find.byType(BackdropFilter), findsNothing);
    });

    test('a few slow frames do not turn it off', () {
      for (var frame = 0; frame < 120; frame++) {
        GlassPerformance.instance.record(Duration(
          milliseconds: frame % 10 == 0 ? 30 : 8,
        ));
      }
      expect(GlassPerformance.instance.blurAllowed.value, isTrue);
    });

    testWidgets('high contrast gets a solid surface', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpDashboard(tester, _dashboardState());

      expect(find.byType(BackdropFilter), findsNothing);
      expect(_glassPaints(tester), isEmpty);
    });

    testWidgets('a solid surface keeps its rim, which costs next to nothing',
        (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;

      await _pumpDashboard(tester, _dashboardState());

      expect(find.byType(BackdropFilter), findsNothing);
      expect(_glassPaints(tester), isNotEmpty);
    });

    testWidgets('nothing in the list blurs', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    });

    testWidgets('light on the glass does not take taps', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState().rebuild((b) => b.noInternet = false),
      );

      await tester.tap(find.text('Filter'));
      await settleFor(tester);

      expect(find.byType(GlassSheet), findsOneWidget);
    });

    testWidgets('Legacy has no part in it', (tester) async {
      await _pumpDashboard(tester, _dashboardState(), newDesign: false);

      expect(find.byType(GlassEdge), findsNothing);
      expect(_glassPaints(tester), isEmpty);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Filter'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(
        FilledButtonTheme.of(tester.element(find.byWidget(button))).style,
        isNull,
      );
    });
  });

  group('wide windows', () {
    final side = find.byKey(const Key('dashboard-side-column'));
    final header = find.byKey(const Key('dashboard-app-header'));
    final box = find.byKey(const ValueKey('dashboard-header-box'));
    final row = find.byKey(const ValueKey('compact-row-1'));

    AppState withBanner() => _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ]);

    for (final size in _wideWindows) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$name shows the summary beside the day list',
          (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardHeader), findsOneWidget);
        expect(
          find.descendant(of: side, matching: find.byType(DashboardHeader)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: side, matching: find.byType(EventBanner)),
          findsOneWidget,
        );
        expect(tester.getRect(side).right, lessThan(tester.getRect(row).left));
        expect(tester.getRect(box).top, tester.getRect(header).bottom + 8);
      });

      testWidgets('$name keeps the phone width of the summary and short rows',
          (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        expect(tester.getSize(side).width, DashboardColumns.sideWidth);
        expect(
          tester.getSize(row).width,
          lessThanOrEqualTo(DesignTokens.contentMaxWidth),
        );
        expect(tester.getSize(row).height, compactRowHeight);
      });

      testWidgets('$name lines the header up with the columns', (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        final bar = tester.getRect(header);
        expect(bar.left, moreOrLessEquals(tester.getRect(box).left));
        expect(bar.right, moreOrLessEquals(tester.getRect(row).right));
        expect(bar.top, DesignTokens.gutter);
      });

      testWidgets('$name centres the columns next to the rail', (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        final bar = tester.getRect(header);
        expect(
          bar.left - appNavigationRailExtent,
          moreOrLessEquals(size.width - bar.right),
        );
      });

      testWidgets('$name keeps its list scrollable to the edge of the window',
          (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        final list = find.ancestor(
          of: row,
          matching: find.byType(Scrollable),
        );
        expect(tester.getRect(list.first).right, size.width);
      });
    }

    testWidgets('the day list scrolls while the summary stays', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(homework: [
          for (var id = 1; id < 40; id++)
            buildHomework(id: id, title: 'Eintrag $id', checkable: true),
        ]),
        size: const Size(1280, 720),
      );

      final before = tester.getTopLeft(box);
      await tester.drag(row, const Offset(0, -300));
      await settleFor(tester);

      expect(tester.getTopLeft(box), before);
      expect(tester.getTopLeft(row).dy, lessThan(100));
    });

    testWidgets('a low window can still reach the whole summary',
        (tester) async {
      await _pumpDashboard(tester, withBanner(), size: const Size(1280, 300));

      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.byType(EventBanner),
        find.descendant(of: side, matching: find.byType(Scrollable)),
        const Offset(0, -80),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text fits both columns', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpDashboard(tester, withBanner(), size: const Size(1280, 720));

      expect(tester.takeException(), isNull);
    });

    testWidgets('without entries the message stands beside the summary',
        (tester) async {
      await _pumpDashboard(
        tester,
        AppState((b) => b
          ..dashboardState.allDays = ListBuilder<Day>()
          ..loginState.loggedIn = true
          ..url = 'https://franziskanergymnasium.digitalesregister.it'),
        size: const Size(1366, 768),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: side, matching: find.byType(DashboardHeader)),
        findsOneWidget,
      );
    });

    testWidgets('a window below the limit keeps one column', (tester) async {
      await _pumpDashboard(tester, withBanner(), size: const Size(1000, 700));

      expect(side, findsNothing);
      expect(tester.getRect(header).top, DesignTokens.gutter);
      expect(tester.getRect(header).left,
          moreOrLessEquals(tester.getRect(box).left));
      expect(tester.takeException(), isNull);
    });

    for (final size in const [Size(320, 640), Size(400, 800), Size(700, 800)]) {
      testWidgets('a ${size.width.toInt()} px window stays the phone layout',
          (tester) async {
        await _pumpDashboard(tester, withBanner(), size: size);

        expect(side, findsNothing);
        expect(tester.getRect(header).left, 0);
        expect(tester.getRect(header).right, size.width);
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Legacy stays as it was at any width', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(),
        size: const Size(1920, 1080),
        newDesign: false,
      );

      expect(side, findsNothing);
      expect(find.byType(DashboardAppHeader), findsNothing);
      expect(find.byType(AppNavigationRail), findsNothing);
      expect(find.byType(Sidebar), findsOneWidget);
    });

    test('the limit follows from the columns and the rail', () {
      expect(DashboardColumns.forWindow(1079), isNull);
      expect(DashboardColumns.forWindow(1080)?.margin, 0);
      expect(
        DashboardColumns.forWindow(1920)?.margin,
        (1920 - appNavigationRailExtent - DashboardColumns.maxWidth) / 2,
      );
    });
  });

  group('desktop panels', () {
    tearDown(GlassPerformance.instance.reset);

    final panel = find.byKey(const Key('glass-sheet'));

    for (final size in _wideWindows) {
      final name = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('$name centres the details of an entry', (tester) async {
        await _pumpDashboard(tester, _dashboardState(), size: size);

        await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
        await settleFor(tester);

        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(EntryDetailsSheet), findsOneWidget);
        final rect = tester.getRect(panel);
        expect(rect.width, lessThanOrEqualTo(GlassSheet.panelMaxWidth));
        expect(rect.center.dx, moreOrLessEquals(size.width / 2));
        expect(rect.center.dy, moreOrLessEquals(size.height / 2));
        expect(
          find.descendant(of: panel, matching: find.byType(BackdropFilter)),
          findsOneWidget,
        );
      });
    }

    testWidgets('the filter opens as a panel', (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1366, 768));

      await tester.tap(find.text('Filter'));
      await settleFor(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(panel).width, GlassSheet.panelMaxWidth);
    });

    testWidgets('the event list opens as a panel', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(id: 1, type: 'message', objectId: 1),
          buildNotification(id: 2, type: 'message', objectId: 2),
        ]).rebuild((b) => b.noInternet = false),
        size: const Size(1366, 768),
      );

      await tester.tap(find.byKey(const Key('event-banner-more')));
      await settleFor(tester);

      expect(find.byType(EventListSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a panel closes with Escape', (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1366, 768));

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleFor(tester);

      expect(find.byType(EntryDetailsSheet), findsNothing);
    });

    testWidgets('a panel is solid without blur', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1366, 768));

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a tablet gets panels as well', (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(820, 1000));

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a phone keeps its sheet', (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('the profile menu sits beside the rail, with the same corners',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1366, 768));

      await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
      await settleFor(tester);

      expect(find.byType(ProfileMenuContainer), findsOneWidget);
      expect(tester.getRect(panel).left, appNavigationRailExtent);
      expect(tester.getRect(panel).bottom, 768 - DesignTokens.gutter);
    });
  });

  group('desktop interaction', () {
    AppState online() => _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ]).rebuild((b) => b.noInternet = false);

    Future<void> pumpDesktop(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await _pumpDashboard(tester, online(), size: const Size(1366, 768));
    }

    Future<TestGesture> mouseOn(WidgetTester tester) async {
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      return mouse;
    }

    testWidgets('clickable surfaces show the click cursor', (tester) async {
      await pumpDesktop(tester);
      final mouse = await mouseOn(tester);

      for (final target in [
        find.byKey(const ValueKey('compact-row-open-1')),
        find.byKey(const ValueKey('compact-row-check-1')),
        find.byKey(ValueKey('day-add-entry-$_today')),
        find.byKey(const ValueKey('app-navigation-grades')),
        find.byType(EventBanner),
        find.text('Filter'),
      ]) {
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
          reason: target.describeMatch(Plurality.one),
        );
      }
      debugDefaultTargetPlatformOverride = null;
    });

    Iterable<GlassFocusRingPainter> highlights(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<GlassFocusRingPainter>();

    testWidgets('a row reacts to the mouse as a whole', (tester) async {
      await pumpDesktop(tester);
      expect(highlights(tester), isEmpty);
      final mouse = await mouseOn(tester);

      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('compact-row-open-1'))),
      );
      await tester.pump();

      final scheme =
          Theme.of(tester.element(find.byType(CompactDayWidget))).colorScheme;
      final highlight = highlights(tester).single;
      expect(highlight.tint, scheme.onExam.withValues(alpha: 0.06));
      expect(highlight.ring, isNull);
      expect(highlight.shape, isA<StadiumBorder>());

      // Ink would only cover a rectangle of one of the two targets.
      final open = tester.widget<InkWell>(
        find.byKey(const ValueKey('compact-row-open-1')),
      );
      expect(open.hoverColor, Colors.transparent);
      expect(open.focusColor, Colors.transparent);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(highlights(tester), isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the notepad has a round highlight of its own', (tester) async {
      await pumpDesktop(tester);

      final check = tester.widget<InkWell>(
        find.byKey(const ValueKey('compact-row-check-1')),
      );
      expect(check.customBorder, isA<CircleBorder>());
      expect(check.focusColor, check.hoverColor);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('tooltips name the destinations of the rail', (tester) async {
      await pumpDesktop(tester);

      final mouse = await mouseOn(tester);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('app-navigation-calendar'))),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Kalender'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the keyboard gets a clear ring around a row', (tester) async {
      await pumpDesktop(tester);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      expect(highlights(tester), isEmpty);

      Focus.of(tester.element(find
              .descendant(
                of: find.byKey(const ValueKey('compact-row-open-1')),
                matching: find.byType(ConstrainedBox),
              )
              .first))
          .requestFocus();
      await tester.pump();

      expect(highlights(tester).single.ring, isNotNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('controls show their focus with a ring', (tester) async {
      await pumpDesktop(tester);
      final scheme =
          Theme.of(tester.element(find.byType(CompactDayWidget))).colorScheme;

      final side = glassFocusSide(scheme);
      expect(side.resolve({WidgetState.focused})?.color, scheme.primary);
      expect(side.resolve({WidgetState.focused})?.width, 2);
      expect(side.resolve({}), isNull);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Tab walks through the rail and the rows', (tester) async {
      await pumpDesktop(tester);

      final visited = <String>{};
      for (var step = 0; step < 24; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context?.widget;
        visited.add('$focus'.split('(').first);
        final key = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<InkWell>()
            ?.key;
        if (key != null) visited.add('$key');
      }

      expect(
        visited.where((value) => value.contains('compact-row')),
        isNotEmpty,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a right click on a card still opens its menu', (tester) async {
      await pumpDesktop(tester);

      await tester.tap(
        find.byType(DashboardSummaryCard).first,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await settleFor(tester);

      expect(find.byType(PopupMenuItem<Object?>), findsNothing);
      expect(find.byType(PopupMenuDivider), findsWidgets);
      debugDefaultTargetPlatformOverride = null;
    });

    for (final (name, finder) in [
      ('settings', () => find.byType(SettingsPageContainer)),
    ]) {
      testWidgets('$name keeps a readable width', (tester) async {
        final store = await _pumpDashboard(
          tester,
          _dashboardState(),
          size: const Size(1920, 1080),
          withMiddleware: true,
        );

        await store.actions.routingActions.showSettings();
        await settleFor(tester);

        expect(finder(), findsOneWidget);
        final content = find.descendant(
          of: find.byType(NewDesignReadable),
          matching: find.byType(ListView),
        );
        expect(
          tester.getSize(content.first).width,
          DesignTokens.contentMaxWidth,
        );
        await _finish(tester);
      });
    }
  });

  group('light of the glass', () {
    // Curves are not rasterised perfectly alike on both sides. Light from the
    // side differs by far more, as the control below shows.
    const antialiasing = 12;

    final schemes = [
      AppPalette.scheme(brightness: Brightness.light, amoled: false),
      AppPalette.scheme(brightness: Brightness.dark, amoled: false),
      AppPalette.scheme(brightness: Brightness.dark, amoled: true),
    ];

    /// The pixels of [paint] on a canvas of [size], in RGBA.
    Future<ByteData> render(
      WidgetTester tester,
      Size size,
      void Function(Canvas canvas) paint,
    ) async =>
        (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          paint(Canvas(recorder));
          final image = await recorder
              .endRecording()
              .toImage(size.width.toInt(), size.height.toInt());
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!;
        }))!;

    /// How far the pixels of a render differ from the ones across its middle.
    int mirrorDifference(ByteData pixels, Size size) {
      final width = size.width.toInt();
      var worst = 0;
      for (var y = 0; y < size.height; y++) {
        for (var x = 0; x < width ~/ 2; x++) {
          for (var channel = 0; channel < 4; channel++) {
            final left = pixels.getUint8((y * width + x) * 4 + channel);
            final right =
                pixels.getUint8((y * width + width - 1 - x) * 4 + channel);
            worst = math.max(worst, (left - right).abs());
          }
        }
      }
      return worst;
    }

    test('all gradients run straight down', () {
      for (final scheme in schemes) {
        final light = GlassLight.of(scheme);
        const shape = StadiumBorder();
        final rim = GlassRimPainter(
          shape: shape,
          rim: GlassRim.around,
          light: light,
        );
        final gradients = [
          GlassSheenPainter(shape: shape, light: light).gradient,
          rim.aroundGradient,
          EventEdgePainter(
            color: scheme.primary,
            animation: const AlwaysStoppedAnimation(0.5),
          ).bandGradient(0.5),
        ];
        for (final gradient in gradients) {
          expect((gradient.begin as Alignment).x, 0);
          expect((gradient.end as Alignment).x, 0);
          expect((gradient.begin as Alignment).y, -1);
        }
      }
    });

    test('the line below the header is the same on both sides', () {
      for (final scheme in schemes) {
        final gradient = GlassRimPainter(
          shape: const RoundedRectangleBorder(),
          rim: GlassRim.bottom,
          light: GlassLight.of(scheme),
        ).bottomGradient;
        expect(gradient.stops, isNull);
        expect(gradient.colors.first, gradient.colors.last);
      }
    });

    test('the top of the rim is only very slightly the stronger one', () {
      for (final scheme in schemes) {
        final colors = GlassRimPainter(
          shape: const StadiumBorder(),
          rim: GlassRim.around,
          light: GlassLight.of(scheme),
        ).aroundGradient.colors;
        expect(colors[0].a, greaterThan(colors[1].a));
        expect(colors[0].a / colors[1].a, lessThanOrEqualTo(1.2));
      }
    });

    /// What the rim adds to the fill, at the middle of each side of a surface.
    /// Outside of the stroke, the render is the bare [fill].
    Future<({double top, double bottom, double left, double right})> rimLight(
      WidgetTester tester,
      ColorScheme scheme,
      ShapeBorder shape,
      Size size,
    ) async {
      final light = GlassLight.of(scheme);
      final fill = scheme.surfaceContainer;
      final pixels = await render(tester, size, (canvas) {
        canvas.drawRect(Offset.zero & size, Paint()..color = fill);
        GlassRimPainter(shape: shape, rim: GlassRim.around, light: light)
            .paint(canvas, size);
      });
      final width = size.width.toInt();
      final height = size.height.toInt();
      // In light themes the highlight lies next to the outline, so of the
      // pixels of the rim, the one that differs from the fill the most counts.
      double lift(int x, int y, int stepX, int stepY) {
        var most = 0.0;
        for (var step = 0; step < 3; step++) {
          final offset = ((y + step * stepY) * width + x + step * stepX) * 4;
          final difference = [
            (pixels.getUint8(offset) - fill.r * 255).abs(),
            (pixels.getUint8(offset + 1) - fill.g * 255).abs(),
            (pixels.getUint8(offset + 2) - fill.b * 255).abs(),
          ].reduce(math.max);
          most = math.max(most, difference);
        }
        return most;
      }

      return (
        top: lift(width ~/ 2, 0, 0, 1),
        bottom: lift(width ~/ 2, height - 1, 0, -1),
        left: lift(0, height ~/ 2, 1, 0),
        right: lift(width - 1, height ~/ 2, -1, 0),
      );
    }

    testWidgets('the rim is lit nearly evenly all around', (tester) async {
      for (final scheme in schemes) {
        for (final (shape, size) in const <(ShapeBorder, Size)>[
          (StadiumBorder(), Size(120, 44)),
          (StadiumBorder(), Size(388, 56)),
          (CircleBorder(), Size(40, 40)),
          (
            RoundedRectangleBorder(
              borderRadius: DesignTokens.cardBorderRadius,
            ),
            Size(388, 209),
          ),
          (
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(28)),
            ),
            Size(412, 640),
          ),
        ]) {
          final rim = await rimLight(tester, scheme, shape, size);
          expect(rim.bottom, greaterThan(0));
          expect(rim.top / rim.bottom, lessThanOrEqualTo(1.2));
          expect(rim.top / rim.bottom, greaterThanOrEqualTo(0.95));
          expect((rim.left - rim.right).abs(), lessThan(antialiasing));
          final middle = (rim.top + rim.bottom) / 2;
          expect(rim.left / middle, inInclusiveRange(0.85, 1.15));
        }
      }
    });

    testWidgets('the rim of a sheet runs down its sides without a stop',
        (tester) async {
      const size = Size(412, 640);
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      );
      for (final scheme in schemes) {
        final fill = scheme.surfaceContainer;
        final pixels = await render(tester, size, (canvas) {
          canvas.drawRect(Offset.zero & size, Paint()..color = fill);
          GlassRimPainter(
            shape: shape,
            rim: GlassRim.around,
            light: GlassLight.of(scheme),
          ).paint(canvas, size);
        });
        double side(int x, int y) => (pixels.getUint8(
                  (y * size.width.toInt() + x) * 4 + 1,
                ) -
                fill.g * 255)
            .abs();
        // From just below the corners, where the old light ran out, to the end.
        final depths = [32, 40, 60, 100, 200, 400, 630];
        final left = [for (final y in depths) side(0, y)];
        final right = [for (final y in depths) side(411, y)];
        expect(left.reduce(math.min), greaterThan(0));
        expect(
          left.reduce(math.max) / left.reduce(math.min),
          lessThanOrEqualTo(1.2),
        );
        for (var index = 0; index < depths.length; index++) {
          expect((left[index] - right[index]).abs(), lessThan(antialiasing));
        }
      }
    });

    testWidgets('the rim of a sheet lies on the edge of the screen',
        (tester) async {
      for (final width in const [320.0, 412.0]) {
        await _pumpDashboard(
          tester,
          _dashboardState(),
          size: Size(width, 800),
        );
        await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
        await settleFor(tester, duration: const Duration(milliseconds: 600));
        final sheet = find.byKey(const Key('glass-sheet'));
        expect(tester.getRect(sheet).left, 0);
        expect(tester.getRect(sheet).right, width);
        // The first one is the rim of the sheet, the avatar has its own.
        final edge = tester.widget<GlassEdge>(
          find.descendant(of: sheet, matching: find.byType(GlassEdge)).first,
        );
        expect(edge.rim, GlassRim.around);
        // Only the glass inside has a rim, not the route around it as well.
        final material = tester.widget<Material>(find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first);
        expect(material.shape, isNot(isA<GlassRimBorder>()));
        Navigator.of(tester.element(find.byType(GlassSheet))).pop();
        await settleFor(tester, duration: const Duration(milliseconds: 600));
      }
      await _finish(tester);
    });

    testWidgets('all that floats above the page has the rim', (tester) async {
      await _pumpDashboard(tester, _dashboardState());
      final context = tester.element(find.byType(CompactDayWidget).first);
      final theme = Theme.of(context);
      expect(theme.dialogTheme.shape, isA<GlassRimBorder>());
      expect(theme.bottomSheetTheme.shape, isA<GlassRimBorder>());
      expect(theme.popupMenuTheme.shape, isA<GlassRimBorder>());
      expect(theme.datePickerTheme.shape, isA<GlassRimBorder>());
      expect(theme.timePickerTheme.shape, isA<GlassRimBorder>());
      expect(
        glassRimShape(context, const CircleBorder()),
        isA<GlassRimBorder>(),
      );
    });

    testWidgets('Legacy keeps its plain shapes', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(),
        size: const Size(1200, 800),
        newDesign: false,
      );
      final context = tester.element(find.byType(Sidebar).first);
      expect(Theme.of(context).bottomSheetTheme.shape, isNull);
      expect(Theme.of(context).popupMenuTheme.shape, isNull);
      expect(
        glassRimShape(context, const CircleBorder()),
        const CircleBorder(),
      );
    });

    testWidgets('high contrast keeps its plain shapes', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpDashboard(tester, _dashboardState());
      final context = tester.element(find.byType(CompactDayWidget).first);
      expect(Theme.of(context).bottomSheetTheme.shape, isNull);
      expect(Theme.of(context).datePickerTheme.shape, isNull);
    });

    testWidgets('a row below the bar does not colour its glass',
        (tester) async {
      tester.view.physicalSize = const Size(412, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final scheme = AppPalette.scheme(
        brightness: Brightness.dark,
        amoled: false,
      );

      Future<ByteData> barOver(Color behind) async {
        // Otherwise the shadow of the bar is painted as a solid slab.
        debugDisableShadows = false;
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: Material(
              color: scheme.surface,
              child: Stack(children: [
                // Just as wide as the bar, like a row of the list.
                Positioned(
                  left: DesignTokens.gutter,
                  right: DesignTokens.gutter,
                  bottom: 30,
                  height: 60,
                  child: ColoredBox(color: behind),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FloatingNavigationBar(
                    selected: AppDestination.grades,
                    onSelected: (_) {},
                    unreadMessages: 0,
                    userIcon: null,
                  ),
                ),
              ]),
            ),
          ),
        ));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final pixels = (await tester.runAsync(() async {
          final image = await render.toImage();
          final data =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          image.dispose();
          return data!;
        }))!;
        debugDisableShadows = true;
        return pixels;
      }

      final plain = await barOver(scheme.surface);
      final tinted = await barOver(const Color(0xFFFF5449));
      final bar = tester.getRect(find.byKey(const Key('app-navigation-bar')));
      int warmth(ByteData pixels, double x, double y) {
        final offset = (y.toInt() * 412 + x.toInt()) * 4;
        return pixels.getUint8(offset) - pixels.getUint8(offset + 2);
      }

      // Without the fade, the corners change by 165 and the glass by 18.
      for (final (x, y, limit) in [
        (bar.left + 8.5, bar.top + 7.5, 20),
        (bar.right - 9.5, bar.top + 7.5, 20),
        (bar.left + 14.0, bar.top + 12.0, 10),
        (bar.right - 14.0, bar.top + 12.0, 10),
      ]) {
        expect(
          (warmth(tinted, x, y) - warmth(plain, x, y)).abs(),
          lessThanOrEqualTo(limit),
        );
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the fade below the bar leaves the page tappable',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());
      final fade = find.byKey(const Key('app-navigation-fade'));
      expect(
        find.descendant(of: fade, matching: find.byType(IgnorePointer)),
        findsOneWidget,
      );
      final bar = tester.getRect(find.byKey(const Key('app-navigation-bar')));
      // It stays in the gap that content keeps to the bar.
      expect(tester.getTopLeft(fade).dy, greaterThanOrEqualTo(bar.top - 8));
      expect(tester.getSize(fade).width, 400);
    });

    testWidgets('a mirrored surface looks exactly the same', (tester) async {
      const size = Size(120, 60);
      for (final scheme in schemes) {
        final light = GlassLight.of(scheme);
        for (final shape in const <ShapeBorder>[
          StadiumBorder(),
          CircleBorder(),
          RoundedRectangleBorder(
            borderRadius: DesignTokens.cardBorderRadius,
          ),
        ]) {
          final pixels = await render(tester, size, (canvas) {
            GlassSheenPainter(shape: shape, light: light).paint(canvas, size);
            GlassRimPainter(shape: shape, rim: GlassRim.around, light: light)
                .paint(canvas, size);
          });
          expect(mirrorDifference(pixels, size), lessThan(antialiasing));
        }
      }
    });

    testWidgets('a lens is lit the same on its left and right', (tester) async {
      const canvasSize = Size(120, 80);
      for (final scheme in schemes) {
        for (final lens in const [Size(44, 44), Size(60, 44), Size(100, 42)]) {
          final pixels = await render(tester, canvasSize, (canvas) {
            canvas.translate(
              (canvasSize.width - lens.width) / 2,
              (canvasSize.height - lens.height) / 2,
            );
            GlassLensPainter(
              fill: navigationLensFill(scheme),
              shadow: scheme.shadow,
              light: GlassLight.of(scheme),
            ).paint(canvas, lens);
          });
          // Four layers add up on the curve. Light from the side reaches 40.
          expect(
            mirrorDifference(pixels, canvasSize),
            lessThan(antialiasing + 4),
          );
        }
      }
    });

    testWidgets('the mirror test sees light that comes from the side',
        (tester) async {
      const size = Size(120, 60);
      final pixels = await render(tester, size, (canvas) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            ).createShader(Offset.zero & size),
        );
      });
      expect(mirrorDifference(pixels, size), greaterThan(40));
    });

    testWidgets('the band on the edge of a banner falls down both sides',
        (tester) async {
      const size = Size(120, 60);
      final painter = EventEdgePainter(
        color: const Color(0xFF3972A6),
        animation: const AlwaysStoppedAnimation(0.5),
      );
      for (final progress in const [0.0, 0.3, 0.5, 1.0]) {
        final gradient = painter.bandGradient(progress);
        final pixels = await render(tester, size, (canvas) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              (Offset.zero & size).deflate(1),
              const Radius.circular(DesignTokens.cardRadius),
            ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..shader = gradient.createShader(Offset.zero & size),
          );
        });
        expect(mirrorDifference(pixels, size), lessThan(antialiasing));
      }
    });

    /// Every shadow that a decoration of the tree below [finder] casts.
    Iterable<BoxShadow> shadows(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .expand<BoxShadow>((decoration) => switch (decoration) {
              BoxDecoration(:final boxShadow?) => boxShadow,
              ShapeDecoration(:final shadows?) => shadows,
              _ => const [],
            });

    testWidgets('no shadow falls to the side', (tester) async {
      await _pumpDashboard(
          tester,
          _dashboardState(notifications: [
            buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
          ]));

      final all = shadows(tester);
      expect(all, isNotEmpty);
      for (final shadow in all) {
        expect(shadow.offset.dx, 0);
      }

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);
      for (final shadow in shadows(tester)) {
        expect(shadow.offset.dx, 0);
      }
    });

    testWidgets('every kind of surface uses the shared light', (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ]).rebuild((b) => b.noInternet = false),
      );

      for (final surface in [
        find.byKey(const Key('dashboard-app-header')),
        find.byKey(const Key('app-navigation-bar')),
        find.byKey(const Key('app-navigation-lens')),
        find.byKey(const ValueKey('compact-row-1')),
        find.byKey(ValueKey('day-add-entry-$_today')),
        find.byType(EventBanner),
        find.byType(DashboardSummaryCard).first,
      ]) {
        expect(
          find.descendant(of: surface, matching: find.byType(GlassEdge)),
          findsWidgets,
        );
      }
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('dashboard-header-box')),
          matching: find.byType(GlassEdge),
        ),
        findsWidgets,
      );
    });

    testWidgets('dialogs have the rim, but not in Legacy', (tester) async {
      await _pumpDashboard(tester, _dashboardState());
      expect(
        Theme.of(tester.element(find.byType(CompactDayWidget)))
            .dialogTheme
            .shape,
        isA<GlassRimBorder>(),
      );

      await _pumpDashboard(tester, _dashboardState(), newDesign: false);
      expect(
        Theme.of(tester.element(find.byType(DayWidget))).dialogTheme.shape,
        isNot(isA<GlassRimBorder>()),
      );
    });

    testWidgets('a dialog keeps the rim of the place it opens from',
        (tester) async {
      await _pumpDashboard(
        tester,
        _dashboardState().rebuild((b) => b.noInternet = false),
      );

      await tester.tap(find.byKey(ValueKey('day-add-entry-$_today')));
      await settleFor(tester);

      final dialog = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Material),
      );
      expect(
        tester.widget<Material>(dialog.first).shape,
        isA<GlassRimBorder>(),
      );
    });

    testWidgets('high contrast keeps plain dialogs', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpDashboard(tester, _dashboardState());

      expect(
        Theme.of(tester.element(find.byType(CompactDayWidget)))
            .dialogTheme
            .shape,
        isNot(isA<GlassRimBorder>()),
      );
    });
  });

  group('navigation lens', () {
    final lens = find.byKey(const Key('app-navigation-lens'));

    Future<ValueNotifier<AppDestination>> pumpBar(
      WidgetTester tester, {
      double width = 400,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final selected = ValueNotifier(AppDestination.dashboard);
      addTearDown(selected.dispose);
      await pumpApp(
        tester,
        store: createStore(newDesign: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder(
              valueListenable: selected,
              builder: (context, destination, _) => FloatingNavigationBar(
                selected: destination,
                onSelected: (tapped) => selected.value = tapped,
                unreadMessages: 0,
                userIcon: null,
              ),
            ),
          ),
        ),
      );
      return selected;
    }

    Finder item(AppDestination destination) =>
        find.byKey(ValueKey('app-navigation-${destination.name}'));

    for (final (name, platform) in const [
      ('touch', TargetPlatform.android),
      ('desktop', TargetPlatform.windows),
    ]) {
      for (final width in const [320.0, 400.0, 800.0]) {
        testWidgets('rests on the selected item at $width px on $name',
            (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final selected = await pumpBar(tester, width: width);
          final barRect =
              tester.getRect(find.byKey(const Key('app-navigation-bar')));

          for (final destination in AppDestination.values) {
            selected.value = destination;
            await tester.pumpAndSettle();
            final rect = tester.getRect(lens);
            expect(
              rect.center.dx,
              moreOrLessEquals(tester.getCenter(item(destination)).dx,
                  epsilon: 0.5),
            );
            expect(rect.left, greaterThanOrEqualTo(barRect.left));
            expect(rect.right, lessThanOrEqualTo(barRect.right));
            expect(rect.height, 44);
          }
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }

    testWidgets('slides over and stretches on the way', (tester) async {
      final selected = await pumpBar(tester);
      final rest = tester.getRect(lens);
      final target = tester.getCenter(item(AppDestination.extras)).dx;

      selected.value = AppDestination.extras;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final moving = tester.getRect(lens);
      expect(moving.center.dx, greaterThan(rest.center.dx));
      expect(moving.center.dx, lessThan(target));
      expect(moving.width, greaterThan(rest.width));
      expect(moving.height, lessThan(rest.height));

      await tester.pumpAndSettle();
      expect(tester.getRect(lens).width, moreOrLessEquals(rest.width));
      expect(
        tester.getRect(lens).center.dx,
        moreOrLessEquals(target, epsilon: 0.05),
      );
    });

    testWidgets('arrives without swinging past its place', (tester) async {
      final selected = await pumpBar(tester);
      final target = tester.getCenter(item(AppDestination.extras)).dx;

      selected.value = AppDestination.extras;
      await tester.pump();
      for (var frame = 0; frame < 90; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getCenter(lens).dx, lessThanOrEqualTo(target + 0.01));
      }
    });

    testWidgets('a tap moves the lens to the item, and nothing else moves',
        (tester) async {
      final selected = await pumpBar(tester);
      final calendar = item(AppDestination.calendar);
      final icons = find.descendant(
        of: find.byKey(const Key('app-navigation-bar')),
        matching: find.byType(Icon),
      );
      List<Rect> places() => icons.evaluate().map((element) {
            final box = element.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) & box.size;
          }).toList();
      final before = places();

      await tester.tap(calendar);
      expect(selected.value, AppDestination.calendar);
      await tester.pump();
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(places(), before);
      }
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(lens).dx,
        moreOrLessEquals(tester.getCenter(calendar).dx, epsilon: 0.05),
      );
      expect(places(), before);
    });

    testWidgets('a press alone shows nothing at all', (tester) async {
      final selected = await pumpBar(tester);
      final bar = find.byKey(const Key('app-navigation-bar'));
      final grades = item(AppDestination.grades);
      final rest = tester.getRect(lens);

      expect(
        find.descendant(of: bar, matching: find.byType(InkResponse)),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: bar, matching: find.byType(Transform)),
        findsNothing,
      );
      final gesture = await tester.startGesture(tester.getCenter(grades));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.getRect(lens), rest);
      }
      final material = Material.of(tester.element(grades)) as dynamic;
      expect(material.debugInkFeatures ?? const <Object>[], isEmpty);
      expect(selected.value, AppDestination.dashboard);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected.value, AppDestination.grades);
    });

    Iterable<GlassFocusRingPainter> marks(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GlassFocusRingPainter>();

    testWidgets('the mouse leaves a mark and the hand cursor', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpBar(tester);
      final scheme = Theme.of(tester.element(lens)).colorScheme;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      expect(marks(tester), isEmpty);

      await mouse.moveTo(tester.getCenter(item(AppDestination.grades)));
      await tester.pump();
      expect(marks(tester).single.tint,
          navigationHoverTint(scheme, onLens: false));
      expect(marks(tester).single.ring, isNull);
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await mouse.moveTo(tester.getCenter(item(AppDestination.dashboard)));
      await tester.pump();
      expect(
          marks(tester).single.tint, navigationHoverTint(scheme, onLens: true));

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(marks(tester), isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the keyboard gets a ring and can pick an item',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final selected = await pumpBar(tester);
      final scheme = Theme.of(tester.element(lens)).colorScheme;
      expect(marks(tester), isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(marks(tester).single.ring, navigationFocusRing(scheme));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(marks(tester).single.ring, navigationFocusRing(scheme));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected.value, AppDestination.grades);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selected.value, AppDestination.calendar);
      expect(
        tester.getCenter(lens).dx,
        moreOrLessEquals(
          tester.getCenter(item(AppDestination.calendar)).dx,
          epsilon: 0.05,
        ),
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('every item keeps a full touch target on a small phone',
        (tester) async {
      await pumpBar(tester, width: 320);
      for (final destination in AppDestination.values) {
        expect(tester.getSize(item(destination)), const Size.square(48));
      }
    });

    testWidgets('follows a new selection in mid-flight', (tester) async {
      final selected = await pumpBar(tester);

      selected.value = AppDestination.extras;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      selected.value = AppDestination.grades;
      await tester.pumpAndSettle();

      expect(
        tester.getRect(lens).center.dx,
        moreOrLessEquals(
          tester.getCenter(item(AppDestination.grades)).dx,
          epsilon: 0.05,
        ),
      );
    });

    testWidgets('jumps with reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final selected = await pumpBar(tester);
      final rest = tester.getRect(lens);

      selected.value = AppDestination.extras;
      await tester.pump();

      expect(tester.getRect(lens).width, moreOrLessEquals(rest.width));
      expect(
        tester.getRect(lens).center.dx,
        moreOrLessEquals(tester.getCenter(item(AppDestination.extras)).dx),
      );
    });

    testWidgets('is solid with an outline in high contrast mode',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpBar(tester);

      final scheme = Theme.of(tester.element(lens)).colorScheme;
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: lens, matching: find.byType(DecoratedBox)),
      );
      final decoration = box.decoration as ShapeDecoration;
      expect(decoration.color, scheme.primaryContainer);
      expect(
        (decoration.shape as StadiumBorder).side.color,
        scheme.onPrimaryContainer,
      );
      expect(_glassPaints(tester), isEmpty);
    });

    testWidgets('leaves the semantics of the items as they were',
        (tester) async {
      final handle = tester.ensureSemantics();
      final selected = await pumpBar(tester);

      selected.value = AppDestination.calendar;
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(item(AppDestination.calendar)),
        containsSemantics(
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
          tooltip: 'Kalender',
        ),
      );
      expect(
        tester.getSemantics(item(AppDestination.dashboard)),
        containsSemantics(
            isButton: true, isSelected: false, hasTapAction: true),
      );
      expect(find.byTooltip('Kalender'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the rail has the same glass and lens as the bar',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState(),
          size: const Size(1200, 800));

      final rail = find.byKey(const Key('app-navigation-rail'));
      expect(
        find.descendant(of: rail, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
      expect(tester.getRect(lens).height, greaterThan(44));
      expect(
        tester.getCenter(lens).dy,
        moreOrLessEquals(
          tester.getCenter(item(AppDestination.dashboard)).dy,
          epsilon: 0.5,
        ),
      );
      expect(tester.getRect(lens).width, 44);
    });

    Future<ValueNotifier<AppDestination>> pumpRail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final selected = ValueNotifier(AppDestination.dashboard);
      addTearDown(selected.dispose);
      await pumpApp(
        tester,
        store: createStore(newDesign: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder(
              valueListenable: selected,
              builder: (context, destination, _) => AppNavigationRail(
                selected: destination,
                onSelected: (_) {},
                unreadMessages: 0,
                userIcon: null,
              ),
            ),
          ),
        ),
      );
      return selected;
    }

    testWidgets('slides upright in the rail', (tester) async {
      final selected = await pumpRail(tester);
      final rest = tester.getRect(lens);
      final target = tester.getCenter(item(AppDestination.extras)).dy;

      selected.value = AppDestination.extras;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final moving = tester.getRect(lens);
      expect(moving.center.dy, greaterThan(rest.center.dy));
      expect(moving.center.dy, lessThan(target));
      expect(moving.height, greaterThan(rest.height));
      expect(moving.width, lessThan(rest.width));
      expect(moving.center.dx, moreOrLessEquals(rest.center.dx));

      await tester.pumpAndSettle();
      expect(
        tester.getCenter(lens).dy,
        moreOrLessEquals(target, epsilon: 0.05),
      );
    });

    testWidgets('jumps in the rail with reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final selected = await pumpRail(tester);

      selected.value = AppDestination.messages;
      await tester.pump();

      expect(
        tester.getCenter(lens).dy,
        moreOrLessEquals(tester.getCenter(item(AppDestination.messages)).dy),
      );
    });

    testWidgets('the wash of the dashboard continues below the rail only',
        (tester) async {
      final selected = await pumpRail(tester);
      final wash = find.descendant(
        of: find.byType(AppNavigationRail),
        matching: find.byType(DashboardBackdrop),
      );
      expect(tester.widget<DashboardBackdrop>(wash).visible, isTrue);

      selected.value = AppDestination.grades;
      await tester.pumpAndSettle();
      expect(tester.widget<DashboardBackdrop>(wash).visible, isFalse);
    });
  });

  group('a sheet in motion', () {
    tearDown(GlassPerformance.instance.reset);

    final sheetBlur = find.descendant(
      of: find.byKey(const Key('glass-sheet')),
      matching: find.byType(BackdropFilter),
    );
    bool blurs(WidgetTester tester) =>
        tester.widget<BackdropFilter>(sheetBlur).enabled;
    double tint(WidgetTester tester) => (tester
            .widget<DecoratedBox>(find
                .descendant(
                  of: find.byKey(const Key('glass-sheet')),
                  matching: find.byType(DecoratedBox),
                )
                .first)
            .decoration as BoxDecoration)
        .color!
        .a;

    /// Opens a sheet and counts what its content costs.
    Future<_SheetCosts> open(
      WidgetTester tester, {
      Size size = const Size(400, 800),
    }) async {
      await _pumpDashboard(tester, _dashboardState(), size: size);
      final costs = _SheetCosts();
      unawaited(showGlassSheet<void>(
        context: tester.element(find.byType(CompactDayWidget).first),
        builder: (_) => _CountingContent(costs),
      ));
      await tester.pump();
      return costs;
    }

    Future<void> frames(WidgetTester tester, int count) async {
      for (var frame = 0; frame < count; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    for (final (name, size) in const [
      ('sheet', Size(400, 800)),
      ('panel', Size(1200, 800)),
    ]) {
      testWidgets('the content of a $name is built and painted only once',
          (tester) async {
        final costs = await open(tester, size: size);
        await frames(tester, 40);

        expect(costs.states, 1);
        expect(costs.builds, 1);
        expect(costs.paints, 1);

        Navigator.of(tester.element(find.byType(GlassSheet))).pop();
        await tester.pump();
        await frames(tester, 30);
        expect(find.byType(GlassSheet), findsNothing);
        expect(costs.builds, 1);
        expect(costs.paints, 1);
      });

      testWidgets('a $name only blurs once it has settled', (tester) async {
        await open(tester, size: size);
        await frames(tester, 6);
        expect(blurs(tester), isFalse);
        expect(tint(tester), 1);

        await settleFor(tester, duration: const Duration(milliseconds: 600));
        expect(blurs(tester), isTrue);
        expect(tint(tester), moreOrLessEquals(DesignTokens.sheetOpacity));
      });
    }

    testWidgets('it stops blurring as soon as it closes', (tester) async {
      await open(tester);
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      Navigator.of(tester.element(find.byType(GlassSheet))).pop();
      await tester.pump();
      await frames(tester, 1);

      expect(blurs(tester), isFalse);
    });

    testWidgets('dragging pauses the blur, and it returns after a release',
        (tester) async {
      await open(tester);
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('glass-sheet'))),
      );
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(blurs(tester), isFalse);

      await gesture.up();
      await settleFor(tester, duration: const Duration(milliseconds: 800));
      expect(blurs(tester), isTrue);
      expect(tint(tester), moreOrLessEquals(DesignTokens.sheetOpacity));
    });

    testWidgets('with reduced motion the glass does not fade in',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester);
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(blurs(tester), isTrue);
      await tester.pump();

      expect(tint(tester), moreOrLessEquals(DesignTokens.sheetOpacity));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('without blur it never asks for it', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      await open(tester);
      await frames(tester, 6);
      expect(sheetBlur, findsNothing);

      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(sheetBlur, findsNothing);
      expect(tint(tester), 1);
    });
  });

  group('glass sheets', () {
    tearDown(GlassPerformance.instance.reset);

    Finder inSheet(Type type) => find.descendant(
          of: find.byType(GlassSheet),
          matching: find.byType(type),
        );

    testWidgets('the details of an entry blur what is behind them',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(inSheet(BackdropFilter), findsOneWidget);
    });

    testWidgets('the accent of a sheet is readable on its glass',
        (tester) async {
      await _pumpDashboard(tester, _dashboardState());
      final scheme =
          Theme.of(tester.element(find.byType(CompactDayWidget))).colorScheme;

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      final label = tester.widget<Text>(find.text('Deutsch'));
      expect(label.style?.color, scheme.onPrimaryContainer);
    });

    testWidgets('are solid once blur is off or in high contrast mode',
        (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);

      expect(find.byType(GlassSheet), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      final surface = tester.widget<DecoratedBox>(find
          .descendant(
            of: find.byKey(const Key('glass-sheet')),
            matching: find.byType(DecoratedBox),
          )
          .first);
      expect((surface.decoration as BoxDecoration).color!.a, 1);
    });

    testWidgets('can be dragged away and closed by a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester, _dashboardState());

      await tester.tap(find.byKey(const ValueKey('compact-row-open-1')));
      await settleFor(tester);
      expect(find.bySemanticsLabel('Schließen'), findsOneWidget);

      await tester.drag(find.byType(GlassSheet), const Offset(0, 500));
      await settleFor(tester);
      expect(find.byType(GlassSheet), findsNothing);
      handle.dispose();
    });

    testWidgets('Legacy keeps its plain filter sheet', (tester) async {
      await _pumpDashboard(tester, _dashboardState(), newDesign: false);

      await tester.tap(find.text('Filter'));
      await settleFor(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(GlassSheet), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('rows and navigation have labels', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester, _dashboardState());

      expect(
        find.bySemanticsLabel(RegExp('Deutsch, Test, Literarische Gattungen')),
        findsOneWidget,
      );
      for (final destination in ['Noten', 'Kalender', 'Mitteilungen']) {
        expect(find.byTooltip(destination), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('screen readers can activate rows, checkboxes and banners',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ]).rebuild((b) => b.noInternet = false),
      );

      for (final finder in [
        find.byKey(const ValueKey('compact-row-open-1')),
        find.byKey(const ValueKey('compact-row-check-1')),
        find.byType(EventBanner),
      ]) {
        expect(
          tester.getSemantics(finder),
          containsSemantics(hasTapAction: true),
        );
      }
      handle.dispose();
    });

    testWidgets('works with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpDashboard(
        tester,
        _dashboardState(notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ]),
        size: const Size(360, 700),
      );

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('dark mode and every language render without errors',
      (tester) async {
    for (final language in AppLanguage.values) {
      await tester
          .runAsync(() => AppLocalizations.delegate.load(language.locale));
      final state = _dashboardState(
        notifications: [
          buildNotification(type: 'message', objectId: 1, title: 'Hinweis'),
        ],
        updates: (b) => b.settingsState.languageCode = language.code,
      );
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        store: createStore(initialState: state, newDesign: true),
        home: DaysContainer(),
        themeMode: ThemeMode.dark,
      );
      // Switching the language loads its catalog from the asset bundle.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settleFor(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(CompactDayWidget), findsOneWidget);
    }
  });

  testWidgets('the legacy sidebar no longer shows Hausaufgaben twice',
      (tester) async {
    await _pumpDashboard(
      tester,
      _dashboardState(),
      size: const Size(1200, 800),
      newDesign: false,
    );

    final sidebar = find.byType(Sidebar);
    expect(
      find.descendant(of: sidebar, matching: find.text('Hausaufgaben')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('Dashboard')),
      findsOneWidget,
    );
  });

  test('the sidebar has its own dashboard label in every language', () async {
    for (final language in AppLanguage.values) {
      final l10n = await AppLocalizations.delegate.load(language.locale);
      expect(
        l10n.text('sidebar.dashboard'),
        isNot(l10n.text('sidebar.homework')),
      );
    }
  });
}
