import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/config.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/profile_menu_container.dart';
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
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/notepad_mark.dart';
import 'package:dr/ui/profile_menu.dart';
import 'package:dr/ui/sidebar.dart';
import 'package:dr/ui/sorted_grades_widget.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter/services.dart';
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
        final lens = Color.alphaBlend(navigationLensFill(scheme), bar);
        for (final surface in [lens, lit(lens)]) {
          expect(AppPalette.contrastRatio(scheme.onPrimaryContainer, surface),
              greaterThanOrEqualTo(4.5));
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
        final button = tester.widget<IconButton>(
            find.byKey(ValueKey('app-navigation-${destination.name}')));
        expect(button.tooltip, isNotEmpty);
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
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(AppDestination.values.length));
      expect(rail.selectedIndex, AppDestination.dashboard.index);
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

      await tester.tap(find.text('Profil'));
      await settleFor(tester);

      expect(find.byType(ProfileMenuContainer), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('switches to another account', (tester) async {
      final store = await _pumpDashboard(tester, profileState());
      final selected = <int>[];
      final menu = ProfileMenu(
        name: 'anna',
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
