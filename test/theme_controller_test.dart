import 'package:dr/app_state.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('load restores the theme preference and drops the legacy accent',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      legacyContrastColorPreferenceKey: Colors.green.toARGB32(),
      'followDeviceTheme': false,
      'isDark': true,
      'platformOverride': true,
    });

    final controller = AppThemeController();
    await controller.load();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(legacyContrastColorPreferenceKey), isFalse);
    expect(controller.themePreference, AppThemePreference.dark);
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.platformOverride, isTrue);
  });

  test('setters update shared preferences and controller state', () async {
    final controller = AppThemeController();
    await controller.load();

    await controller.setThemePreference(AppThemePreference.light);
    await controller.setPlatformOverride(true);

    final prefs = await SharedPreferences.getInstance();
    expect(controller.themePreference, AppThemePreference.light);
    expect(controller.platformOverride, isTrue);
    expect(prefs.getBool('followDeviceTheme'), isFalse);
    expect(prefs.getBool('isDark'), isFalse);
    expect(prefs.getBool('platformOverride'), isTrue);
  });

  test('buildTheme uses true black surfaces only in AMOLED dark mode', () {
    final controller = AppThemeController();

    final amoledTheme = controller.buildTheme(
      brightness: Brightness.dark,
      amoledMode: true,
    );
    final darkTheme = controller.buildTheme(
      brightness: Brightness.dark,
      amoledMode: false,
    );
    final lightTheme = controller.buildTheme(
      brightness: Brightness.light,
      amoledMode: true,
    );

    expect(amoledTheme.scaffoldBackgroundColor, Colors.black);
    expect(amoledTheme.colorScheme.surface, Colors.black);
    expect(darkTheme.scaffoldBackgroundColor, isNot(Colors.black));
    expect(lightTheme.scaffoldBackgroundColor, isNot(Colors.black));
    // Light, dark and AMOLED share the same accents per brightness.
    expect(amoledTheme.colorScheme.primary, darkTheme.colorScheme.primary);
    expect(lightTheme.colorScheme.primary, AppPalette.light.primary);
  });

  group('palette contrast', () {
    final schemes = {
      for (final accent in AppAccent.values) ...{
        '${accent.name} light': AppPalette.scheme(
            brightness: Brightness.light, amoled: false, accent: accent),
        '${accent.name} dark': AppPalette.scheme(
            brightness: Brightness.dark, amoled: false, accent: accent),
        '${accent.name} amoled': AppPalette.scheme(
            brightness: Brightness.dark, amoled: true, accent: accent),
      },
    };
    for (final MapEntry(key: name, value: scheme) in schemes.entries) {
      test('$name on-colors meet WCAG AA', () {
        final pairs = <String, (Color, Color)>{
          'primary': (scheme.primary, scheme.onPrimary),
          'primaryContainer': (
            scheme.primaryContainer,
            scheme.onPrimaryContainer
          ),
          'secondary': (scheme.secondary, scheme.onSecondary),
          'secondaryContainer': (
            scheme.secondaryContainer,
            scheme.onSecondaryContainer
          ),
          'tertiary': (scheme.tertiary, scheme.onTertiary),
          'tertiaryContainer': (
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer
          ),
          'error': (scheme.error, scheme.onError),
          'errorContainer': (scheme.errorContainer, scheme.onErrorContainer),
          'surface': (scheme.surface, scheme.onSurface),
          'surfaceVariantText': (scheme.surface, scheme.onSurfaceVariant),
          'containerHighest': (
            scheme.surfaceContainerHighest,
            scheme.onSurfaceVariant
          ),
          'primaryOnSurface': (scheme.surface, scheme.primary),
          'primaryOnCard': (scheme.surfaceContainerLow, scheme.primary),
          'secondaryOnSurface': (scheme.surface, scheme.secondary),
          'tertiaryOnSurface': (scheme.surface, scheme.tertiary),
          'errorOnSurface': (scheme.surface, scheme.error),
          'inverse': (scheme.inverseSurface, scheme.onInverseSurface),
        };
        for (final MapEntry(key: role, value: (bg, fg)) in pairs.entries) {
          expect(
            AppPalette.contrastRatio(bg, fg),
            greaterThanOrEqualTo(4.5),
            reason: '$name $role',
          );
        }
        // The highest container holds tracks and fills, not primary text, so
        // the accent there only needs the 3:1 non-text contrast.
        expect(
          AppPalette.contrastRatio(
              scheme.surfaceContainerHighest, scheme.primary),
          greaterThanOrEqualTo(3),
          reason: '$name primary on highest container',
        );
      });
    }

    test('subject swatches stay visible on light and dark surfaces', () {
      for (final swatch in AppPalette.subjectSwatches) {
        for (final surface in [
          AppPalette.light.surface,
          AppPalette.light.surfaceContainerLowest,
          AppPalette.dark.surface,
          AppPalette.amoled.surface,
        ]) {
          expect(
            AppPalette.contrastRatio(swatch, surface),
            greaterThanOrEqualTo(3),
            reason: '$swatch on $surface',
          );
        }
        // The check mark on a selected swatch is white.
        expect(
          AppPalette.contrastRatio(swatch, Colors.white),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        AppPalette.subjectSwatchNameKeys.length,
        AppPalette.subjectSwatches.length,
      );
    });
  });

  test('blue is the default accent and the choice persists', () async {
    final controller = AppThemeController();
    await controller.load();
    expect(controller.accent, AppAccent.blue);
    expect(
      controller
          .buildTheme(brightness: Brightness.light, amoledMode: false)
          .colorScheme
          .primary,
      AppAccent.blue.seed,
    );

    await controller.setAccent(AppAccent.green);
    final restored = AppThemeController();
    await restored.load();
    expect(restored.accent, AppAccent.green);
    for (final (brightness, amoled) in [
      (Brightness.light, false),
      (Brightness.dark, false),
      (Brightness.dark, true),
    ]) {
      expect(
        restored
            .buildTheme(brightness: brightness, amoledMode: amoled)
            .colorScheme
            .primary,
        AppPalette.scheme(
                brightness: brightness, amoled: amoled, accent: AppAccent.green)
            .primary,
      );
    }
    final amoled =
        restored.buildTheme(brightness: Brightness.dark, amoledMode: true);
    expect(amoled.scaffoldBackgroundColor, Colors.black);
  });

  for (final (legacy, expected) in [
    (0xFF3D79AF, AppAccent.blue),
    (0xFF4CAF50, AppAccent.green),
    (0xFF9C27B0, AppAccent.violet),
    (0xFFE91E63, AppAccent.rose),
    (0xFFFF9800, AppAccent.orange),
    (0xFF009688, AppAccent.teal),
    (0xFF9E9E9E, AppAccent.slate),
  ]) {
    test('legacy accent ${legacy.toRadixString(16)} migrates to $expected',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        legacyContrastColorPreferenceKey: legacy,
      });
      final controller = AppThemeController();
      await controller.load();
      expect(controller.accent, expected);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(legacyContrastColorPreferenceKey), isFalse);
      expect(prefs.getString(accentPreferenceKey), expected.name);
    });
  }

  test('freely picked subject colors migrate to the nearest swatch', () {
    final settings = SettingsState(
      (b) => b
        ..subjectThemes['Rot'] = SubjectTheme(
          (t) => t
            ..color = 0xFFFF0000
            ..thick = 2,
        )
        ..subjectThemes['Swatch'] = SubjectTheme(
          (t) => t
            ..color = AppPalette.subjectSwatches[9].toARGB32()
            ..thick = 3,
        ),
    );

    final migrated = migrateSubjectColorsToPalette(settings);

    expect(
      migrated.subjectThemes['Rot']!.color,
      const Color(0xFFD64545).toARGB32(),
    );
    expect(migrated.subjectThemes['Rot']!.thick, 2);
    expect(migrated.subjectThemes['Swatch'], settings.subjectThemes['Swatch']);
    expect(
      migrated.subjectThemes.values.every((t) => AppPalette.isSwatch(t.color)),
      isTrue,
    );
    expect(migrateSubjectColorsToPalette(migrated), same(migrated));
  });
}
