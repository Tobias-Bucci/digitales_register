import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);

AppState _state() => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
    });

/// A page of the new design built only from the shared parts.
class _TestPage extends StatelessWidget {
  const _TestPage({
    required this.body,
    this.bottom,
    this.scrolls = true,
    this.twoColumns = false,
  });

  final Widget body;
  final PreferredSizeWidget? bottom;
  final bool scrolls, twoColumns;

  @override
  Widget build(BuildContext context) => GlassPage(
        scrolls: scrolls,
        header: GlassPageHeader(
          surfaceKey: const Key('test-header'),
          titleKey: const Key('test-title'),
          title: 'Testseite',
          floatingMaxWidth: glassHeaderFloatingWidth(
            MediaQuery.sizeOf(context).width,
            twoColumns: twoColumns,
          ),
          actions: [
            HeaderDiscButton(
              key: const Key('test-action'),
              tooltip: 'Aktion',
              icon: Icons.history_rounded,
              onPressed: () {},
            ),
          ],
          bottom: bottom,
        ),
        body: body,
      );
}

List<Widget> _tiles(int count, {VoidCallback? onTap}) => [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        GlassTile(
          key: ValueKey('tile-$i'),
          icon: Icons.description_outlined,
          title: 'Eintrag $i',
          subtitle: 'Beschreibung $i',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap ?? () {},
        ),
      ],
    ];

/// Shows [page] in the shell of the new design, as the page [as].
Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  Pages as = Pages.extras,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(initialState: _state(), newDesign: true);
  await pumpApp(
    tester,
    store: store,
    home: DaysContainer(),
    themeMode: themeMode,
  );
  await settleFor(tester);
  scaffoldKey!.currentState!.selectContentWidget(page, as);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('header', () {
    testWidgets('a destination of the navigation has no back button',
        (tester) async {
      await _pumpPage(
          tester, _TestPage(body: GlassListBody(children: _tiles(2))));

      expect(find.byKey(const Key('test-header')), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byKey(const Key('test-action')), findsOneWidget);
    });

    testWidgets('any other page has one, and it goes back', (tester) async {
      await _pumpPage(
        tester,
        _TestPage(body: GlassListBody(children: _tiles(2))),
        as: Pages.classRegister,
      );

      expect(find.byType(BackButton), findsOneWidget);
      final button = tester.getSize(
        find.descendant(
          of: find.byType(BackButton),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 500));
      expect(find.byType(_TestPage), findsNothing);
    });

    testWidgets('a page that nothing lies below has no back button',
        (tester) async {
      final store = createStore(initialState: _state(), newDesign: true);
      await pumpApp(
        tester,
        store: store,
        home: _TestPage(body: GlassListBody(children: _tiles(1))),
      );

      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('the title is a heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPage(
          tester, _TestPage(body: GlassListBody(children: _tiles(1))));

      expect(
        tester.getSemantics(find.byKey(const Key('test-title'))),
        isSemantics(label: 'Testseite', isHeader: true),
      );
      semantics.dispose();
    });

    test('floats from 720 px and lines up with the body', () {
      expect(glassHeaderFloatingWidth(719), isNull);
      expect(glassHeaderFloatingWidth(720), DesignTokens.contentMaxWidth);
      expect(glassHeaderFloatingWidth(1920), DesignTokens.contentMaxWidth);
      expect(glassHeaderFloatingWidth(719, twoColumns: true), isNull);
      expect(
        glassHeaderFloatingWidth(1000, twoColumns: true),
        DesignTokens.contentMaxWidth,
      );
      expect(
        glassHeaderFloatingWidth(1280, twoColumns: true),
        DashboardColumns.maxWidth,
      );
    });

    for (final (width, floating) in const [(719.0, false), (720.0, true)]) {
      testWidgets(
          'at $width px the header ${floating ? 'floats' : 'is a band'}',
          (tester) async {
        await _pumpPage(
          tester,
          _TestPage(body: GlassListBody(children: _tiles(1))),
          size: Size(width, 800),
        );

        final header = tester.getRect(find.byKey(const Key('test-header')));
        if (floating) {
          expect(header.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
          expect(header.top, DesignTokens.gutter);
        } else {
          expect(header.left, 0);
          expect(header.top, 0);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a second row adds its height', (tester) async {
      const row = PreferredSize(
        preferredSize: Size.fromHeight(48),
        child: SizedBox.expand(key: Key('test-bottom')),
      );
      const plain = GlassPageHeader(title: 'A', floatingMaxWidth: null);
      const withRow =
          GlassPageHeader(title: 'A', floatingMaxWidth: null, bottom: row);
      const floating = GlassPageHeader(
        title: 'A',
        floatingMaxWidth: 840,
        bottom: row,
      );
      expect(plain.preferredSize.height, GlassPageHeader.height);
      expect(withRow.preferredSize.height, GlassPageHeader.height + 48);
      expect(
        floating.preferredSize.height,
        GlassPageHeader.height + DesignTokens.gutter + 48,
      );

      await _pumpPage(
        tester,
        _TestPage(bottom: row, body: GlassListBody(children: _tiles(1))),
      );
      final bottom = tester.getRect(find.byKey(const Key('test-bottom')));
      expect(bottom.height, 48);
      expect(bottom.top, GlassPageHeader.height);
      // The list starts below both rows.
      expect(
        tester.getRect(find.byKey(const ValueKey('tile-0'))).top,
        greaterThanOrEqualTo(bottom.bottom),
      );
    });
  });

  group('bodies', () {
    testWidgets('a list starts below the header and ends above the bar',
        (tester) async {
      await _pumpPage(
        tester,
        _TestPage(
          body: GlassListBody(
            listKey: const Key('test-list'),
            children: _tiles(20),
          ),
        ),
        size: const Size(412, 600),
      );

      expect(
        tester.getRect(find.byKey(const ValueKey('tile-0'))).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('test-header'))).bottom,
        ),
      );
      await tester.drag(
        find.byKey(const Key('test-list')),
        const Offset(0, -4000),
      );
      await settleFor(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('tile-19'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });

    testWidgets('a lazy list ends above the bar as well', (tester) async {
      await _pumpPage(
        tester,
        _TestPage(
          body: GlassListBody.builder(
            listKey: const Key('test-list'),
            itemCount: 30,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(height: 40, key: ValueKey('row-$index')),
            ),
          ),
        ),
        size: const Size(412, 600),
      );

      await tester.drag(
        find.byKey(const Key('test-list')),
        const Offset(0, -4000),
      );
      await settleFor(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('row-29'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });

    testWidgets('a list keeps the readable width', (tester) async {
      await _pumpPage(
        tester,
        _TestPage(body: GlassListBody(children: _tiles(1))),
        size: const Size(1920, 1080),
      );

      final tile = tester.getRect(find.byKey(const ValueKey('tile-0')));
      final header = tester.getRect(find.byKey(const Key('test-header')));
      expect(tile.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
      expect(tile.left, header.left);
      expect(tile.right, header.right);
    });

    testWidgets('two columns from 1080 px, one below', (tester) async {
      Widget page() => _TestPage(
            twoColumns: true,
            body: GlassColumnsBody(
              listKey: const Key('test-list'),
              side: const SizedBox(height: 100, key: Key('test-side')),
              main: Column(children: _tiles(3)),
            ),
          );
      await _pumpPage(tester, page(), size: const Size(1280, 800));

      final sideColumn = find.byKey(const Key('dashboard-side-column'));
      expect(sideColumn, findsOneWidget);
      expect(
        find.descendant(
            of: sideColumn, matching: find.byKey(const Key('test-side'))),
        findsOneWidget,
      );
      // The columns line up with the floating header.
      final header = tester.getRect(find.byKey(const Key('test-header')));
      expect(
          tester.getRect(find.byKey(const Key('test-side'))).left, header.left);
      expect(
        tester.getRect(find.byKey(const ValueKey('tile-0'))).right,
        header.right,
      );
    });

    testWidgets('below 1080 px the side comes first', (tester) async {
      await _pumpPage(
        tester,
        _TestPage(
          twoColumns: true,
          body: GlassColumnsBody(
            side: const SizedBox(height: 100, key: Key('test-side')),
            main: Column(children: _tiles(1)),
          ),
        ),
      );

      expect(find.byKey(const Key('dashboard-side-column')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('tile-0'))).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('test-side'))).bottom,
        ),
      );
    });

    testWidgets('a body that does not scroll stays between header and bar',
        (tester) async {
      await _pumpPage(
        tester,
        const _TestPage(
          scrolls: false,
          body: SizedBox.expand(key: Key('test-fixed')),
        ),
      );

      final body = tester.getRect(find.byKey(const Key('test-fixed')));
      expect(
        body.top,
        tester.getRect(find.byKey(const Key('test-header'))).bottom,
      );
      expect(
        body.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('app-navigation-bar'))).top,
        ),
      );
    });

    testWidgets('the loading bar sits below the header', (tester) async {
      await _pumpPage(
        tester,
        GlassPage(
          loading: true,
          header: const GlassPageHeader(
            surfaceKey: Key('test-header'),
            title: 'Testseite',
            floatingMaxWidth: null,
          ),
          body: GlassListBody(children: _tiles(1)),
        ),
      );

      expect(
        tester.getRect(find.byType(LinearProgressIndicator)).top,
        tester.getRect(find.byKey(const Key('test-header'))).bottom,
      );
    });

    testWidgets('text is limited to 200 % below the header', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpPage(
        tester,
        _TestPage(body: GlassListBody(children: _tiles(3))),
        size: const Size(320, 640),
      );

      final context = tester.element(find.byKey(const ValueKey('tile-0')));
      expect(MediaQuery.textScalerOf(context).scale(10), 20);
      expect(tester.takeException(), isNull);
    });
  });

  group('cards', () {
    testWidgets('a tile is one button with its title and subtitle',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _pumpPage(
        tester,
        _TestPage(
            body: GlassListBody(children: _tiles(1, onTap: () => taps++))),
      );

      final tile = find.byKey(const ValueKey('tile-0'));
      expect(
        tester.getSemantics(
          find.descendant(of: tile, matching: find.byType(InkWell)),
        ),
        isSemantics(
          label: 'Eintrag 0, Beschreibung 0',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
      await tester.tap(tile);
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('a tile shows the hand and a ring for the keyboard',
        (tester) async {
      await _pumpPage(
        tester,
        _TestPage(body: GlassListBody(children: _tiles(1))),
      );

      final ink = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('tile-0')),
          matching: find.byType(InkWell),
        ),
      );
      expect(ink.mouseCursor, NewDesignTheme.clickCursor);
      expect(
        find.ancestor(
          of: find.byType(GlassCard),
          matching: find.byType(GlassFocusRing),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the state card heads its message', (tester) async {
      final semantics = tester.ensureSemantics();
      var retries = 0;
      await _pumpPage(
        tester,
        _TestPage(
          body: GlassStateCard(
            key: const Key('test-state'),
            icon: Icons.wifi_off_rounded,
            title: 'Offline',
            body: 'Keine Verbindung',
            actionLabel: 'Erneut versuchen',
            onAction: () => retries++,
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('Offline')),
        isSemantics(label: 'Offline', isHeader: true),
      );
      expect(find.text('Keine Verbindung'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(retries, 1);
      semantics.dispose();
    });

    testWidgets('the section heading has its count and action', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpPage(
        tester,
        _TestPage(
          body: GlassListBody(
            children: [
              GlassSectionHeading(
                titleKey: const Key('test-heading'),
                title: 'Fächer',
                count: 12,
                trailing: HeaderDiscButton(
                  key: const Key('test-heading-action'),
                  tooltip: 'Anzeige',
                  icon: Icons.tune_rounded,
                  onPressed: () {},
                ),
              ),
              const GlassOfflineHint(
                key: Key('test-offline'),
                message: 'Stand von gestern',
                onRetry: _noop,
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byKey(const Key('test-heading'))),
        isSemantics(label: 'Fächer  12', isHeader: true),
      );
      expect(find.byKey(const Key('test-heading-action')), findsOneWidget);
      expect(find.text('Stand von gestern'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('glass', () {
    testWidgets('only the header blurs', (tester) async {
      await _pumpPage(
        tester,
        _TestPage(
          body: GlassListBody(
            listKey: const Key('test-list'),
            children: _tiles(3),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('test-list')),
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
        await _pumpPage(
          tester,
          _TestPage(body: GlassListBody(children: _tiles(3))),
          as: Pages.classRegister,
          themeMode: themeMode,
        );

        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          find.descendant(
            of: find.byType(_TestPage),
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

    testWidgets('without blur the header stays', (tester) async {
      GlassPerformance.instance.blurAllowed.value = false;
      addTearDown(GlassPerformance.instance.reset);
      await _pumpPage(
        tester,
        _TestPage(body: GlassListBody(children: _tiles(1))),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('test-title')), findsOneWidget);
    });
  });
}

void _noop() {}
