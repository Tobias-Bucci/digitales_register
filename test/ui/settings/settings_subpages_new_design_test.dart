import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/settings_page_new.dart';
import 'package:dr/ui/settings_page_widget.dart';
import 'package:dr/ui/subject_swatch_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

const _phone = Size(412, 900);

typedef _Store = Store<AppState, AppStateBuilder, AppActions>;

AppState _state({String languageCode = 'de', bool empty = false}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.gradesState.subjects.replace([
        for (final subject in ['Mathematik', 'Deutsch', 'Physik'])
          buildSubject(name: subject),
      ]);
      b.settingsState
        ..languageCode = languageCode
        ..calendarSyncEnabled = true
        ..calendarSyncCalendarId = 12
        ..subjectThemes = MapBuilder<String, SubjectTheme>({
          'Mathematik': SubjectTheme((t) => t
            ..thick = 2
            ..color = 0xFF3F51B5),
        });
      if (empty) {
        b.settingsState
          ..subjectNicks = MapBuilder<String, String>()
          ..favoriteSubjects = ListBuilder<String>()
          ..ignoreForGradesAverage = ListBuilder<String>();
      } else {
        b.settingsState
          ..subjectNicks = MapBuilder<String, String>({'Mathematik': 'Mat'})
          ..favoriteSubjects = ListBuilder<String>(['Mathematik'])
          ..ignoreForGradesAverage = ListBuilder<String>(['Deutsch'])
          ..substitutePrimaryTeachers = MapBuilder<String, BuiltList<String>>({
            'Mathematik': BuiltList<String>(['Huber Maria']),
          });
      }
    });

/// The tile on the main page that opens each sub-page, and the key of the
/// sub-page.
const _pages = {
  'subject colours': (
    'settings-subject-colors-tile',
    'settings-subject-colors-page'
  ),
  'grades': ('settings-grades-tile', 'settings-grades-page'),
  'nicknames': ('settings-subject-nicks-tile', 'settings-subject-nicks-page'),
  'substitute teachers': (
    'settings-substitute-tile',
    'settings-substitute-page'
  ),
  'favourite subjects': (
    'settings-favorite-subjects-tile',
    'settings-favorite-subjects-page'
  ),
  'calendar sync': (
    'settings-calendar-sync-details-tile',
    'settings-calendar-sync-page'
  ),
};

Finder _key(String key) => find.byKey(Key(key));

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 600));

/// Opens the settings below the shell and then the sub-page behind [tile].
Future<_Store> _pumpSubPage(
  WidgetTester tester,
  String tile, {
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
      .selectContentWidget(const SettingsPageContainer(), Pages.settings);
  await _settle(tester);
  await Scrollable.ensureVisible(tester.element(_key(tile)), alignment: 0.5);
  await settleFor(tester);
  await tester.tap(_key(tile));
  await _settle(tester);
  return store;
}

/// Picks [suggestion] in the add sheet that is open and confirms it.
Future<void> _pickInSheet(WidgetTester tester, String suggestion) async {
  await tester.enterText(_key('add-subject-field'), suggestion.substring(0, 2));
  await settleFor(tester);
  await tester.tap(find.byKey(ValueKey('suggestion-$suggestion')));
  await settleFor(tester);
  await tester.tap(_key('add-subject-done'));
  await _settle(tester);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    isAndroidOverride = () => true;
    CalendarSyncService.requestPermissionOverride = () async => true;
    CalendarSyncService.getWritableCalendarsOverride =
        () async => const <CalendarSyncCalendar>[
              CalendarSyncCalendar(
                id: 12,
                displayName: 'School',
                accountName: 'school@example.com',
                ownerAccount: 'school@example.com',
                isPrimary: true,
              ),
            ];
  });

  tearDown(() async {
    CalendarSyncService.missingEventCount.value = 0;
    await resetTestState();
  });

  group('design switch', () {
    for (final MapEntry(key: name, value: (tile, page)) in _pages.entries) {
      testWidgets('$name shows glass sections, no Material cards',
          (tester) async {
        await _pumpSubPage(tester, tile);

        expect(_key(page), findsOneWidget);
        expect(
          find.descendant(
            of: _key(page),
            matching: _key('settings-detail-app-header'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _key(page), matching: find.byType(Card)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: _key(page),
            matching: find.byType(SettingsSectionNew),
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.descendant(of: _key(page), matching: find.byType(BackButton)),
        );
        await _settle(tester);
        expect(_key(page), findsNothing);
        expect(find.byType(SettingsPageNew), findsOneWidget);
      });
    }

    testWidgets('legacy keeps its cards and its dialog', (tester) async {
      final store = createStore(initialState: _state());
      await pumpApp(
        tester,
        store: store,
        home: const SettingsPageContainer(shortcut: SettingsShortcut.grades),
      );
      await settleFor(tester);

      expect(find.byType(Card), findsWidgets);
      expect(find.byType(SettingsSectionNew), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await settleFor(tester);
      expect(find.byType(AddSubject), findsOneWidget);
      expect(find.byType(GlassPanel), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('content', () {
    testWidgets('subject colours list the subjects with their colour',
        (tester) async {
      await _pumpSubPage(tester, 'settings-subject-colors-tile');

      expect(
        find.descendant(
          of: _key('settings-subject-colors-list'),
          matching: find.byType(SettingsColorDisc),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Mathematik'));
      await _settle(tester);
      expect(
        find.ancestor(
          of: find.byType(SubjectSwatchPicker),
          matching: find.byType(GlassSheet),
        ),
        findsOneWidget,
      );
    });

    testWidgets('grades: a subject is excluded in a sheet and removed again',
        (tester) async {
      final store = await _pumpSubPage(tester, 'settings-grades-tile');

      await tester.tap(_key('settings-grades-exclude-add'));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.ancestor(
          of: _key('add-subject-field'),
          matching: find.byType(GlassPanel),
        ),
        findsOneWidget,
      );
      await _pickInSheet(tester, 'Physik');
      expect(
        store.state.settingsState.ignoreForGradesAverage,
        containsAll(['Deutsch', 'Physik']),
      );

      final remove = find.descendant(
        of: find.ancestor(
          of: find.text('Deutsch'),
          matching: find.byType(ListTile),
        ),
        matching: find.byTooltip('Löschen'),
      );
      await tester.tap(remove);
      await _settle(tester);
      expect(store.state.settingsState.ignoreForGradesAverage, ['Physik']);
    });

    testWidgets('grades: the empty list says so', (tester) async {
      await _pumpSubPage(
        tester,
        'settings-grades-tile',
        state: _state(empty: true),
      );
      final l10n = tester.element(_key('settings-grades-page')).l10n;
      expect(
        find.widgetWithText(
          SettingsEmptyRow,
          l10n.text('settings.grades.noExcludedSubject'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('nicknames: edited in a sheet with labelled fields',
        (tester) async {
      final store = await _pumpSubPage(tester, 'settings-subject-nicks-tile');

      await tester.tap(_key('settings-subject-nicks-add'));
      await _settle(tester);
      expect(
        find.ancestor(
          of: _key('subject-nick-subject-field'),
          matching: find.byType(GlassPanel),
        ),
        findsOneWidget,
      );
      await tester.enterText(_key('subject-nick-subject-field'), 'Phy');
      await settleFor(tester);
      await tester.tap(find.byKey(const ValueKey('suggestion-Physik')));
      await settleFor(tester);
      await tester.enterText(_key('subject-nick-nick-field'), 'Phy');
      await settleFor(tester);
      await tester.tap(_key('subject-nick-done'));
      await _settle(tester);
      expect(store.state.settingsState.subjectNicks['Physik'], 'Phy');

      await tester.tap(_key('settings-subject-nicks-reset'));
      await _settle(tester);
      expect(
        store.state.settingsState.subjectNicks.toMap(),
        defaultSubjectNicks,
      );
    });

    testWidgets('nicknames: the shortcut asks in a sheet at once',
        (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = createStore(initialState: _state(), newDesign: true);
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      scaffoldKey!.currentState!.selectContentWidget(
        const SettingsPageContainer(shortcut: SettingsShortcut.subjectNicks),
        Pages.settings,
      );
      await _settle(tester);

      expect(_key('settings-subject-nicks-page'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(EditSubjectsNicks),
          matching: find.byType(GlassSheet),
        ),
        findsOneWidget,
      );
    });

    testWidgets('substitute teachers: a subject opens and adds a teacher',
        (tester) async {
      final store = await _pumpSubPage(tester, 'settings-substitute-tile');

      expect(
        find.descendant(
          of: _key('settings-substitute-subjects'),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('Mathematik'));
      await _settle(tester);
      expect(find.text('Huber Maria'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('substitute-add-teacher-Mathematik')),
      );
      await _settle(tester);
      expect(
        find.ancestor(
          of: _key('add-subject-field'),
          matching: find.byType(GlassPanel),
        ),
        findsOneWidget,
      );
      await tester.enterText(_key('add-subject-field'), 'Rossi Paolo');
      await settleFor(tester);
      await tester.tap(_key('add-subject-done'));
      await _settle(tester);
      expect(
        store.state.settingsState.substitutePrimaryTeachers['Mathematik'],
        containsAll(['Huber Maria', 'Rossi Paolo']),
      );
    });

    testWidgets('favourite subjects: added from the subjects only',
        (tester) async {
      final store =
          await _pumpSubPage(tester, 'settings-favorite-subjects-tile');

      await tester.tap(_key('settings-favorite-subjects-add'));
      await _settle(tester);
      await _pickInSheet(tester, 'Deutsch');
      expect(
        store.state.settingsState.favoriteSubjects,
        containsAll(['Mathematik', 'Deutsch']),
      );
    });

    testWidgets('favourite subjects: nothing left to add disables the button',
        (tester) async {
      await _pumpSubPage(
        tester,
        'settings-favorite-subjects-tile',
        state: _state().rebuild(
          (b) => b.settingsState.favoriteSubjects =
              ListBuilder<String>(['Mathematik', 'Deutsch', 'Physik']),
        ),
      );
      final button = tester.widget<IconButton>(
        find.descendant(
          of: _key('settings-favorite-subjects-add'),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('calendar sync: target, missing events and removal',
        (tester) async {
      CalendarSyncService.missingEventCount.value = 2;
      await _pumpSubPage(tester, 'settings-calendar-sync-details-tile');

      expect(_key('calendar-sync-calendar-picker'), findsOneWidget);
      expect(_key('calendar-sync-missing-events'), findsOneWidget);
      expect(_key('calendar-sync-recreate-missing-events'), findsOneWidget);
      expect(_key('calendar-sync-remove-events-tile'), findsOneWidget);
      expect(find.textContaining('School'), findsWidgets);

      await tester.tap(_key('calendar-sync-calendar-picker'));
      await _settle(tester);
      expect(find.byType(GlassPanel), findsOneWidget);
    });
  });

  group('layouts', () {
    testWidgets('at 1280 x 800 the header floats above the cards',
        (tester) async {
      await _pumpSubPage(
        tester,
        'settings-grades-tile',
        size: const Size(1280, 800),
      );
      final header = tester.getRect(_key('settings-detail-app-header'));
      final card = tester.getRect(find.byType(GlassCard).first);
      expect(header.top, DesignTokens.gutter);
      expect(card.left, header.left);
      expect(card.right, header.right);
      expect(card.top, greaterThanOrEqualTo(header.bottom));
    });

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final MapEntry(key: page, value: (tile, _)) in _pages.entries) {
        testWidgets('$page at 320 px, text at 2.0, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpSubPage(
            tester,
            tile,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('glass', () {
    testWidgets('only the header blurs', (tester) async {
      await _pumpSubPage(tester, 'settings-substitute-tile');
      expect(
        find.descendant(
          of: _key('settings-detail-list'),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    });

    testWidgets('high contrast has no blur and no light', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpSubPage(tester, 'settings-grades-tile');

      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: _key('settings-grades-page'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is GlassSheenPainter,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('reduced motion removes an entry at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final store = await _pumpSubPage(
        tester,
        'settings-favorite-subjects-tile',
        state: _state().rebuild(
          (b) => b.settingsState.favoriteSubjects =
              ListBuilder<String>(['Mathematik', 'Deutsch']),
        ),
      );
      await tester.tap(find.byTooltip('Löschen').first);
      await tester.pump();
      await tester.pump();
      expect(store.state.settingsState.favoriteSubjects, ['Deutsch']);
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpSubPage(
          tester,
          'settings-favorite-subjects-tile',
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );
        final l10n =
            tester.element(_key('settings-favorite-subjects-page')).l10n;
        expect(l10n.text('grades.subjects'), isNot('grades.subjects'));
        expect(
          find.descendant(
            of: find.byType(GlassSectionHeading),
            matching: find.textContaining(l10n.text('grades.subjects')),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
