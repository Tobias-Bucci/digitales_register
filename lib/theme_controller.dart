import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const contrastColorPreferenceKey = "contrastColor";
const _themeBrightnessPreferenceKey = "isDark";
const _followDeviceThemePreferenceKey = "followDeviceTheme";
const _platformOverridePreferenceKey = "platformOverride";
const defaultContrastColor = Color(0xFF3D79AF);

enum AppThemePreference {
  light,
  dark,
  system,
}

class AppThemeController extends ChangeNotifier with WidgetsBindingObserver {
  AppThemeController();

  Color _contrastColor = defaultContrastColor;
  AppThemePreference _themePreference = AppThemePreference.system;
  bool _platformOverride = false;

  Color get contrastColor => _contrastColor;
  AppThemePreference get themePreference => _themePreference;
  bool get platformOverride => _platformOverride;

  ThemeMode get themeMode {
    switch (_themePreference) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
      case AppThemePreference.system:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    final persistedColor = prefs.getInt(contrastColorPreferenceKey);
    if (persistedColor != null) {
      _contrastColor = Color(persistedColor);
    }

    final followDevice = prefs.getBool(_followDeviceThemePreferenceKey) ?? true;
    if (followDevice) {
      _themePreference = AppThemePreference.system;
    } else {
      final isDark = prefs.getBool(_themeBrightnessPreferenceKey) ?? false;
      _themePreference =
          isDark ? AppThemePreference.dark : AppThemePreference.light;
    }
    _platformOverride = prefs.getBool(_platformOverridePreferenceKey) ?? false;
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themePreference == AppThemePreference.system) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  ThemeData buildTheme({
    required Brightness brightness,
    required bool amoledMode,
  }) {
    TargetPlatform? platform;
    if (_platformOverride && Platform.isAndroid) {
      platform = TargetPlatform.iOS;
    }
    final baseTheme = ThemeData(
      colorSchemeSeed: _contrastColor,
      brightness: brightness,
      platform: platform,
    );
    if (!amoledMode || brightness != Brightness.dark) {
      return baseTheme;
    }

    final amoledScheme = baseTheme.colorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerHighest: Colors.black,
      primaryContainer: Colors.black,
      secondaryContainer: Colors.black,
      tertiaryContainer: Colors.black,
      errorContainer: Colors.black,
    );
    return baseTheme.copyWith(
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
      cardColor: Colors.black,
      dividerColor: Colors.black,
      shadowColor: Colors.black,
      colorScheme: amoledScheme,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
      ),
      cardTheme: baseTheme.cardTheme.copyWith(
        color: Colors.black,
        surfaceTintColor: Colors.black,
        shadowColor: Colors.black,
      ),
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.black,
      ),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: Colors.black,
        modalBackgroundColor: Colors.black,
      ),
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
        color: Colors.black,
      ),
      listTileTheme: baseTheme.listTileTheme.copyWith(
        tileColor: Colors.black,
      ),
    );
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    _themePreference = preference;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _followDeviceThemePreferenceKey,
      preference == AppThemePreference.system,
    );
    if (preference != AppThemePreference.system) {
      await prefs.setBool(
        _themeBrightnessPreferenceKey,
        preference == AppThemePreference.dark,
      );
    }
  }

  Future<void> setPlatformOverride(bool value) async {
    _platformOverride = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_platformOverridePreferenceKey, value);
  }

  Future<void> setContrastColor(Color color) async {
    _contrastColor = color;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(contrastColorPreferenceKey, color.toARGB32());
  }
}

final AppThemeController themeController = AppThemeController();
