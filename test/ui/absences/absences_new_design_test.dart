// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart' show Store;
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/absences_page.dart';
import 'package:dr/ui/absences_page_new.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

const _phone = Size(412, 900);

AbsenceGroup _group(
  UtcDateTime date,
  List<int> hours,
  AbsenceJustified justified, {
  String? reason,
  String? signature,
}) =>
    AbsenceGroup((b) => b
      ..date = date
      ..reason = reason
      ..reasonSignature = signature
      ..reasonTimestamp =
          signature == null ? null : date.add(const Duration(days: 1))
      ..justified = justified
      ..hours = hours.length
      ..minutes = 0
      ..absences = ListBuilder<Absence>([
        for (final hour in hours.reversed)
          Absence((a) => a
            ..date = date
            ..hour = hour
            ..minutes = 50
            ..minutesCameTooLate = 0
            ..minutesLeftTooEarly = 0),
      ]));

/// Statistics, a future absence and a justified, an unjustified and a
/// pending absence.
AppState _state({
  bool empty = false,
  bool withStatistic = true,
  bool canEdit = true,
  bool noInternet = false,
  bool loadFailed = false,
  String languageCode = 'de',
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
      b.noInternet = noInternet;
      b.absencesState
        ..canEdit = canEdit
        ..loadFailed = loadFailed
        ..lastFetched = withStatistic ? UtcDateTime(2026, 11, 10) : null
        ..statistic = !withStatistic
            ? null
            : (AbsenceStatisticBuilder()
              ..counter = empty ? 0 : 7
              ..counterForSchool = empty ? 0 : 1
              ..delayed = empty ? 0 : 2
              ..justified = empty ? 0 : 4
              ..notJustified = empty ? 0 : 2
              ..percentage = empty ? '0' : '2.5')
        ..futureAbsences = ListBuilder<FutureAbsence>(empty
            ? const <FutureAbsence>[]
            : [
                FutureAbsence((f) => f
                  ..id = 10
                  ..justified = AbsenceJustified.notYetJustified
                  ..reason = 'Arzttermin'
                  ..startDate = UtcDateTime(2026, 11, 20)
                  ..endDate = UtcDateTime(2026, 11, 20)
                  ..startHour = 2
                  ..endHour = 4),
              ])
        ..absences = ListBuilder<AbsenceGroup>(empty
            ? const <AbsenceGroup>[]
            : [
                _group(UtcDateTime(2026, 11, 4), [1, 2],
                    AbsenceJustified.notYetJustified),
                _group(UtcDateTime(2026, 10, 21), [3, 4],
                    AbsenceJustified.justified,
                    reason: 'Grippe', signature: 'Maria Huber'),
                _group(UtcDateTime(2026, 10, 9), [1],
                    AbsenceJustified.notJustified),
              ]);
    });

typedef _Store = Store<AppState, AppStateBuilder, AppActions>;

/// Opens the absences as Extras does, below the shell of the new design.
/// [page] builds a page in place of the container, to see what it calls.
Future<_Store> _pumpAbsences(
  WidgetTester tester, {
  AppState? state,
  Widget Function(_Store store)? page,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  bool newDesign = true,
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
  scaffoldKey!.currentState!.selectContentWidget(
    page?.call(store) ?? const AbsencesPageContainer(),
    Pages.absences,
  );
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

/// The page with callbacks that record what they get.
Widget Function(_Store) _recording({
  List<Map<String, dynamic>>? added,
  List<FutureAbsence>? removed,
  List<String>? retried,
}) =>
    (store) => AbsencesPageNew(
          state: store.state.absencesState,
          noInternet: store.state.noInternet,
          onAddFutureAbsence: (payload) => added?.add(payload),
          onRemoveFutureAbsence: (absence) => removed?.add(absence),
          onRetry: () => retried?.add('retry'),
        );

Finder _key(String key) => find.byKey(Key(key));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.descendant(
      of: _key('absences-list'),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(finder);
  await settleFor(tester);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 11, 11));
  });

  tearDown(resetTestState);

  group('design switch', () {
    testWidgets('the new design shows the new page', (tester) async {
      await _pumpAbsences(tester);

      expect(find.byType(AbsencesPageNew), findsOneWidget);
      expect(find.byType(AbsencesPage), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(LastFetchedOverlay), findsNothing);
      expect(_key('absences-app-header'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('Legacy shows the old page', (tester) async {
      await _pumpAbsences(tester, newDesign: false);

      expect(find.byType(AbsencesPage), findsOneWidget);
      expect(find.byType(AbsencesPageNew), findsNothing);
      expect(find.text('Statistik'), findsOneWidget);
    });

    testWidgets('switching applies at once, in both directions',
        (tester) async {
      final store = await _pumpAbsences(tester);

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(AbsencesPage), findsOneWidget);
      expect(find.byType(AbsencesPageNew), findsNothing);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(AbsencesPageNew), findsOneWidget);
      expect(find.byType(AbsencesPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('figures, future absences and the history', (tester) async {
      final store = await _pumpAbsences(tester);

      expect(_key('absences-overview'), findsOneWidget);
      // The figures the selector counts from the entries, as legacy shows.
      final statistic =
          appSelectors.absenceStatistics(store.state.absencesState).statistic;
      for (final (key, value) in [
        ('absences-figure-counter', statistic.counter),
        ('absences-figure-not-justified', statistic.notJustified),
        ('absences-figure-delays', statistic.delayed),
        ('absences-figure-school', statistic.counterForSchool),
      ]) {
        expect(
          find.descendant(of: _key(key), matching: find.text('$value')),
          findsOneWidget,
        );
      }
      expect(find.byType(FutureAbsenceEntry), findsOneWidget);
      expect(find.text('Arzttermin'), findsOneWidget);

      await _reveal(tester, find.text('Grippe'));
      expect(find.byType(AbsenceEntry), findsNWidgets(3));
      expect(find.text('Nicht entschuldigt'), findsWidgets);
      expect(find.text('Noch nicht entschuldigt'), findsWidgets);
      // Only the pending absence without a reason can be justified.
      expect(_key('absences-justify'), findsOneWidget);
    });

    testWidgets('the charts open on a phone, and the pie on request',
        (tester) async {
      await _pumpAbsences(tester);

      expect(_key('absences-status'), findsNothing);
      expect(_key('absences-history'), findsNothing);
      await tester.tap(_key('absences-charts-toggle'));
      await settleFor(tester);
      expect(_key('absences-status'), findsOneWidget);
      expect(_key('absences-history'), findsOneWidget);
      expect(find.byType(charts.BarChart), findsOneWidget);

      await tester.tap(find.text('Kreisdiagramm'));
      await settleFor(tester);
      expect(_key('absences-pie'), findsOneWidget);
      expect(find.byType(charts.PieChart<String>), findsOneWidget);
      await tester.tap(find.text('Ausblenden'));
      await settleFor(tester);
      expect(_key('absences-pie'), findsNothing);
    });

    testWidgets('the justification sheet requires reason and signature',
        (tester) async {
      final store = await _pumpAbsences(tester);
      await _reveal(tester, _key('absences-justify'));

      await tester.tap(_key('absences-justify'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      FilledButton save() =>
          tester.widget<FilledButton>(_key('absence-justification-save'));
      expect(save().onPressed, isNull);

      await tester.enterText(
          _key('absence-justification-reason'), 'Bauchschmerzen');
      await tester.pump();
      expect(save().onPressed, isNull);
      await tester.enterText(
          _key('absence-justification-signature'), 'Maria Huber');
      await tester.pump();
      expect(save().onPressed, isNotNull);

      await tester.tap(_key('absence-justification-save'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsNothing);
      // Without middleware the request goes nowhere, but the page is still
      // there and nothing failed.
      expect(store.state.absencesState.absences, hasLength(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling the justification sends nothing', (tester) async {
      await _pumpAbsences(tester);
      await _reveal(tester, _key('absences-justify'));

      await tester.tap(_key('absences-justify'));
      await settleFor(tester);
      await tester.tap(find.text('Abbrechen'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsNothing);
    });

    testWidgets('a future absence is recorded in a glass sheet',
        (tester) async {
      final added = <Map<String, dynamic>>[];
      await _pumpAbsences(tester, page: _recording(added: added));

      await tester.tap(_key('absences-add-future'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Voraus-Absenz eintragen'), findsOneWidget);

      await tester.enterText(_key('future-absence-reason'), 'Arzttermin');
      await tester.enterText(_key('future-absence-signature'), 'Maria Huber');
      await tester.pump();
      await tester.tap(find.text('Ganzer Tag'));
      await settleFor(tester);
      await tester.tap(_key('future-absence-save'));
      await settleFor(tester);

      expect(added, hasLength(1));
      final payload = added.single['futureAbsence'] as Map<String, dynamic>;
      expect(payload['reason'], 'Arzttermin');
      expect(payload['reason_signature'], 'Maria Huber');
      expect(payload['startTime'], 1);
      expect(payload['endTime'], 20);
    });

    testWidgets('the date picker of the sheet opens and closes',
        (tester) async {
      await _pumpAbsences(tester, page: _recording());
      await tester.tap(_key('absences-add-future'));
      await settleFor(tester);

      await tester.tap(find.text('Enddatum'));
      await settleFor(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settleFor(tester);
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(GlassPanel), findsOneWidget);
    });

    testWidgets('a future absence can be deleted', (tester) async {
      final removed = <FutureAbsence>[];
      await _pumpAbsences(tester, page: _recording(removed: removed));

      await tester.tap(_key('absences-future-remove'));
      await tester.pump();
      expect(removed.single.id, 10);
    });

    testWidgets('without the right to edit, nothing can be recorded',
        (tester) async {
      await _pumpAbsences(tester, state: _state(canEdit: false));

      expect(_key('absences-add-future'), findsNothing);
      expect(_key('absences-future-remove'), findsNothing);
      await _reveal(tester, find.text('Grippe'));
      expect(_key('absences-justify'), findsNothing);
    });

    testWidgets('offline, recording waits for the connection', (tester) async {
      await _pumpAbsences(tester, state: _state(noInternet: true));

      final add = tester.widget<FilledButton>(_key('absences-add-future'));
      expect(add.onPressed, isNull);
    });
  });

  group('states', () {
    testWidgets('a failed first load offers to try again', (tester) async {
      final retried = <String>[];
      await _pumpAbsences(
        tester,
        state: _state(withStatistic: false, loadFailed: true),
        page: _recording(retried: retried),
      );

      expect(_key('absences-load-failed'), findsOneWidget);
      expect(find.byType(GlassStateCard), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
          find.text('Absenzen konnten nicht geladen werden.'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      expect(retried, ['retry']);
    });

    testWidgets('offline without data', (tester) async {
      await _pumpAbsences(
        tester,
        state: _state(withStatistic: false, noInternet: true),
      );

      expect(_key('absences-offline'), findsOneWidget);
      expect(find.byType(LastFetchedOverlay), findsNothing);
    });

    testWidgets('offline with data shows a hint above the list',
        (tester) async {
      await _pumpAbsences(tester, state: _state(noInternet: true));

      expect(_key('absences-last-fetched'), findsOneWidget);
      expect(find.byType(GlassOfflineHint), findsOneWidget);
      expect(find.byType(FutureAbsenceEntry), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the data and offers a retry',
        (tester) async {
      final retried = <String>[];
      await _pumpAbsences(
        tester,
        state: _state(loadFailed: true),
        page: _recording(retried: retried),
      );

      expect(_key('absences-refresh-failed'), findsOneWidget);
      expect(find.byType(FutureAbsenceEntry), findsOneWidget);
      await tester.tap(find.descendant(
        of: _key('absences-refresh-failed'),
        matching: find.byType(TextButton),
      ));
      await tester.pump();
      expect(retried, ['retry']);
    });

    testWidgets('no absences yet still offer the first one', (tester) async {
      final added = <Map<String, dynamic>>[];
      await _pumpAbsences(
        tester,
        state: _state(empty: true),
        page: _recording(added: added),
      );

      expect(_key('absences-empty'), findsOneWidget);
      expect(find.text('Noch keine Absenzen'), findsOneWidget);
      await tester.tap(find.text('Voraus-Absenz'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
    });

    testWidgets('while loading, the bar shows below the header',
        (tester) async {
      await _pumpAbsences(
        tester,
        state: _state(withStatistic: false),
      );

      expect(
        tester.widget<GlassPage>(find.byType(GlassPage)).loading,
        isTrue,
      );
      expect(find.byType(GlassStateCard), findsNothing);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the list ends above the bar', (tester) async {
      await _pumpAbsences(tester, size: const Size(360, 640));

      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      final header = tester.getRect(_key('absences-app-header'));
      expect(header.top, 0);
      expect(
        tester.getRect(_key('absences-add-future')).top,
        greaterThanOrEqualTo(header.bottom),
      );
      await tester.drag(_key('absences-list'), const Offset(0, -3000));
      await settleFor(tester);
      final last = find.byType(AbsenceEntry).last;
      expect(
        tester.getRect(last).bottom,
        lessThanOrEqualTo(tester.getRect(_key('app-navigation-bar')).top),
      );
    });

    testWidgets('at 1280 x 800 the statistics stand beside the list',
        (tester) async {
      await _pumpAbsences(tester, size: const Size(1280, 800));

      expect(find.byType(AppNavigationRail), findsOneWidget);
      final side = _key('dashboard-side-column');
      expect(
        find.descendant(of: side, matching: _key('absences-overview')),
        findsOneWidget,
      );
      // Beside the list the charts need no button.
      expect(_key('absences-charts-toggle'), findsNothing);
      expect(_key('absences-status'), findsOneWidget);
      expect(_key('absences-history'), findsOneWidget);
      final list = tester.getRect(find.byType(FutureAbsenceEntry));
      expect(list.left, greaterThan(tester.getRect(side).right));
      final header = tester.getRect(_key('absences-app-header'));
      expect(header.top, DesignTokens.gutter);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 800 x 600 one column below a floating header',
        (tester) async {
      await _pumpAbsences(tester, size: const Size(800, 600));

      expect(_key('dashboard-side-column'), findsNothing);
      final header = tester.getRect(_key('absences-app-header'));
      expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
      expect(tester.getRect(_key('absences-overview')).top,
          greaterThanOrEqualTo(header.bottom));
    });

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('320 px, text at $scale, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpAbsences(
            tester,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(_key('absences-charts-toggle'));
          await settleFor(tester);
          await tester.drag(_key('absences-list'), const Offset(0, -400));
          await settleFor(tester);
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(_key('absences-overview')).width,
            320 - 2 * DesignTokens.gutter,
          );
        });
      }
    }

    testWidgets('the sheet fits 320 px with text at 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpAbsences(tester, size: const Size(320, 640));

      await tester.tap(_key('absences-add-future'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the back button returns to where the page came from',
        (tester) async {
      await _pumpAbsences(tester);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester);
      expect(find.byType(AbsencesPageNew), findsNothing);
    });
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pumpAbsences(tester);

      expect(
        find.descendant(
          of: _key('absences-list'),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('high contrast has no blur and no light, ${themeMode.name}',
          (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpAbsences(tester, themeMode: themeMode);

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AbsencesPageNew),
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

    testWidgets('reduced motion opens the sheet without trouble',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpAbsences(tester);

      await tester.tap(_key('absences-charts-toggle'));
      await tester.pump();
      expect(_key('absences-status'), findsOneWidget);
      await tester.tap(_key('absences-add-future'));
      await settleFor(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpAbsences(
          tester,
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );

        final l10n = tester.element(find.byType(AbsencesPageNew)).l10n;
        expect(
          tester.widget<Text>(_key('absences-header-title')).data,
          l10n.text('absences.title'),
        );
        expect(
            find.text(l10n.text('absences.addFutureAbsence')), findsOneWidget);
        expect(find.text(l10n.text('absences.statistics')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
