import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:dr/app_state.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/export_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../export_test.dart' show exportFixture;

class _Service extends ExportService {
  bool fail = false;
  bool saved = true;
  int saves = 0;
  List<ExportSection>? sections;
  Completer<ExportFile>? pending;
  @override
  Future<ExportFile> create(
      {required List<ExportSection> sections,
      required ExportFormat format,
      required AppLocalizations l10n,
      required String scope,
      DateTime? created,
      int? schoolYear}) async {
    this.sections = sections;
    if (fail) throw FileSystemException('denied');
    return pending == null
        ? ExportFile('test.pdf', Uint8List.fromList([1]))
        : await pending!.future;
  }

  @override
  Future<bool> save(ExportFile file, String title) async {
    saves++;
    return saved;
  }
}

void main() {
  final boundaryKey = GlobalKey();
  setUpAll(() async {
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  Widget app(
          {AppState? state,
          Locale locale = const Locale('de'),
          ThemeMode mode = ThemeMode.light,
          ExportService service = const ExportService(),
          ExportCategory? initial = ExportCategory.grades,
          Key? pageKey}) =>
      MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          theme:
              ThemeData(fontFamily: 'NotoSans', colorSchemeSeed: Colors.teal),
          darkTheme: ThemeData(
              fontFamily: 'NotoSans',
              colorSchemeSeed: Colors.teal,
              brightness: Brightness.dark),
          themeMode: mode,
          home: RepaintBoundary(
              key: boundaryKey,
              child: ExportPage(
                  key: pageKey,
                  state: state ?? exportFixture(),
                  initialCategory: initial,
                  service: service)));

  for (final locale in AppLocalizations.supportedLocales) {
    for (final dark in [false, true]) {
      testWidgets(
          'responsive ${locale.toLanguageTag()} ${dark ? 'dark' : 'light'} at large text scale',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
            app(locale: locale, mode: dark ? ThemeMode.dark : ThemeMode.light));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const dir = String.fromEnvironment('EXPORT_PREVIEW_DIR');
        if (dir.isNotEmpty &&
            locale.languageCode == 'de' &&
            locale.countryCode == null) {
          await tester.runAsync(() async {
            final boundary = boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$dir/ui_${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.scrollUntilVisible(
            find.byWidgetPredicate((w) => w is FilledButton), 400,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final selection = find.byIcon(Icons.tune);
        await tester.ensureVisible(selection);
        await tester.pumpAndSettle();
        await tester.tap(selection);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final l10n = await AppLocalizations.load(locale);
        await tester.tap(find.text(l10n.text('export.cancel')));
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('year filtering and saving use the visible selection',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(app(service: service));
    await tester.pumpAndSettle();
    final year = find.byType(DropdownButtonFormField<int>);
    await tester.scrollUntilVisible(year, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(year);
    await tester.pumpAndSettle();
    await tester.tap(year);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025-2026').last);
    await tester.pumpAndSettle();
    final save = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.sections!.single.records, hasLength(4));
    expect(service.saves, 1);
    expect(find.text('Die Datei wurde gespeichert.'), findsOneWidget);
  });

  testWidgets('individual entries constrain the saved data and averages',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(app(service: service));
    await tester.pumpAndSettle();
    final selection = find.byIcon(Icons.tune);
    await tester.scrollUntilVisible(selection, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(selection);
    await tester.pumpAndSettle();
    await tester.tap(selection);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswahl aufheben'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    final save = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.sections!.single.records, hasLength(1));
    expect(service.sections!.single.overallAverage, 4);
  });

  testWidgets(
      'empty, cancellation and failures are understandable and recoverable',
      (tester) async {
    await tester.pumpWidget(app(state: AppState()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byWidgetPredicate((w) => w is FilledButton), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((w) => w is FilledButton))
            .onPressed,
        isNull);
    final service = _Service()..saved = false;
    await tester.pumpWidget(app(service: service));
    await tester.pumpAndSettle();
    final save = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Speichern abgebrochen.'), findsOneWidget);
    service.fail = true;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Prüfe den freien Speicherplatz'), findsOneWidget);
    service.fail = false;
    service.saved = true;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Die Datei wurde gespeichert.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposing an account during generation never opens its save dialog',
      (tester) async {
    final service = _Service()..pending = Completer<ExportFile>();
    await tester
        .pumpWidget(app(service: service, pageKey: const ValueKey('account1')));
    await tester.pumpAndSettle();
    final save = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.scrollUntilVisible(save, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pump();
    await tester
        .pumpWidget(app(service: service, pageKey: const ValueKey('account2')));
    await tester.pump();
    service.pending!.complete(ExportFile('old.pdf', Uint8List(1)));
    await tester.pumpAndSettle();
    expect(service.saves, 0);
    expect(tester.takeException(), isNull);
  });
}
