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
}
