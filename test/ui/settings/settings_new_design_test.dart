import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/reminder_settings.dart';
import 'package:dr/ui/settings_page_new.dart';
import 'package:dr/ui/subject_swatch_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

const _phone = Size(412, 900);

typedef _Store = Store<AppState, AppStateBuilder, AppActions>;

AppState _state({
  String languageCode = 'de',
  String username = 'anna',
  bool assessmentReminders = false,
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = username;
      b.settingsState
        ..languageCode = languageCode
        ..assessmentRemindersEnabled = assessmentReminders
        ..subjectThemes = MapBuilder<String, SubjectTheme>({
          'Mathematik': SubjectTheme((t) => t
            ..thick = 2
            ..color = 0xFF3F51B5),
        });
    });

/// Opens the settings as the profile menu does, below the shell of the new
/// design.
Future<_Store> _pumpSettings(
  WidgetTester tester, {
  Widget page = const SettingsPageContainer(),
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
  scaffoldKey!.currentState!.selectContentWidget(page, Pages.settings);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
  return store;
}

Finder _key(String key) => find.byKey(Key(key));

/// Brings [finder] into view in the list of the settings.
Future<void> _show(WidgetTester tester, Finder finder) async {
  // In the middle, as the top of the list is below the glass header.
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await settleFor(tester);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the new design shows the glass page', (tester) async {
      await _pumpSettings(tester);

      expect(find.byType(SettingsPageNew), findsOneWidget);
      expect(_key('settings-app-header'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(RadioListTile<Object>), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.byType(GlassSegmentedControl<bool>), findsOneWidget);
    });

    testWidgets('legacy keeps its page', (tester) async {
      final store = createStore(initialState: _state());
      await pumpApp(tester, store: store, home: const SettingsPageContainer());
      await settleFor(tester);

      expect(find.byType(SettingsPageNew), findsNothing);
      expect(find.byType(SettingsSectionNew), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
      expect(find.byType(GlassSegmentedControl<bool>), findsNothing);
    });

    testWidgets('the design segments switch the design', (tester) async {
      final store = await _pumpSettings(tester);
      final switcher = _key('settings-design-switch');
      await _show(tester, switcher);
      await tester
          .tap(find.descendant(of: switcher, matching: find.text('Legacy')));
      await settleFor(tester);
      expect(store.state.settingsState.legacyDesign, isTrue);
    });
  });

  group('content', () {
    testWidgets('sections are glass cards below headings', (tester) async {
      await _pumpSettings(tester);
      final l10n = tester.element(find.byType(SettingsPageNew)).l10n;

      for (final key in [
        'settings.section.auth',
        'settings.section.appearance',
        'settings.section.dashboard',
        'settings.section.calendar',
        'tutorial.settings.title',
        'privacySettings.title',
        'reminders.settings.title',
        'export.title',
        'settings.section.advanced',
        'settings.section.credits',
      ]) {
        final heading = find.widgetWithText(
          GlassSectionHeading,
          l10n.text(key),
        );
        expect(heading, findsOneWidget, reason: key);
      }
      expect(
        find.descendant(
          of: find.byType(ReminderSettings),
          matching: find.byType(GlassCard),
        ),
        findsOneWidget,
      );
      for (final key in [
        'settings-design-tile',
        'settings-language-tile',
        'settings-subject-colors-tile',
        'settings-grades-tile',
        'settings-subject-nicks-tile',
        'settings-substitute-tile',
        'settings-favorite-subjects-tile',
        'settings-credits-tile',
        'settings-dashboard-cards-tile',
        'mensa-reminder-toggle',
        'assessment-reminder-toggle',
      ]) {
        expect(
          find.descendant(of: find.byType(GlassCard), matching: _key(key)),
          findsOneWidget,
          reason: key,
        );
      }
      expect(_key('settings-debug-button'), findsNothing);
    });

    testWidgets('the headings and the title are headings', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpSettings(tester);
      final l10n = tester.element(find.byType(SettingsPageNew)).l10n;

      expect(
        tester.getSemantics(_key('settings-header-title')),
        isSemantics(label: l10n.text('settings.title'), isHeader: true),
      );
      expect(
        tester.getSemantics(find.text(l10n.text('settings.section.auth'))),
        isSemantics(label: l10n.text('settings.section.auth'), isHeader: true),
      );
      semantics.dispose();
    });

    testWidgets('the theme segments choose the theme', (tester) async {
      final previous = themeController.themePreference;
      addTearDown(() => themeController.setThemePreference(previous));
      final store = await _pumpSettings(tester);
      final control = _key('settings-theme-switch');
      await _show(tester, control);

      await tester
          .tap(find.descendant(of: control, matching: find.text('Dunkel')));
      await settleFor(tester);
      expect(themeController.themePreference, AppThemePreference.dark);
      expect(store.state.settingsState.amoledMode, isFalse);

      await tester
          .tap(find.descendant(of: control, matching: find.text('Amoled')));
      await settleFor(tester);
      expect(store.state.settingsState.amoledMode, isTrue);

      await tester
          .tap(find.descendant(of: control, matching: find.text('System')));
      await settleFor(tester);
      expect(themeController.themePreference, AppThemePreference.system);
      expect(store.state.settingsState.amoledMode, isFalse);
    });

    testWidgets('the debug user gets a glass button', (tester) async {
      await _pumpSettings(tester, state: _state(username: 'debug'));

      final button = _key('settings-debug-button');
      expect(button, findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('a day of the assessment reminders is added in a sheet',
        (tester) async {
      final store = await _pumpSettings(
        tester,
        state: _state(assessmentReminders: true),
      );
      final add = _key('assessment-reminder-add');
      await _show(tester, add);
      await tester.tap(add);
      await settleFor(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.ancestor(
          of: _key('assessment-reminder-day-input'),
          matching: find.byType(GlassPanel),
        ),
        findsOneWidget,
      );
      await tester.enterText(_key('assessment-reminder-day-input'), '5');
      await tester.tap(_key('assessment-reminder-day-confirm'));
      await settleFor(tester);

      expect(_key('assessment-reminder-day-input'), findsNothing);
      expect(store.state.settingsState.assessmentReminderDays, contains(5));
    });
  });

  group('sub-pages', () {
    testWidgets('open in the glass frame and go back', (tester) async {
      await _pumpSettings(tester);
      final tile = _key('settings-subject-colors-tile');
      await _show(tester, tile);
      await tester.tap(tile);
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      final page = _key('settings-subject-colors-page');
      expect(page, findsOneWidget);
      expect(
        find.descendant(
          of: page,
          matching: _key('settings-detail-app-header'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppBar), findsNothing);

      // The swatches open in a glass sheet.
      await tester.tap(find.text('Mathematik'));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(
        find.ancestor(
          of: find.byType(SubjectSwatchPicker),
          matching: find.byType(GlassSheet),
        ),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(SubjectSwatchPicker))).pop();
      await settleFor(tester, duration: const Duration(milliseconds: 600));

      await tester.tap(
        find.descendant(of: page, matching: find.byType(BackButton)),
      );
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(page, findsNothing);
      expect(find.byType(SettingsPageNew), findsOneWidget);
    });

    testWidgets('a shortcut shows only its page in the frame', (tester) async {
      await _pumpSettings(
        tester,
        page: const SettingsPageContainer(shortcut: SettingsShortcut.grades),
      );

      expect(_key('settings-grades-page'), findsOneWidget);
      expect(_key('settings-detail-app-header'), findsOneWidget);
      expect(find.byType(SettingsPageNew), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('the sub-page list ends above the bar', (tester) async {
      await _pumpSettings(
        tester,
        size: const Size(360, 640),
        page: const SettingsPageContainer(shortcut: SettingsShortcut.grades),
      );

      final list = tester.widget<ListView>(_key('settings-detail-list'));
      expect(
        (list.padding! as EdgeInsets).bottom,
        greaterThanOrEqualTo(
          tester.getSize(_key('app-navigation-bar')).height,
        ),
      );
    });
  });

  group('back', () {
    testWidgets('the back button leaves the settings', (tester) async {
      await _pumpSettings(tester);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 600));
      expect(find.byType(SettingsPageNew), findsNothing);
    });
  });

  group('layouts', () {
    testWidgets('on a phone the list ends above the bar', (tester) async {
      await _pumpSettings(tester, size: const Size(360, 640));

      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      final header = tester.getRect(_key('settings-app-header'));
      expect(header.left, 0);
      expect(header.top, 0);
      expect(
        tester.getRect(find.byType(GlassSectionHeading).first).top,
        greaterThanOrEqualTo(header.bottom),
      );

      await tester.drag(_key('settings-list'), const Offset(0, -20000));
      await settleFor(tester);
      expect(
        tester.getRect(_key('settings-credits-tile')).bottom,
        lessThanOrEqualTo(tester.getRect(_key('app-navigation-bar')).top),
      );
    });

    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets(
          'at ${size.width} x ${size.height} the header floats above the list',
          (tester) async {
        await _pumpSettings(tester, size: size);

        expect(find.byType(AppNavigationRail), findsOneWidget);
        final header = tester.getRect(_key('settings-app-header'));
        final card = tester.getRect(find.byType(GlassCard).first);
        expect(header.top, DesignTokens.gutter);
        expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(card.left, header.left);
        expect(card.right, header.right);
        expect(card.top, greaterThanOrEqualTo(header.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('320 px, text at $scale, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpSettings(
            tester,
            state: _state(assessmentReminders: true),
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );

          expect(tester.takeException(), isNull);
          for (final card in find.byType(GlassCard).evaluate()) {
            expect(
              tester.getSize(find.byWidget(card.widget)).width,
              320 - 2 * DesignTokens.gutter,
            );
          }
        });
      }
    }
  });

  group('glass', () {
    testWidgets('only the header blurs, nothing in the list', (tester) async {
      await _pumpSettings(tester);

      expect(
        find.descendant(
          of: _key('settings-list'),
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
        await _pumpSettings(tester, themeMode: themeMode);

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SettingsPageNew),
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

    testWidgets('reduced motion switches at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final store = await _pumpSettings(tester);
      final switcher = _key('settings-design-switch');
      await _show(tester, switcher);
      await tester
          .tap(find.descendant(of: switcher, matching: find.text('Legacy')));
      await tester.pump();
      expect(store.state.settingsState.legacyDesign, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpSettings(
          tester,
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );

        final l10n = tester.element(find.byType(SettingsPageNew)).l10n;
        final header = tester.widget<Text>(_key('settings-header-title'));
        expect(header.data, l10n.text('settings.title'));
        expect(
            l10n.text('settings.theme.system'), isNot('settings.theme.system'));
        expect(
          find.descendant(
            of: _key('settings-theme-switch'),
            matching: find.text(l10n.text('settings.theme.system')),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
