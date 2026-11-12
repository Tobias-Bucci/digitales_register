import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/extras_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/extras_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/homework_summary_page.dart';
import 'package:dr/ui/homework_summary_page_new.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);

const _html = '''
<div id="classSummary"><div class="summary">
<h1>Hausaufgaben Übersicht - 5AT</h1>
<h3>Woche vom 18/5/2026</h3>
<table><thead><tr><th>Datum</th><th>Fach</th><th>Art</th><th>Name</th><th>Online Abgabe</th></tr></thead>
<tr><td>Mo, 18/05</td><td>Italienisch</td><td>Prüfung</td><td>Interrogazioni Cap.3</td><td>Nein</td></tr>
<tr><td>Mi, 20/05</td><td>Mathematik</td><td>Hausaufgabe</td><td>Buch S. 88</td><td>Ja</td></tr>
</table>
<h3>Woche vom 1/6/2026</h3>
<table><thead><tr><th>Datum</th><th>Fach</th><th>Art</th><th>Name</th><th>Online Abgabe</th></tr></thead></table>
</div></div>
''';

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

/// Opens the homework summary as Extras does, below the shell. [page]
/// replaces the page, to give it other loaders.
Future<Store<AppState, AppStateBuilder, AppActions>> _pump(
  WidgetTester tester, {
  Widget? page,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  bool newDesign = true,
  String languageCode = 'de',
  bool fromExtras = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _state(languageCode: languageCode),
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
  if (fromExtras) {
    scaffoldKey!.currentState!
        .selectContentWidget(const ExtrasPageContainer(), Pages.extras);
    await settleFor(tester, duration: const Duration(milliseconds: 500));
  }
  scaffoldKey!.currentState!.selectContentWidget(
    page ?? HomeworkSummaryPage(key: UniqueKey(), loader: () async => _html),
    Pages.homeworkSummary,
  );
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _key(String key) => find.byKey(Key(key));

Finder _heading(String text) => find.textContaining(text, findRichText: true);

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the new design shows the new page', (tester) async {
      await _pump(tester);

      expect(find.byType(HomeworkSummaryPageNew), findsOneWidget);
      expect(_key('homework-summary-app-header'), findsOneWidget);
      expect(find.byType(ResponsiveAppBar), findsNothing);
      expect(find.byType(NewDesignReadable), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GlassPageHeader),
          matching: find.byIcon(Icons.assignment_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('Legacy shows the old page with its cards', (tester) async {
      // Wide: on a phone the empty week of the old view overflows with the
      // test font, which is a bug of the old view, kept as it is.
      await _pump(tester, newDesign: false, size: const Size(1280, 800));

      expect(find.byType(HomeworkSummaryPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('Hausaufgaben Übersicht - 5AT'), findsOneWidget);
      expect(find.text('Woche vom 18/5/2026'), findsOneWidget);
      expect(find.text('Interrogazioni Cap.3'), findsOneWidget);
      expect(find.text('Online Abgabe: Nein'), findsOneWidget);
      expect(find.text('Keine Einträge in dieser Woche'), findsOneWidget);
      expect(find.text('3 Einträge'), findsNothing);
      expect(find.text('2 Einträge'), findsNWidgets(2));
    });

    testWidgets('switching applies at once', (tester) async {
      final store = await _pump(tester, size: const Size(1280, 800));

      await store.actions.settingsActions.legacyDesign(true);
      await settleFor(tester);
      expect(find.byType(HomeworkSummaryPageNew), findsNothing);
      expect(find.byType(ResponsiveAppBar), findsOneWidget);

      await store.actions.settingsActions.legacyDesign(false);
      await settleFor(tester);
      expect(find.byType(HomeworkSummaryPageNew), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('content', () {
    testWidgets('weeks as headings, entries as rows in cards', (tester) async {
      await _pump(tester);

      expect(find.byType(GlassSectionHeading), findsNWidgets(2));
      expect(_heading('Woche vom 18/5/2026'), findsOneWidget);
      expect(_heading('Woche vom 1/6/2026'), findsOneWidget);
      expect(find.byType(GlassCard), findsNWidgets(2));
      expect(_key('homework-summary-entry'), findsNWidgets(2));
      expect(find.text('Italienisch'), findsOneWidget);
      expect(find.text('Mo, 18/05'), findsOneWidget);
      expect(find.text('Prüfung'), findsOneWidget);
      expect(find.text('Interrogazioni Cap.3'), findsOneWidget);
      expect(find.text('Online Abgabe: Nein'), findsOneWidget);
      expect(find.text('Keine Einträge in dieser Woche'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('homework-summary-summary')).data,
        startsWith('Hausaufgaben Übersicht - 5AT · 2 Einträge'),
      );
    });

    testWidgets('an entry shows everything Legacy shows', (tester) async {
      const html = '''
<div class="summary"><h3>Woche vom 18/5/2026</h3>
<table><thead><tr><th>Datum</th><th>Fach</th><th>Art</th><th>Name</th><th>Online Abgabe</th><th>Lehrperson</th></tr></thead>
<tr><td>Mo, 18/05</td><td>Italienisch</td><td>Prüfung</td><td>Interrogazioni</td><td>Nein</td><td>Rossi</td></tr>
</table></div>''';
      for (final newDesign in [false, true]) {
        await _pump(
          tester,
          newDesign: newDesign,
          size: const Size(1280, 800),
          page: HomeworkSummaryPage(key: UniqueKey(), loader: () async => html),
        );
        for (final text in [
          // Due date, subject, type, the task and the further columns.
          'Mo, 18/05',
          'Italienisch',
          'Prüfung',
          'Interrogazioni',
          'Online Abgabe: Nein',
          'Lehrperson: Rossi',
        ]) {
          expect(find.text(text), findsOneWidget,
              reason: '$text, newDesign: $newDesign');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      }
    });

    testWidgets('the refresh disc loads again', (tester) async {
      var loads = 0;
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          loader: () async {
            loads++;
            return _html;
          },
        ),
      );
      await tester.tap(_key('homework-summary-refresh'));
      await settleFor(tester);
      expect(loads, 2);
    });

    testWidgets('a saved summary is shown, then refreshed', (tester) async {
      final refresh = Completer<PagePayloadSnapshot<String>?>();
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          cachedLoader: () async =>
              PagePayloadSnapshot<String>.fromPayload(_html),
          refreshLoader: () => refresh.future,
        ),
      );
      expect(find.text('Interrogazioni Cap.3'), findsOneWidget);

      refresh.complete(PagePayloadSnapshot<String>.fromPayload(
        _html.replaceAll('Interrogazioni Cap.3', 'Neu'),
      ));
      await settleFor(tester);
      expect(find.text('Neu'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('loading shows the bar below the header', (tester) async {
      final completer = Completer<String?>();
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          loader: () => completer.future,
        ),
      );

      expect(_key('homework-summary-loading'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedLinearProgressIndicator>(
              find.byType(AnimatedLinearProgressIndicator),
            )
            .show,
        isTrue,
      );
      completer.complete(_html);
      await settleFor(tester);
      expect(find.text('Italienisch'), findsOneWidget);
    });

    testWidgets('an error offers to try again', (tester) async {
      String? response;
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          loader: () async => response,
        ),
      );

      expect(_key('homework-summary-error'), findsOneWidget);
      expect(find.text('Hausaufgaben konnten nicht geladen werden.'),
          findsOneWidget);
      response = _html;
      await tester.tap(find.text('Erneut versuchen'));
      await settleFor(tester);
      expect(find.text('Italienisch'), findsOneWidget);
    });

    testWidgets('no homework', (tester) async {
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          loader: () async => '<div class="summary"></div>',
        ),
      );

      expect(_key('homework-summary-empty'), findsOneWidget);
      expect(find.text('Keine Hausaufgaben vorhanden'), findsOneWidget);
    });

    testWidgets('offline without a summary', (tester) async {
      wrapper.noInternet = true;
      await _pump(
        tester,
        page: HomeworkSummaryPage(
          key: UniqueKey(),
          loader: () async => null,
        ),
      );

      expect(_key('homework-summary-offline'), findsOneWidget);
    });

    testWidgets('offline with a saved summary shows a hint', (tester) async {
      wrapper.noInternet = true;
      await _pump(tester);

      expect(_key('homework-summary-last-fetched'), findsOneWidget);
      expect(find.text('Italienisch'), findsOneWidget);
    });
  });

  group('layouts', () {
    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('at ${size.width} x ${size.height} the header floats',
          (tester) async {
        await _pump(tester, size: size);

        final header = tester.getRect(_key('homework-summary-app-header'));
        final card = tester.getRect(find.byType(GlassCard).first);
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(card.left, header.left);
        expect(card.right, header.right);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px, text at 2.0, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
        );

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(GlassCard).first).width,
          320 - 2 * DesignTokens.gutter,
        );
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pump(tester);

      expect(
        find.descendant(
          of: _key('homework-summary-list'),
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

    testWidgets('high contrast has no blur and no light', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, themeMode: ThemeMode.dark);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HomeworkSummaryPageNew),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is GlassSheenPainter,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester);

      expect(find.text('Italienisch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('navigation', () {
    testWidgets('back returns to Extras', (tester) async {
      await _pump(tester, fromExtras: true);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(HomeworkSummaryPageNew), findsNothing);
      expect(find.byType(ExtrasPage), findsOneWidget);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pump(tester, languageCode: code, size: const Size(320, 640));

        final l10n = tester.element(find.byType(HomeworkSummaryPageNew)).l10n;
        expect(
          tester.widget<Text>(_key('homework-summary-header-title')).data,
          l10n.text('homeworkSummary.title'),
        );
        expect(
            find.text(l10n.text('homeworkSummary.emptyWeek')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
