import 'dart:async';
import 'package:dr/analytics_service.dart';
// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:dr/diagnostics_service.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Removed in favor of the curated palette; deleted from prefs on load.
const legacyContrastColorPreferenceKey = "contrastColor";
const _themeBrightnessPreferenceKey = "isDark";
const _followDeviceThemePreferenceKey = "followDeviceTheme";
const platformOverridePreferenceKey = "platformOverride";

enum AppThemePreference {
  light,
  dark,
  system,
}

class AppThemeController extends ChangeNotifier with WidgetsBindingObserver {
  AppThemeController();

  AppThemePreference _themePreference = AppThemePreference.system;
  bool _platformOverride = false;

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
    if (prefs.containsKey(legacyContrastColorPreferenceKey)) {
      await prefs.remove(legacyContrastColorPreferenceKey);
    }

    _platformOverride = prefs.getBool(platformOverridePreferenceKey) ?? false;

    final followDevice = prefs.getBool(_followDeviceThemePreferenceKey) ?? true;
    if (followDevice) {
      _themePreference = AppThemePreference.system;
    } else {
      final isDark = prefs.getBool(_themeBrightnessPreferenceKey) ?? false;
      _themePreference =
          isDark ? AppThemePreference.dark : AppThemePreference.light;
    }
    diagnostics.update('theme', _themePreference.name);
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themePreference == AppThemePreference.system) {
      diagnostics.update('theme', _themePreference.name);
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
    final isDark = brightness == Brightness.dark;
    final amoled = amoledMode && isDark;
    final scheme = AppPalette.scheme(brightness: brightness, amoled: amoled);
    final baseTheme = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      tabBarTheme: TabBarThemeData(indicatorColor: scheme.primary),
    );
    final appBarTheme = baseTheme.appBarTheme.copyWith(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: amoled ? 0 : (isDark ? 10 : 6),
      shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.36 : 0.12),
      surfaceTintColor: amoled
          ? Colors.transparent
          : isDark
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.18)
              : scheme.surfaceTint.withValues(alpha: 0.08),
      shape: Border(
        bottom: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.55),
        ),
      ),
    );
    if (!amoled) {
      return baseTheme.copyWith(appBarTheme: appBarTheme);
    }

    // On AMOLED, page-level surfaces stay pure black. Raised surfaces use the
    // near-black containers with a thin outline instead of shadows.
    final outlinedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return baseTheme.copyWith(
      cardColor: scheme.surfaceContainerLow,
      shadowColor: Colors.black,
      appBarTheme: appBarTheme,
      cardTheme: baseTheme.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: outlinedShape,
      ),
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: Colors.black,
      ),
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: scheme.surfaceContainer,
        modalBackgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    _themePreference = preference;
    unawaited(AnalyticsService.product
        .updateUserProperties({'theme': preference.name}));
    unawaited(AnalyticsService.product
        .event('theme_changed', {'theme': preference.name}));
    diagnostics.update('theme', _themePreference.name);
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
    diagnostics.update('theme', _themePreference.name);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(platformOverridePreferenceKey, value);
    // If platform override is enabled, stop following device theme.
    await prefs.setBool(_followDeviceThemePreferenceKey, !value);
  }
}

final AppThemeController themeController = AppThemeController();
