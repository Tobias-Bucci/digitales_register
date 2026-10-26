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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's single, curated color palette.
///
/// Every scheme is hand-tuned instead of generated from a seed so that light,
/// dark and AMOLED mode share the same identity (slate blue, teal and a warm
/// amber accent) while keeping WCAG AA contrast for all on-color pairs.
// A namespace keeps palette lookups readable at call sites (AppPalette.dark).
// ignore: avoid_classes_with_only_static_members
abstract final class AppPalette {
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2F5DA8),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE6F7),
    onPrimaryContainer: Color(0xFF0F2A55),
    primaryFixed: Color(0xFFDCE6F7),
    primaryFixedDim: Color(0xFF9DBEF5),
    onPrimaryFixed: Color(0xFF0F2A55),
    onPrimaryFixedVariant: Color(0xFF22447D),
    secondary: Color(0xFF00756F),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCDEDEA),
    onSecondaryContainer: Color(0xFF00302D),
    tertiary: Color(0xFFA3501E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFBE1D3),
    onTertiaryContainer: Color(0xFF3B1602),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF7F8FA),
    onSurface: Color(0xFF1A1C20),
    onSurfaceVariant: Color(0xFF464B55),
    surfaceDim: Color(0xFFD8DADF),
    surfaceBright: Color(0xFFF7F8FA),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF1F3F6),
    surfaceContainer: Color(0xFFECEEF2),
    surfaceContainerHigh: Color(0xFFE6E8ED),
    surfaceContainerHighest: Color(0xFFE0E3E8),
    outline: Color(0xFF737985),
    outlineVariant: Color(0xFFC4C8D0),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2E3036),
    onInverseSurface: Color(0xFFF0F1F4),
    inversePrimary: Color(0xFF9DBEF5),
    surfaceTint: Color(0xFF2F5DA8),
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF9DBEF5),
    onPrimary: Color(0xFF0B2A5C),
    primaryContainer: Color(0xFF22447D),
    onPrimaryContainer: Color(0xFFDCE6F7),
    primaryFixed: Color(0xFFDCE6F7),
    primaryFixedDim: Color(0xFF9DBEF5),
    onPrimaryFixed: Color(0xFF0F2A55),
    onPrimaryFixedVariant: Color(0xFF22447D),
    secondary: Color(0xFF6FD6CB),
    onSecondary: Color(0xFF00332F),
    secondaryContainer: Color(0xFF005049),
    onSecondaryContainer: Color(0xFFCDEDEA),
    tertiary: Color(0xFFF2B48C),
    onTertiary: Color(0xFF4A2108),
    tertiaryContainer: Color(0xFF6E3412),
    onTertiaryContainer: Color(0xFFFBE1D3),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF121418),
    onSurface: Color(0xFFE3E5EA),
    onSurfaceVariant: Color(0xFFC2C6CF),
    surfaceDim: Color(0xFF121418),
    surfaceBright: Color(0xFF383B41),
    surfaceContainerLowest: Color(0xFF0D0F12),
    surfaceContainerLow: Color(0xFF1A1C21),
    surfaceContainer: Color(0xFF1E2126),
    surfaceContainerHigh: Color(0xFF282B31),
    surfaceContainerHighest: Color(0xFF33363C),
    outline: Color(0xFF8C919B),
    outlineVariant: Color(0xFF3F444D),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE3E5EA),
    onInverseSurface: Color(0xFF2E3036),
    inversePrimary: Color(0xFF2F5DA8),
    surfaceTint: Color(0xFF9DBEF5),
  );

  /// Dark accents on true black. Containers stay just above black so cards
  /// and sheets remain distinguishable without lighting up OLED pixels.
  static final ColorScheme amoled = dark.copyWith(
    primaryContainer: const Color(0xFF172F57),
    secondaryContainer: const Color(0xFF003833),
    tertiaryContainer: const Color(0xFF4D240C),
    errorContainer: const Color(0xFF690005),
    surface: const Color(0xFF000000),
    surfaceDim: const Color(0xFF000000),
    surfaceBright: const Color(0xFF26282D),
    surfaceContainerLowest: const Color(0xFF000000),
    surfaceContainerLow: const Color(0xFF08090B),
    surfaceContainer: const Color(0xFF0E0F12),
    surfaceContainerHigh: const Color(0xFF16181C),
    surfaceContainerHighest: const Color(0xFF1E2025),
    outlineVariant: const Color(0xFF2C3038),
  );

  static ColorScheme scheme({
    required Brightness brightness,
    required bool amoled,
  }) {
    if (brightness == Brightness.light) return light;
    return amoled ? AppPalette.amoled : dark;
  }

  /// Subject colors. Each is a mid tone that keeps at least 3:1 contrast
  /// against white and against black, so it works as a marker in every theme.
  static const List<Color> subjectSwatches = [
    Color(0xFF3B7DD8), // blue
    Color(0xFF5C6BC0), // indigo
    Color(0xFF8B5CD6), // violet
    Color(0xFFC94F86), // rose
    Color(0xFFD64545), // red
    Color(0xFFD9652B), // orange
    Color(0xFFC27C0E), // amber
    Color(0xFF8A8A1F), // olive
    Color(0xFF3E9A4A), // green
    Color(0xFF13948A), // teal
    Color(0xFF9C6B4E), // brown
    Color(0xFF6B7A8F), // slate
  ];

  /// Localization keys naming each swatch, in [subjectSwatches] order.
  static const List<String> subjectSwatchNameKeys = [
    'palette.swatch.blue',
    'palette.swatch.indigo',
    'palette.swatch.violet',
    'palette.swatch.rose',
    'palette.swatch.red',
    'palette.swatch.orange',
    'palette.swatch.amber',
    'palette.swatch.olive',
    'palette.swatch.green',
    'palette.swatch.teal',
    'palette.swatch.brown',
    'palette.swatch.slate',
  ];

  static bool isSwatch(int argb) =>
      subjectSwatches.any((swatch) => swatch.toARGB32() == argb);

  /// Returns the swatch closest to [argb], used to migrate colors that were
  /// picked freely in earlier versions.
  static Color nearestSwatch(int argb) {
    final color = Color(argb);
    Color best = subjectSwatches.first;
    var bestDistance = double.infinity;
    for (final swatch in subjectSwatches) {
      // Weighted RGB distance ("redmean"), a cheap perceptual approximation.
      final r = (color.r + swatch.r) / 2;
      final dr = color.r - swatch.r;
      final dg = color.g - swatch.g;
      final db = color.b - swatch.b;
      final distance = math.sqrt(
        (2 + r) * dr * dr + 4 * dg * dg + (3 - r) * db * db,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = swatch;
      }
    }
    return best;
  }

  /// Context-free status markers (chart dots, borders). Same mid tones as
  /// the red, amber and green subject swatches, visible in every theme.
  static const Color markerNegative = Color(0xFFD64545);
  static const Color markerWarning = Color(0xFFC27C0E);
  static const Color markerPositive = Color(0xFF3E9A4A);

  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }
}

/// Status roles that Material's [ColorScheme] does not cover. They follow the
/// scheme's brightness and AMOLED containers so they fit the curated palette.
extension AppStatusColors on ColorScheme {
  bool get _isDark => brightness == Brightness.dark;
  bool get _isAmoled => _isDark && surface == const Color(0xFF000000);

  Color get success =>
      _isDark ? const Color(0xFF7FD18B) : const Color(0xFF2E7D32);
  Color get onSuccess =>
      _isDark ? const Color(0xFF00390C) : const Color(0xFFFFFFFF);
  Color get successContainer => _isAmoled
      ? const Color(0xFF12331A)
      : _isDark
          ? const Color(0xFF1E4D26)
          : const Color(0xFFD7F0DA);
  Color get onSuccessContainer =>
      _isDark ? const Color(0xFFD7F0DA) : const Color(0xFF0B3A12);

  Color get warning =>
      _isDark ? const Color(0xFFF5BF5B) : const Color(0xFF9A5B00);
  Color get onWarning =>
      _isDark ? const Color(0xFF3D2400) : const Color(0xFFFFFFFF);
  Color get warningContainer => _isAmoled
      ? const Color(0xFF3D2700)
      : _isDark
          ? const Color(0xFF5C3B00)
          : const Color(0xFFFCE7C2);
  Color get onWarningContainer =>
      _isDark ? const Color(0xFFFCE7C2) : const Color(0xFF3D2400);
}
