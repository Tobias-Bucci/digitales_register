import 'package:dr/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('load restores persisted contrast color and theme preference', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      contrastColorPreferenceKey: Colors.green.toARGB32(),
      'followDeviceTheme': false,
      'isDark': true,
      'platformOverride': true,
    });

    final controller = AppThemeController();
    await controller.load();

    expect(controller.contrastColor.toARGB32(), Colors.green.toARGB32());
    expect(controller.themePreference, AppThemePreference.dark);
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.platformOverride, isTrue);
  });

  test('setters update shared preferences and controller state', () async {
    final controller = AppThemeController();
    await controller.load();

    await controller.setThemePreference(AppThemePreference.light);
    await controller.setPlatformOverride(true);
    await controller.setContrastColor(Colors.orange);

    final prefs = await SharedPreferences.getInstance();
    expect(controller.themePreference, AppThemePreference.light);
    expect(controller.platformOverride, isTrue);
    expect(controller.contrastColor.toARGB32(), Colors.orange.toARGB32());
    expect(prefs.getBool('followDeviceTheme'), isFalse);
    expect(prefs.getBool('isDark'), isFalse);
    expect(prefs.getBool('platformOverride'), isTrue);
    expect(prefs.getInt(contrastColorPreferenceKey), Colors.orange.toARGB32());
  });

  test('buildTheme enables amoled black surfaces only in dark mode', () async {
    final controller = AppThemeController();
    await controller.load();

    final darkTheme = controller.buildTheme(
      brightness: Brightness.dark,
      amoledMode: true,
    );
    final lightTheme = controller.buildTheme(
      brightness: Brightness.light,
      amoledMode: true,
    );

    expect(darkTheme.scaffoldBackgroundColor, Colors.black);
    expect(darkTheme.cardColor, Colors.black);
    expect(lightTheme.scaffoldBackgroundColor, isNot(Colors.black));
  });

  test('exact custom accents survive theme changes and controller reloads',
      () async {
    final controller = AppThemeController();
    addTearDown(controller.dispose);
    await controller.load();

    for (final color in [
      defaultContrastColor,
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
      const Color(0xFF0000FF),
      const Color(0xFFFF00FF),
      const Color(0xFFFFCCDD),
      Colors.black,
      Colors.white,
    ]) {
      await controller.setContrastColor(color);
      for (final preference in AppThemePreference.values) {
        await controller.setThemePreference(preference);
        final restored = AppThemeController();
        await restored.load();
        expect(restored.contrastColor, color);
        for (final brightness in Brightness.values) {
          for (final amoled in [false, true]) {
            final theme = restored.buildTheme(
              brightness: brightness,
              amoledMode: amoled,
            );
            expect(theme.colorScheme.primary, color);
            expect(theme.colorScheme.secondary, color);
            expect(theme.primaryColor, color);
            expect(theme.tabBarTheme.indicatorColor, color);
            final foreground = theme.colorScheme.onPrimary;
            final backgroundLuminance = color.computeLuminance();
            final foregroundLuminance = foreground.computeLuminance();
            final contrast = foregroundLuminance > backgroundLuminance
                ? (foregroundLuminance + 0.05) / (backgroundLuminance + 0.05)
                : (backgroundLuminance + 0.05) / (foregroundLuminance + 0.05);
            expect(contrast, greaterThanOrEqualTo(4.5));
            expect(theme.colorScheme.onSecondary, foreground);
          }
        }
        restored.dispose();
      }
    }
  });
}
