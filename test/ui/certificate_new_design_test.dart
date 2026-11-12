import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show scaffoldKey;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/certificate.dart';
import 'package:dr/ui/certificate_new.dart';
import 'package:dr/ui/export_page_new.dart';
import 'package:dr/ui/extras_page.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../support/test_harness.dart';

const _phone = Size(412, 900);

/// A certificate as schools send it: inline colours for a white page, a
/// table with black borders and a column of remarks.
const _html = '''
<div>
  <h2 style="color:#000000">Zeugnis 1. Semester</h2>
  <p style="color:black">Klasse 4B</p>
  <table border="1" style="border-collapse:collapse; border-color:#000">
    <tr style="background-color:#e0e0e0">
      <th>Fach</th><th>Note</th><th>Fehlstunden</th><th>Bemerkung</th>
    </tr>
    <tr><td>Deutsch</td><td>8</td><td>4</td><td>Mündlich sehr engagiert</td></tr>
    <tr><td>Mathematik</td><td style="color:red">5</td><td>6</td>
      <td>Nachprüfung im September</td></tr>
    <tr><td>Rechtskundeundwirtschaftskunde</td><td>7</td><td>0</td>
      <td>Fachübergreifendesprojektarbeitsergebnis</td></tr>
  </table>
</div>
''';

AppState _state({
  String? html = _html,
  bool offline = false,
  String languageCode = 'de',
}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://example.digitalesregister.it';
      b.noInternet = offline;
      b.settingsState.languageCode = languageCode;
      b.certificateState
        ..html = html
        ..lastFetched = html == null
            ? null
            : UtcDateTime.now().subtract(const Duration(hours: 2));
    });

/// Opens the certificate as Extras does, below the shell of the new design.
/// [page] replaces the container.
Future<void> _pumpCertificate(
  WidgetTester tester, {
  AppState? state,
  Widget? page,
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
  scaffoldKey!.currentState!
      .selectContentWidget(page ?? CertificateContainer(), Pages.certificate);
  await settleFor(tester, duration: const Duration(milliseconds: 500));
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

const _vm = CertificateViewModel(
  html: null,
  baseUrl: null,
  noInternet: false,
  lastFetched: null,
);

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('the new design shows the glass page', (tester) async {
      await _pumpCertificate(tester);

      expect(find.byType(CertificateNew), findsOneWidget);
      expect(find.byType(Certificate), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('certificate-app-header')), findsOneWidget);
    });

    testWidgets('legacy keeps the old page', (tester) async {
      await _pumpCertificate(tester, newDesign: false);

      expect(find.byType(Certificate), findsOneWidget);
      expect(find.byType(CertificateNew), findsNothing);
      expect(find.byType(GlassPageHeader), findsNothing);
    });
  });

  group('content', () {
    testWidgets('the HTML stands in a glass card with a back button',
        (tester) async {
      await _pumpCertificate(tester);

      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('certificate-card')),
          matching: find.byType(HtmlWidget),
        ),
        findsOneWidget,
      );
      expect(
          find.text('Zeugnis 1. Semester', findRichText: true), findsOneWidget);
      expect(find.byKey(const Key('certificate-export')), findsOneWidget);
    });

    testWidgets('the export opens inside the shell and back returns',
        (tester) async {
      await _pumpCertificate(tester);

      await tester.tap(find.byKey(const Key('certificate-export')));
      await settleFor(tester, duration: const Duration(milliseconds: 800));
      expect(find.byType(ExportNewView), findsOneWidget);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('export-category-certificates')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 800));
      expect(find.byType(ExportNewView), findsNothing);
      expect(find.byType(CertificateNew), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('back returns to Extras', (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Offline, so that nothing goes to a server.
      final store = createStore(
        initialState: _state(offline: true),
        newDesign: true,
        withMiddleware: true,
      );
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      await tester.tap(find.byKey(const ValueKey('app-navigation-extras')));
      await settleFor(tester, duration: const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('extras-certificate')));
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(find.byType(CertificateNew), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(seconds: 1));
      expect(find.byType(CertificateNew), findsNothing);
      expect(find.byType(ExtrasPage), findsOneWidget);
      await _finish(tester);
    });
  });

  group('states', () {
    testWidgets('loading shows the bar, then a failed load says so',
        (tester) async {
      final load = Completer<void>();
      var retries = 0;
      await _pumpCertificate(
        tester,
        page: CertificateNew(
          vm: _vm,
          onLoad: () => load.future,
          onRetry: () async => retries++,
        ),
      );

      expect(find.byKey(const Key('certificate-loading')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('certificate-error')), findsNothing);

      load.complete();
      await settleFor(tester);
      expect(find.byKey(const Key('certificate-error')), findsOneWidget);
      expect(find.text('Das Zeugnis konnte nicht geladen werden.'),
          findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await settleFor(tester);
      expect(retries, 1);
    });

    testWidgets('offline without a certificate', (tester) async {
      await _pumpCertificate(tester, state: _state(html: null, offline: true));

      expect(find.byKey(const Key('certificate-offline')), findsOneWidget);
      expect(find.byType(HtmlWidget), findsNothing);
    });

    testWidgets('offline with an older certificate shows the hint',
        (tester) async {
      await _pumpCertificate(tester, state: _state(offline: true));

      expect(find.byKey(const Key('certificate-last-fetched')), findsOneWidget);
      expect(find.byKey(const Key('certificate-card')), findsOneWidget);
    });

    for (final html in const [
      '<p>Zeugnis nicht verfügbar</p>',
      '<p>Report card not available</p>',
      '<div>  </div>',
    ]) {
      testWidgets('no certificate: $html', (tester) async {
        await _pumpCertificate(tester, state: _state(html: html));

        expect(find.byKey(const Key('certificate-empty')), findsOneWidget);
        expect(find.text('Noch kein Zeugnis'), findsOneWidget);
        expect(find.byType(HtmlWidget), findsNothing);
      });
    }
  });

  group('layouts', () {
    for (final size in const [Size(1280, 800), Size(800, 600)]) {
      testWidgets('at ${size.width} x ${size.height} the card is readable',
          (tester) async {
        await _pumpCertificate(tester, size: size);

        final header =
            tester.getRect(find.byKey(const Key('certificate-app-header')));
        final card = tester.getRect(find.byKey(const Key('certificate-card')));
        expect(header.top, DesignTokens.gutter);
        expect(card.width, lessThanOrEqualTo(DesignTokens.contentMaxWidth));
        expect(card.left, header.left);
        expect(card.right, header.right);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('320 px, text at $scale, $name: the table scrolls',
            (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpCertificate(
            tester,
            size: const Size(320, 640),
            themeMode: themeMode,
            amoled: amoled,
          );

          expect(tester.takeException(), isNull);
          final card =
              tester.getRect(find.byKey(const Key('certificate-card')));
          expect(card.width, 320 - 2 * DesignTokens.gutter);
          final scroll = find.byKey(const Key('certificate-table-scroll'));
          expect(scroll, findsOneWidget);
          expect(tester.getRect(scroll).right, lessThanOrEqualTo(card.right));
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: scroll, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(position.maxScrollExtent, greaterThan(0));
        });
      }
    }
  });

  group('colours', () {
    final light = themeController.buildTheme(
      brightness: Brightness.light,
      amoledMode: false,
    );
    final dark = themeController.buildTheme(
      brightness: Brightness.dark,
      amoledMode: false,
    );
    final amoled = themeController.buildTheme(
      brightness: Brightness.dark,
      amoledMode: true,
    );

    test('black text and lines give way on a dark card', () {
      for (final theme in [dark, amoled]) {
        final adapted = adaptCertificateHtml(_html, theme.colorScheme);
        expect(adapted, isNot(contains('#000000')));
        expect(adapted, isNot(contains('color:black')));
        expect(adapted, isNot(contains('#e0e0e0')));
        expect(adapted, contains('Mündlich sehr engagiert'));
        expect(adapted, contains('color:red'));
      }
    });

    test('readable colours stay as the school sent them', () {
      expect(adaptCertificateHtml(_html, light.colorScheme), _html);
    });

    test('the content is never touched', () {
      const plain = 'Nur Text, ohne <b>Farben</b>.';
      for (final theme in [light, dark, amoled]) {
        expect(adaptCertificateHtml(plain, theme.colorScheme), plain);
      }
    });

    test('a certificate is told from the note that there is none', () {
      expect(certificateAvailable(_html), isTrue);
      expect(certificateAvailable('<p>Pagella non disponibile</p>'), isFalse);
      expect(certificateAvailable(''), isFalse);
    });
  });

  group('glass', () {
    testWidgets('only the header blurs', (tester) async {
      await _pumpCertificate(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('certificate-list')),
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

    testWidgets('high contrast has no blur', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpCertificate(tester, themeMode: ThemeMode.dark);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpCertificate(
          tester,
          state: _state(
              html: '<p>Report card not available</p>', languageCode: code),
          size: const Size(320, 640),
        );

        final l10n = tester.element(find.byType(CertificateNew)).l10n;
        expect(
          tester
              .widget<Text>(find.byKey(const Key('certificate-header-title')))
              .data,
          l10n.text('certificate.title'),
        );
        expect(find.text(l10n.text('certificate.empty')), findsOneWidget);
        expect(l10n.text('certificate.empty'), isNot('certificate.empty'));
        expect(l10n.text('certificate.loadFailed'),
            isNot('certificate.loadFailed'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
