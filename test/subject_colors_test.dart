import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/subject_swatch_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _allSwatches = [
  for (final palette in AppPalette.subjectPalettes) ...palette.swatches,
];

final _schemes = {
  'light': AppPalette.light,
  'dark': AppPalette.dark,
  'amoled': AppPalette.amoled,
};

SettingsState _withColor(int color) => SettingsState(
      (b) => b.subjectThemes['Mathematik'] = SubjectTheme((t) => t
        ..color = color
        ..thick = 3),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('saved subject colors', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('every palette color survives a restart exactly', () async {
      for (final swatch in _allSwatches) {
        final color = swatch.toARGB32();
        await SettingsPersistenceService().save(_withColor(color));
        final restored = await SettingsPersistenceService().load();
        expect(restored!.subjectThemes['Mathematik']!.color, color);
      }
    });

    test('a color from an older version is not replaced', () async {
      const freelyPicked = 0xFFFF0000;
      SharedPreferences.setMockInitialValues({
        globalSettingsPreferenceKey: json.encode(
          serializers.serialize(_withColor(freelyPicked)),
        ),
      });

      final service = SettingsPersistenceService();
      final restored = await service.load();
      expect(restored!.subjectThemes['Mathematik']!.color, freelyPicked);
      expect(restored.subjectThemes['Mathematik']!.thick, 3);

      await service.save(restored);
      final again = await SettingsPersistenceService().load();
      expect(again!.subjectThemes['Mathematik']!.color, freelyPicked);
    });
  });

  group('palettes', () {
    test('every palette holds one color per name', () {
      expect(AppPalette.subjectPalettes.length, greaterThan(1));
      for (final palette in AppPalette.subjectPalettes) {
        expect(
          palette.swatches.length,
          AppPalette.subjectSwatchNameKeys.length,
          reason: palette.nameKey,
        );
      }
    });

    test('no color is offered twice', () {
      expect(
        _allSwatches.map((c) => c.toARGB32()).toSet(),
        hasLength(_allSwatches.length),
      );
    });

    test('text on a filled swatch stays readable', () {
      for (final swatch in _allSwatches) {
        expect(
          AppPalette.contrastRatio(swatch, AppPalette.onSubjectColor(swatch)),
          greaterThanOrEqualTo(4.5),
          reason: '$swatch',
        );
      }
    });

    _schemes.forEach((name, scheme) {
      test('markers stay visible in $name', () {
        for (final swatch in _allSwatches) {
          final marker = AppPalette.subjectMarker(swatch, scheme);
          for (final surface in [
            scheme.surface,
            scheme.surfaceContainerLowest,
          ]) {
            expect(
              AppPalette.contrastRatio(marker, surface),
              greaterThanOrEqualTo(3),
              reason: '$swatch on $surface',
            );
          }
        }
      });

      test('calendar text stays readable on tints in $name', () {
        for (final swatch in _allSwatches) {
          for (final alpha in [0.25, 0.5]) {
            final tint = AppPalette.subjectTint(swatch, scheme, alpha);
            expect(
              AppPalette.contrastRatio(
                scheme.onSurface,
                Color.alphaBlend(tint, scheme.surface),
              ),
              greaterThanOrEqualTo(4.5),
              reason: '$swatch at $alpha',
            );
          }
        }
      });

      test('the standard colors are not changed in $name', () {
        for (final swatch in AppPalette.subjectSwatches) {
          expect(AppPalette.subjectMarker(swatch, scheme), swatch);
        }
      });
    });

    test('a pale marker keeps its hue', () {
      const pale = Color(0xFF9CC5FF);
      final marker = AppPalette.subjectMarker(pale, AppPalette.light);
      expect(marker, isNot(pale));
      expect(marker.b, greaterThan(marker.r));
    });
  });

  group('picker', () {
    Future<void> pump(
      WidgetTester tester, {
      required Color current,
      ValueChanged<Color>? onSelected,
    }) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SubjectSwatchPicker(
            subject: 'Mathematik',
            current: current,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('names every palette and picks from any of them',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      Color? picked;
      await pump(tester,
          current: AppPalette.subjectSwatches.first,
          onSelected: (color) => picked = color);

      for (final name in ['Standard', 'Bright', 'Light', 'Deep']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Current color'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Light, Green'));
      expect(picked, const Color(0xFFA8E6AE));
    });

    testWidgets('a color from no palette is offered as the current one',
        (tester) async {
      await pump(tester, current: const Color(0xFF123456));

      expect(find.text('Current color'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });
}
