import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/change_email_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/profile_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show navigatorKey, nestedNavKey, scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/change_email.dart';
import 'package:dr/ui/grade_calculator.dart';
import 'package:dr/ui/grades_chart_page.dart';
import 'package:dr/ui/grades_chart_page_new.dart';
import 'package:dr/ui/profile.dart';
import 'package:dr/ui/settings_page_widget.dart';
import 'package:dr/ui/target_grade_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

const _phone = Size(412, 900);

AppState _state() => buildGradesPageState().rebuild((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.profileState
        ..name = 'Anna Muster'
        ..username = 'anna'
        ..roleName = 'Schüler'
        ..email = 'anna@example.com';
      b.url = 'https://franziskanergymnasium.digitalesregister.it';
      b.noInternet = true;
    });

/// Root routes of the legacy design and of the fallback.
Route<dynamic>? _rootRoutes(RouteSettings settings) => switch (settings.name) {
      '/profile' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ProfileContainer(),
        ),
      '/change_email' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ChangeEmailContainer(),
        ),
      '/settings' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SettingsPageContainer(),
        ),
      '/gradesChart' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GradesChartPage(),
        ),
      '/gradeCalculator' => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GradeCalculator(),
        ),
      _ => null,
    };

Future<Store<AppState, AppStateBuilder, AppActions>> _pump(
  WidgetTester tester, {
  bool newDesign = true,
  Size size = _phone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(),
    newDesign: newDesign,
    withMiddleware: true,
  );
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    onGenerateRoute: _rootRoutes,
  );
  await settleFor(tester);
  return store;
}

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(seconds: 1));

Future<void> _openGrades(WidgetTester tester) async {
  scaffoldKey!.currentState!
      .selectContentWidget(const GradesPageContainer(), Pages.grades);
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await _settle(tester);
}

/// Lets the timers of the middleware run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

Pages _current() => scaffoldKey!.currentState!.currentSelected;

AppDestination _highlighted(WidgetTester tester) => tester
    .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
    .selected;

bool _rootCanPop() => navigatorKey!.currentState!.canPop();

bool _inShell(WidgetTester tester, Finder page) =>
    ResponsiveNavigationScope.isActive(tester.element(page));

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  group('new design', () {
    testWidgets('Profile opens inside the shell and back returns',
        (tester) async {
      await _pump(tester);
      await _openGrades(tester);

      await tester.tap(find.byKey(const ValueKey('app-navigation-profile')));
      await settleFor(tester);
      await tester.tap(find.byKey(const Key('profile-menu-header')));
      await _settle(tester);

      expect(find.byType(Profile), findsOneWidget);
      expect(_inShell(tester, find.byType(Profile)), isTrue);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(_highlighted(tester), AppDestination.profile);
      expect(_rootCanPop(), isFalse);
      expect(tester.takeException(), isNull);

      await _back(tester);
      expect(find.byType(Profile), findsNothing);
      expect(_current(), Pages.grades);
      expect(_highlighted(tester), AppDestination.grades);
      expect(openProfileShellPages.value, 0);
      await _finish(tester);
    });

    testWidgets('Profile ends above the floating bar', (tester) async {
      final store = await _pump(tester, size: const Size(412, 500));
      await store.actions.routingActions.showProfile();
      await _settle(tester);

      final list = find.descendant(
        of: find.byType(Profile),
        matching: find.byType(Scrollable),
      );
      await tester.fling(list.first, const Offset(0, -3000), 3000);
      await _settle(tester);
      final bar =
          tester.getTopLeft(find.byKey(const Key('app-navigation-bar'))).dy;
      expect(
        tester.getBottomLeft(find.byType(SwitchListTile).last).dy,
        lessThanOrEqualTo(bar),
      );
      await _finish(tester);
    });

    testWidgets('opening Profile again does not stack it', (tester) async {
      final store = await _pump(tester);
      await store.actions.routingActions.showProfile();
      await _settle(tester);
      await store.actions.routingActions.showProfile();
      await _settle(tester);

      expect(openProfileShellPages.value, 1);
      await _back(tester);
      expect(find.byType(Profile), findsNothing);
      expect(_current(), Pages.homework);
      await _finish(tester);
    });

    testWidgets('change email opens inside the shell and back returns',
        (tester) async {
      final store = await _pump(tester);
      await store.actions.routingActions.showProfile();
      await _settle(tester);
      await store.actions.routingActions.showChangeEmail();
      await _settle(tester);

      expect(find.byType(ChangeEmail), findsOneWidget);
      expect(_inShell(tester, find.byType(ChangeEmail)), isTrue);
      expect(_highlighted(tester), AppDestination.profile);
      expect(_rootCanPop(), isFalse);

      await _back(tester);
      expect(find.byType(ChangeEmail), findsNothing);
      expect(find.byType(Profile), findsOneWidget);
      expect(_highlighted(tester), AppDestination.profile);

      await _back(tester);
      expect(find.byType(Profile), findsNothing);
      expect(_highlighted(tester), AppDestination.dashboard);
      await _finish(tester);
    });

    testWidgets('a destination closes Profile', (tester) async {
      final store = await _pump(tester);
      await _openGrades(tester);
      await store.actions.routingActions.showProfile();
      await _settle(tester);
      await store.actions.routingActions.showChangeEmail();
      await _settle(tester);

      // The page below is the destination itself.
      await tester.tap(find.byKey(const ValueKey('app-navigation-grades')));
      await _settle(tester);
      expect(find.byType(ChangeEmail), findsNothing);
      expect(find.byType(Profile), findsNothing);
      expect(_current(), Pages.grades);
      expect(_highlighted(tester), AppDestination.grades);

      await store.actions.routingActions.showProfile();
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('app-navigation-messages')));
      await _settle(tester);
      expect(find.byType(Profile), findsNothing);
      expect(_current(), Pages.messages);
      // Nothing is left below the page.
      scaffoldKey!.currentState!.navigatorKey.currentState!.pop();
      await _settle(tester);
      expect(_current(), Pages.homework);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      expect(openProfileShellPages.value, 0);
      await _finish(tester);
    });

    testWidgets(
        '"Durchschnitt anpassen" opens the grades settings in the shell',
        (tester) async {
      await _pump(tester);
      await _openGrades(tester);

      await tester
          .ensureVisible(find.byKey(const Key('grades-display-options')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('grades-display-options')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('grades-average-settings')));
      await _settle(tester);

      final page = find.byKey(const Key('settings-grades-page'));
      expect(page, findsOneWidget);
      expect(_inShell(tester, page), isTrue);
      // Only the page asked for, not the whole settings below it.
      expect(find.byKey(const Key('settings-grades-tile')), findsNothing);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(_highlighted(tester), AppDestination.grades);
      expect(_rootCanPop(), isFalse);
      expect(tester.takeException(), isNull);

      await _back(tester);
      expect(page, findsNothing);
      expect(find.byType(SettingsPageWidget), findsNothing);
      expect(_current(), Pages.grades);
      expect(nestedNavKey.currentState!.canPop(), isTrue);
      await _finish(tester);
    });

    for (final (name, open, key) in [
      (
        'nicknames',
        (AppActions actions) =>
            actions.routingActions.showEditCalendarSubjectNicks(),
        'settings-subject-nicks-page',
      ),
      (
        'substitute teachers',
        (AppActions actions) =>
            actions.routingActions.showEditCalendarSubstituteSettings(),
        'settings-substitute-page',
      ),
    ]) {
      testWidgets('the calendar opens its $name settings in the shell',
          (tester) async {
        final store = await _pump(tester, size: const Size(700, 900));
        await tester.tap(find.byKey(const ValueKey('app-navigation-calendar')));
        await _settle(tester);
        expect(_current(), Pages.calendar);

        unawaited(open(store.actions));
        await _settle(tester);
        // The nickname page asks for a new one at once.
        if (_rootCanPop()) {
          navigatorKey!.currentState!.pop();
          await _settle(tester);
        }

        final page = find.byKey(Key(key));
        expect(page, findsOneWidget);
        expect(_inShell(tester, page), isTrue);
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        expect(_rootCanPop(), isFalse);
        expect(tester.takeException(), isNull);

        await _back(tester);
        expect(page, findsNothing);
        expect(find.byType(SettingsPageWidget), findsNothing);
        expect(_current(), Pages.calendar);
        await _finish(tester);
      });
    }

    testWidgets('switching the design keeps a page of the shell open once',
        (tester) async {
      final store = await _pump(tester);
      await _openGrades(tester);
      await store.actions.routingActions.showEditGradesAverageSettings();
      await _settle(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('settings-grades-page')), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await _settle(tester);
      await _back(tester);
      expect(find.byKey(const Key('settings-grades-page')), findsNothing);
      expect(_current(), Pages.grades);
      expect(_rootCanPop(), isFalse);
      await _finish(tester);
    });

    for (final (name, tile, page) in [
      ('chart', 'grades-chart-open', find.byType(GradesChartPageNew)),
      ('calculator', 'grades-calculator', find.byType(GradeCalculator)),
    ]) {
      testWidgets('the grades page opens the $name inside the shell',
          (tester) async {
        final store = await _pump(tester);
        await store.actions.settingsActions.showGradesDiagram(true);
        await _openGrades(tester);

        await tester.ensureVisible(find.byKey(Key(tile)));
        await tester.pump();
        await tester.tap(find.byKey(Key(tile)));
        await _settle(tester);

        expect(page, findsOneWidget);
        expect(_inShell(tester, page), isTrue);
        expect(find.byType(FloatingNavigationBar), findsOneWidget);
        expect(_highlighted(tester), AppDestination.grades);
        expect(_rootCanPop(), isFalse);
        expect(tester.takeException(), isNull);

        await _back(tester);
        expect(page, findsNothing);
        expect(_current(), Pages.grades);
        expect(_highlighted(tester), AppDestination.grades);
        expect(nestedNavKey.currentState!.canPop(), isTrue);
        await _finish(tester);
      });
    }

    testWidgets('the target calculator opens on top of the calculator',
        (tester) async {
      final store = await _pump(tester);
      await _openGrades(tester);
      await store.actions.routingActions.showGradeCalculator();
      await _settle(tester);
      // Asked for again, it is not stacked.
      await store.actions.routingActions.showGradeCalculator();
      await _settle(tester);

      await tester.tap(find.byKey(const Key('grade-calculator-open-target')));
      await _settle(tester);
      final target = find.byType(TargetGradeCalculator);
      expect(target, findsOneWidget);
      expect(_inShell(tester, target), isTrue);
      expect(_highlighted(tester), AppDestination.grades);

      await _back(tester);
      expect(target, findsNothing);
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
      await _back(tester);
      expect(find.byType(GradeCalculator), findsNothing);
      expect(_current(), Pages.grades);
      await _finish(tester);
    });

    testWidgets('a destination closes the chart and the calculators',
        (tester) async {
      final store = await _pump(tester);
      await _openGrades(tester);
      await store.actions.routingActions.showGradeCalculator();
      await _settle(tester);
      await tester.tap(find.byKey(const Key('grade-calculator-open-target')));
      await _settle(tester);

      // The page below is the destination itself.
      await tester.tap(find.byKey(const ValueKey('app-navigation-grades')));
      await _settle(tester);
      expect(find.byType(TargetGradeCalculator), findsNothing);
      expect(find.byType(GradeCalculator), findsNothing);
      expect(_current(), Pages.grades);

      await store.actions.routingActions.showGradesChart();
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('app-navigation-messages')));
      await _settle(tester);
      expect(find.byType(GradesChartPage), findsNothing);
      expect(_current(), Pages.messages);
      scaffoldKey!.currentState!.navigatorKey.currentState!.pop();
      await _settle(tester);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      await _finish(tester);
    });

    testWidgets('switching the design keeps the calculator open once',
        (tester) async {
      final store = await _pump(tester);
      await _openGrades(tester);
      await store.actions.routingActions.showGradeCalculator();
      await _settle(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      // Legacy draws it as before.
      expect(find.byType(Greeting), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await _settle(tester);
      expect(find.byKey(const Key('grade-calculator-welcome')), findsOneWidget);
      await _back(tester);
      expect(find.byType(GradeCalculator), findsNothing);
      expect(_current(), Pages.grades);
      expect(_rootCanPop(), isFalse);
      await _finish(tester);
    });
  });

  group('legacy design', () {
    testWidgets('the chart and the calculator stay root routes',
        (tester) async {
      final store = await _pump(tester, newDesign: false);
      await store.actions.routingActions.showGradesChart();
      await _settle(tester);
      expect(find.byType(GradesChartPage), findsOneWidget);
      expect(find.byType(GradesChartPageNew), findsNothing);
      expect(_rootCanPop(), isTrue);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      navigatorKey!.currentState!.pop();
      await _settle(tester);

      await store.actions.routingActions.showGradeCalculator();
      await _settle(tester);
      expect(find.byType(Greeting), findsOneWidget);
      expect(_rootCanPop(), isTrue);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      await _finish(tester);
    });

    testWidgets('Profile and change email stay root routes', (tester) async {
      final store = await _pump(tester, newDesign: false);
      await store.actions.routingActions.showProfile();
      await _settle(tester);

      expect(find.byType(Profile), findsOneWidget);
      expect(_rootCanPop(), isTrue);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      expect(openProfileShellPages.value, 0);

      await store.actions.routingActions.showChangeEmail();
      await _settle(tester);
      expect(find.byType(ChangeEmail), findsOneWidget);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      await _finish(tester);
    });

    testWidgets('the settings shortcuts open the root settings',
        (tester) async {
      final store = await _pump(tester, newDesign: false);
      await store.actions.routingActions.showEditGradesAverageSettings();
      await _settle(tester);

      expect(_rootCanPop(), isTrue);
      expect(nestedNavKey.currentState!.canPop(), isFalse);
      expect(find.byKey(const Key('settings-grades-page')), findsOneWidget);
      await _finish(tester);
    });
  });

  testWidgets('without a shell Profile falls back to the root route',
      (tester) async {
    final store = createStore(
      initialState: _state(),
      newDesign: true,
      withMiddleware: true,
    );
    await pumpApp(
      tester,
      store: store,
      home: const SizedBox(),
      onGenerateRoute: _rootRoutes,
    );
    await settleFor(tester);
    await store.actions.routingActions.showProfile();
    await _settle(tester);

    expect(find.byType(Profile), findsOneWidget);
    expect(_rootCanPop(), isTrue);
    await _finish(tester);
  });

  testWidgets('without a shell the calculator falls back to the root route',
      (tester) async {
    final store = createStore(
      initialState: _state(),
      newDesign: true,
      withMiddleware: true,
    );
    await pumpApp(
      tester,
      store: store,
      home: const SizedBox(),
      onGenerateRoute: _rootRoutes,
    );
    await settleFor(tester);
    await store.actions.routingActions.showGradeCalculator();
    await _settle(tester);

    // Outside the shell it is the page of Legacy, as before.
    expect(find.byType(Greeting), findsOneWidget);
    expect(_rootCanPop(), isTrue);
    await _finish(tester);
  });
}
