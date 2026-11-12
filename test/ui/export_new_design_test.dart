import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show nestedNavKey;
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/app_navigation.dart';
import 'package:dr/ui/export_page.dart';
import 'package:dr/ui/export_page_new.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../export_test.dart' show exportFixture;
import '../support/test_harness.dart';

const _phone = Size(412, 900);

class _Service extends ExportService {
  bool fail = false;
  int saves = 0;
  ExportFormat? format;
  Completer<ExportFile>? pending;

  @override
  Future<ExportFile> create({
    required List<ExportSection> sections,
    required ExportFormat format,
    required AppLocalizations l10n,
    required String scope,
    DateTime? created,
    int? schoolYear,
  }) async {
    this.format = format;
    if (fail) throw const FileSystemException('denied');
    return pending == null
        ? ExportFile('test.pdf', Uint8List.fromList([1]))
        : await pending!.future;
  }

  @override
  Future<bool> save(ExportFile file, String title) async {
    saves++;
    return true;
  }
}

AppState _shell({String languageCode = 'de'}) => AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>();
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.settingsState.languageCode = languageCode;
    });

/// Opens the export inside the shell of the new design, as Messages,
/// Certificate and Settings do.
Future<void> _pumpExport(
  WidgetTester tester, {
  ExportService? service,
  AppState? state,
  bool loading = false,
  bool loadFailed = false,
  Future<void> Function()? onReload,
  Size size = _phone,
  ThemeMode themeMode = ThemeMode.light,
  bool amoled = false,
  String languageCode = 'de',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = createStore(
    initialState: _shell(languageCode: languageCode),
    newDesign: true,
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
  unawaited(nestedNavKey.currentState!.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/export'),
    builder: (_) => ExportPage(
      state: state ?? exportFixture(),
      initialCategory: ExportCategory.grades,
      loading: loading,
      loadFailed: loadFailed,
      onReload: onReload ?? () async {},
      service: service ?? _Service(),
    ),
  )));
  await settleFor(tester, duration: const Duration(milliseconds: 800));
}

final _save = find.byKey(const Key('export-save'));

GlassSegmentedControl<ExportFormat> _segments(WidgetTester tester) =>
    tester.widget(find.byType(GlassSegmentedControl<ExportFormat>));

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(_save);
  await settleFor(tester);
  await tester.tap(_save);
  await tester.pump();
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  group('design switch', () {
    testWidgets('inside the shell the glass page shows', (tester) async {
      await _pumpExport(tester);

      expect(find.byType(ExportNewView), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SegmentedButton<ExportFormat>), findsNothing);
      expect(find.byKey(const Key('export-app-header')), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(FloatingNavigationBar), findsOneWidget);
    });

    testWidgets('outside the shell the legacy page stays', (tester) async {
      await tester.pumpWidget(buildTestApp(
        store: createStore(initialState: _shell()),
        home: ExportPage(
          state: exportFixture(),
          initialCategory: ExportCategory.grades,
        ),
      ));
      await settleFor(tester);

      expect(find.byType(ExportNewView), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(GlassPageHeader), findsNothing);
      expect(find.byType(CheckboxListTile), findsWidgets);
    });
  });

  group('content', () {
    testWidgets('categories, options, selection and the save button',
        (tester) async {
      await _pumpExport(tester);

      for (final c in ExportCategory.values) {
        expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(ValueKey('export-category-${c.name}')))
              .value,
          c == ExportCategory.grades,
        );
      }
      expect(find.byKey(const Key('export-options')), findsOneWidget);
      expect(find.byType(GlassSegmentedControl<ExportFormat>), findsOneWidget);
      expect(find.byKey(const ValueKey('export-selection-grades')),
          findsOneWidget);
      expect(
        find.descendant(of: _save, matching: find.textContaining('(')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);
    });

    testWidgets('choosing categories and the format', (tester) async {
      final service = _Service();
      await _pumpExport(tester, service: service);

      await tester.tap(find.byKey(const ValueKey('export-category-messages')));
      await settleFor(tester);
      expect(find.byKey(const ValueKey('export-selection-messages')),
          findsOneWidget);

      _segments(tester).onChanged(ExportFormat.csv);
      await settleFor(tester);
      expect(_segments(tester).selected, ExportFormat.csv);
      expect(
        find.text('Jede Kategorie erhält eine CSV-Datei im gemeinsamen '
            'ZIP-Archiv.'),
        findsOneWidget,
      );
      await _tapSave(tester);
      await settleFor(tester);
      expect(service.format, ExportFormat.csv);
      expect(service.saves, 1);

      // Without a category there is nothing to save.
      for (final c in ['grades', 'messages']) {
        tester
            .widget<CheckboxListTile>(
                find.byKey(ValueKey('export-category-$c')))
            .onChanged!(false);
        await settleFor(tester);
      }
      expect(find.byKey(const Key('export-options')), findsNothing);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('single entries are chosen in a dialog', (tester) async {
      await _pumpExport(tester);

      final entries = find.byKey(const ValueKey('export-selection-grades'));
      await tester.ensureVisible(entries);
      await settleFor(tester);
      await tester.tap(entries);
      await settleFor(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await settleFor(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('states', () {
    testWidgets('busy, then saved', (tester) async {
      final service = _Service()..pending = Completer<ExportFile>();
      await _pumpExport(tester, service: service);

      await _tapSave(tester);
      await settleFor(tester);
      expect(find.text('Datei wird erstellt …'), findsOneWidget);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(
        find.descendant(
            of: _save, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      // The page stays while the file is made.
      await tester.tap(find.byType(BackButton));
      await settleFor(tester);
      expect(find.byType(ExportNewView), findsOneWidget);

      service.pending!.complete(ExportFile('a.pdf', Uint8List(1)));
      await settleFor(tester);
      expect(find.byKey(const Key('export-status')), findsOneWidget);
      expect(find.text('Die Datei wurde gespeichert.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_save).onPressed, isNotNull);

      await tester.tap(find.byType(BackButton));
      await settleFor(tester, duration: const Duration(milliseconds: 800));
      expect(find.byType(ExportNewView), findsNothing);
    });

    testWidgets('a failure is shown as an error', (tester) async {
      await _pumpExport(tester, service: _Service()..fail = true);

      await _tapSave(tester);
      await settleFor(tester);
      expect(find.byKey(const Key('export-error')), findsOneWidget);
      expect(find.textContaining('Prüfe den freien Speicherplatz'),
          findsOneWidget);
    });

    testWidgets('loading', (tester) async {
      await _pumpExport(tester, loading: true);
      expect(find.byKey(const Key('export-loading')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    });

    testWidgets('a failed load, with reload', (tester) async {
      var reloads = 0;
      await _pumpExport(
        tester,
        loadFailed: true,
        onReload: () async => reloads++,
      );
      expect(find.byKey(const Key('export-load-failed')), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-reload')));
      await tester.pump();
      expect(reloads, 1);
    });

    testWidgets('nothing loaded: nothing to save', (tester) async {
      await _pumpExport(tester, state: AppState());

      expect(tester.widget<FilledButton>(_save).onPressed, isNull);
      expect(find.byKey(const Key('export-empty')), findsOneWidget);
    });
  });

  group('layouts', () {
    testWidgets('from 1080 px the categories stand beside the options',
        (tester) async {
      await _pumpExport(tester, size: const Size(1280, 800));

      final categories =
          tester.getRect(find.byKey(const Key('export-categories')));
      final options = tester.getRect(find.byKey(const Key('export-options')));
      expect(options.left, greaterThan(categories.right));
      final header = tester.getRect(find.byKey(const Key('export-app-header')));
      expect(header.top, DesignTokens.gutter);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a phone it is one list', (tester) async {
      await _pumpExport(tester);

      final categories =
          tester.getRect(find.byKey(const Key('export-categories')));
      final options = tester.getRect(find.byKey(const Key('export-options')));
      expect(options.top, greaterThan(categories.bottom));
      expect(options.width, categories.width);
    });

    for (final (name, themeMode, amoled) in const [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('AMOLED', ThemeMode.dark, true),
    ]) {
      testWidgets('320 px, text at 2.0, $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpExport(
          tester,
          size: const Size(320, 640),
          themeMode: themeMode,
          amoled: amoled,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_save);
        await settleFor(tester);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_save).height, greaterThanOrEqualTo(48));
      });
    }
  });

  group('glass', () {
    testWidgets('only the header blurs', (tester) async {
      await _pumpExport(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('export-list')),
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
      await _pumpExport(tester, themeMode: ThemeMode.dark);

      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpExport(tester);

      _segments(tester).onChanged(ExportFormat.csv);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_segments(tester).selected, ExportFormat.csv);
    });
  });

  group('languages', () {
    for (final code in const ['de', 'it', 'en', 'lld']) {
      testWidgets('in $code', (tester) async {
        await _pumpExport(
          tester,
          languageCode: code,
          size: const Size(320, 640),
        );

        final l10n = tester.element(find.byType(ExportNewView)).l10n;
        expect(
          tester
              .widget<Text>(find.byKey(const Key('export-header-title')))
              .data,
          l10n.text('export.title'),
        );
        expect(find.text(l10n.text('export.category.grades')), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
