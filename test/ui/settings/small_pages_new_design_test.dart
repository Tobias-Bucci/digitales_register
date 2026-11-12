import 'dart:async';

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
import 'package:dr/ui/about_app_dialog.dart';
import 'package:dr/ui/credits_page.dart';
import 'package:dr/ui/debug_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/network_protocol_page.dart';
import 'package:dr/ui/privacy_data_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

const _phone = Size(412, 900);

typedef _Store = Store<AppState, AppStateBuilder, AppActions>;

AppState _state({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

Finder _key(String key) => find.byKey(Key(key));

Future<void> _settle(WidgetTester tester) =>
    settleFor(tester, duration: const Duration(milliseconds: 600));

/// Opens the settings below the shell, then [page] above them, as the
/// settings do.
Future<_Store> _pumpPage(
  WidgetTester tester,
  Widget? page, {
  AppState? state,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  int protocolItems = 3,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(initialState: state ?? _state(), newDesign: true);
  for (var i = 0; i < protocolItems; i++) {
    await store.actions.addNetworkProtocolItem(NetworkProtocolItem((b) => b
      ..address = 'https://school.example/v2/api/student/dashboard/dashboard'
      ..parameters = '{"viewFuture":true}'
      ..response = i.isEven ? 'completed' : 'failed'));
  }
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
  if (page != null) {
    unawaited(
      Navigator.of(tester.element(find.byType(SettingsPageContainer)))
          .push(MaterialPageRoute<void>(builder: (_) => page)),
    );
    await _settle(tester);
  }
  return store;
}

/// The pages and the key of their glass header.
final _pages = <String, (Widget, String)>{
  'network protocol': (
    const NetworkProtocolPage(),
    'network-protocol-app-header'
  ),
  'privacy details': (
    const PrivacyDataDetailsPage(),
    'privacy-details-app-header'
  ),
  'credits': (const CreditsPage(), 'credits-app-header'),
};

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    for (final MapEntry(key: name, value: (page, header)) in _pages.entries) {
      testWidgets('$name has the glass header and goes back', (tester) async {
        await _pumpPage(tester, page);

        expect(_key(header), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(Card), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.descendant(of: _key(header), matching: find.byType(BackButton)),
        );
        await _settle(tester);
        expect(_key(header), findsNothing);
      });

      testWidgets('$name keeps its legacy look', (tester) async {
        await pumpApp(
          tester,
          store: createStore(initialState: _state()),
          home: page,
        );
        await settleFor(tester);
        expect(find.byType(AppBar), findsOneWidget);
        expect(_key(header), findsNothing);
        expect(find.byType(GlassPage), findsNothing);
      });
    }

    testWidgets('privacy details from the root navigator stay legacy',
        (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = createStore(initialState: _state(), newDesign: true);
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      // As the consent dialog opens it, above the shell.
      Navigator.of(tester.element(find.byType(DaysContainer)),
              rootNavigator: true)
          .push(MaterialPageRoute<void>(
        builder: (_) => const PrivacyDataDetailsPage(),
      ));
      await _settle(tester);
      expect(find.byType(PrivacyDataDetailsPage), findsOneWidget);
      expect(_key('privacy-details-app-header'), findsNothing);
      expect(find.byType(Card), findsWidgets);
    });
  });

  group('network protocol', () {
    testWidgets('entries are glass cards with glass chips', (tester) async {
      await _pumpPage(tester, const NetworkProtocolPage());

      final list = _key('network-protocol-list');
      expect(
        find.descendant(of: list, matching: find.byType(GlassCard)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(of: list, matching: find.byType(GlassChip)),
        findsNWidgets(9),
      );
    });

    testWidgets('the details open in a glass sheet, without payloads',
        (tester) async {
      await _pumpPage(tester, const NetworkProtocolPage());

      await tester.tap(
        find
            .descendant(
              of: _key('network-protocol-list'),
              matching: find.byType(GlassCard),
            )
            .first,
      );
      await _settle(tester);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(
        find.ancestor(
          of: _key('network-protocol-details'),
          matching: find.byType(GlassSheet),
        ),
        findsOneWidget,
      );
      // The protocol shows labels, never what was sent or received.
      expect(find.textContaining('viewFuture'), findsNothing);
      expect(find.textContaining('school.example/v2'), findsNothing);
    });

    testWidgets('an empty protocol is a state card', (tester) async {
      await _pumpPage(tester, const NetworkProtocolPage(), protocolItems: 0);
      final l10n = tester.element(find.byType(NetworkProtocolPage)).l10n;
      expect(
        find.widgetWithText(GlassStateCard, l10n.text('network.empty')),
        findsOneWidget,
      );
    });
  });

  group('bottom gap', () {
    for (final (name, page, list) in [
      (
        'privacy details',
        const PrivacyDataDetailsPage(),
        'privacy-details-list'
      ),
      ('credits', const CreditsPage(), 'credits-list'),
    ]) {
      testWidgets('$name ends above the bar', (tester) async {
        await _pumpPage(tester, page, size: const Size(360, 640));
        final bar = tester.getRect(_key('app-navigation-bar'));
        final listView = tester.widget<ListView>(_key(list));
        expect(
          (listView.padding! as EdgeInsets).bottom,
          greaterThanOrEqualTo(bar.height),
        );
      });
    }

    testWidgets('the debug page ends above the bar', (tester) async {
      await _pumpPage(
        tester,
        const DebugPageWidget(),
        size: const Size(360, 640),
      );
      final bar = tester.getRect(_key('app-navigation-bar'));
      final listView = tester.widget<ListView>(
        find.descendant(
          of: find.byType(DebugPageWidget),
          matching: find.byType(ListView),
        ),
      );
      expect(
        (listView.padding! as EdgeInsets).bottom,
        greaterThanOrEqualTo(bar.height),
      );
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('about dialog', () {
    testWidgets('gets the rim of the glass panels in the new design',
        (tester) async {
      await _pumpPage(tester, null);
      unawaited(showDialog<void>(
        context: tester.element(find.byType(SettingsPageContainer)),
        builder: (_) => const AboutAppDialog(version: '1.17.1'),
      ));
      await _settle(tester);
      final dialog = tester.widget<Dialog>(
        find.descendant(
          of: find.byType(AboutAppDialog),
          matching: find.byType(Dialog),
        ),
      );
      expect(dialog.shape, isA<GlassRimBorder>());
    });

    testWidgets('keeps its corners in legacy', (tester) async {
      await pumpApp(
        tester,
        store: createStore(initialState: _state()),
        home: const AboutAppDialog(version: '1.17.1'),
      );
      await settleFor(tester);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.shape, isA<RoundedRectangleBorder>());
    });
  });

  group('layouts', () {
    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final MapEntry(key: page, value: (widget, _)) in _pages.entries) {
        testWidgets('$page at 320 px, text at 2.0, $name', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpPage(
            tester,
            widget,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final MapEntry(key: page, value: (widget, header)) in _pages.entries) {
      testWidgets('$page at 1280 x 800 floats its header', (tester) async {
        await _pumpPage(tester, widget, size: const Size(1280, 800));
        final rect = tester.getRect(_key(header));
        expect(rect.top, DesignTokens.gutter);
        expect(rect.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('glass', () {
    for (final MapEntry(key: page, value: (widget, header)) in _pages.entries) {
      testWidgets('$page: high contrast has no blur, $header', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await _pumpPage(tester, widget);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$page: only the header blurs', (tester) async {
        await _pumpPage(tester, widget);
        expect(
          find.descendant(
            of: find.byType(GlassPageHeader).last,
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ListView).last,
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
      });
    }
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpPage(
          tester,
          const CreditsPage(),
          state: _state(languageCode: code),
          size: const Size(320, 640),
        );
        final l10n = tester.element(find.byType(CreditsPage)).l10n;
        expect(find.text(l10n.text('credits.title')), findsOneWidget);
        expect(find.textContaining('credits.'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
