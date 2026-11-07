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
import 'package:material_color_utilities/material_color_utilities.dart';

/// The app's single, curated color palette.
///
/// Neutral surfaces are hand-tuned and shared by every accent. The accent
/// families (primary, secondary, tertiary) come from one of the curated
/// [AppAccent]s: its light-mode primary is fixed, and the remaining roles are
/// HCT tones of the same hue, so every accent keeps WCAG AA contrast in light,
/// dark and AMOLED mode.
// A namespace keeps palette lookups readable at call sites (AppPalette.dark).
// ignore: avoid_classes_with_only_static_members
abstract final class AppPalette {
  static const ColorScheme _lightBase = ColorScheme(
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

  static const ColorScheme _darkBase = ColorScheme(
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
  static final ColorScheme _amoledBase = _darkBase.copyWith(
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

  /// The default (blue) schemes.
  static final ColorScheme light =
      scheme(brightness: Brightness.light, amoled: false);
  static final ColorScheme dark =
      scheme(brightness: Brightness.dark, amoled: false);
  static final ColorScheme amoled =
      scheme(brightness: Brightness.dark, amoled: true);

  static final Map<(AppAccent, Brightness, bool), ColorScheme> _cache = {};

  static ColorScheme scheme({
    required Brightness brightness,
    required bool amoled,
    AppAccent accent = AppAccent.blue,
  }) {
    final isAmoled = amoled && brightness == Brightness.dark;
    return _cache.putIfAbsent(
      (accent, brightness, isAmoled),
      () => _build(accent, brightness, isAmoled),
    );
  }

  static ColorScheme _build(
      AppAccent accent, Brightness brightness, bool amoled) {
    final seed = Hct.fromInt(accent.seed.toARGB32());
    final primary = TonalPalette.of(seed.hue, seed.chroma);
    // Calm companions in the same hue family (Material "tonal spot").
    final secondary = TonalPalette.of(seed.hue, math.min(seed.chroma, 16));
    final tertiary =
        TonalPalette.of((seed.hue + 60) % 360, math.min(seed.chroma, 24));
    Color tone(TonalPalette palette, int tone) => Color(palette.get(tone));

    if (brightness == Brightness.light) {
      return _lightBase.copyWith(
        primary: accent.seed,
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: tone(primary, 90),
        onPrimaryContainer: tone(primary, 10),
        primaryFixed: tone(primary, 90),
        primaryFixedDim: tone(primary, 80),
        onPrimaryFixed: tone(primary, 10),
        onPrimaryFixedVariant: tone(primary, 30),
        secondary: tone(secondary, 40),
        onSecondary: const Color(0xFFFFFFFF),
        secondaryContainer: tone(secondary, 90),
        onSecondaryContainer: tone(secondary, 10),
        tertiary: tone(tertiary, 40),
        onTertiary: const Color(0xFFFFFFFF),
        tertiaryContainer: tone(tertiary, 90),
        onTertiaryContainer: tone(tertiary, 10),
        inversePrimary: tone(primary, 80),
        surfaceTint: accent.seed,
      );
    }
    // On AMOLED, containers sit one tone lower to stay close to black.
    final container = amoled ? 20 : 30;
    return (amoled ? _amoledBase : _darkBase).copyWith(
      primary: tone(primary, 80),
      onPrimary: tone(primary, 20),
      primaryContainer: tone(primary, container),
      onPrimaryContainer: tone(primary, 90),
      primaryFixed: tone(primary, 90),
      primaryFixedDim: tone(primary, 80),
      onPrimaryFixed: tone(primary, 10),
      onPrimaryFixedVariant: tone(primary, 30),
      secondary: tone(secondary, 80),
      onSecondary: tone(secondary, 20),
      secondaryContainer: tone(secondary, container),
      onSecondaryContainer: tone(secondary, 90),
      tertiary: tone(tertiary, 80),
      onTertiary: tone(tertiary, 20),
      tertiaryContainer: tone(tertiary, container),
      onTertiaryContainer: tone(tertiary, 90),
      inversePrimary: accent.seed,
      surfaceTint: tone(primary, 80),
    );
  }

  /// The default subject colors, handed out to subjects that have none yet.
  /// Each is a mid tone that keeps at least 3:1 contrast against white and
  /// against black, so it works as a marker in every theme unchanged.
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

  /// The palettes a subject color can be picked from. All of them hold the same
  /// hues in [subjectSwatchNameKeys] order, so the names fit every palette.
  static const List<SubjectPalette> subjectPalettes = [
    SubjectPalette('palette.group.standard', subjectSwatches),
    SubjectPalette('palette.group.bright', [
      Color(0xFF2196F3), // blue
      Color(0xFF536DFE), // indigo
      Color(0xFFB14DFF), // violet
      Color(0xFFFF4F9A), // rose
      Color(0xFFFF3D3D), // red
      Color(0xFFFF8A00), // orange
      Color(0xFFFFC400), // amber
      Color(0xFFB5C800), // olive
      Color(0xFF22C55E), // green
      Color(0xFF00C9B7), // teal
      Color(0xFFC98A5B), // brown
      Color(0xFF8FA3B8), // slate
    ]),
    SubjectPalette('palette.group.light', [
      Color(0xFF9CC5FF), // blue
      Color(0xFFB3BCFF), // indigo
      Color(0xFFD3B8FF), // violet
      Color(0xFFFFB3D1), // rose
      Color(0xFFFFADA8), // red
      Color(0xFFFFC48F), // orange
      Color(0xFFFFE08A), // amber
      Color(0xFFDDE08A), // olive
      Color(0xFFA8E6AE), // green
      Color(0xFF9DE5DC), // teal
      Color(0xFFDDBFA6), // brown
      Color(0xFFC3CEDC), // slate
    ]),
    SubjectPalette('palette.group.deep', [
      Color(0xFF1E4E9C), // blue
      Color(0xFF303F9F), // indigo
      Color(0xFF5B2A9D), // violet
      Color(0xFF9C1F5C), // rose
      Color(0xFFA32020), // red
      Color(0xFFB0480F), // orange
      Color(0xFF8F5B00), // amber
      Color(0xFF5F6112), // olive
      Color(0xFF1F6B2C), // green
      Color(0xFF0B665F), // teal
      Color(0xFF6B4430), // brown
      Color(0xFF445064), // slate
    ]),
  ];

  /// Black or white, whichever is readable on a fill of [color]. One of the two
  /// always reaches 4.5:1.
  static Color onSubjectColor(Color color) =>
      contrastRatio(color, Colors.white) >= contrastRatio(color, Colors.black)
          ? Colors.white
          : Colors.black;

  static final Map<(int, int, int), Color> _markers = {};

  /// [color] for a thin line, dot or letter on [scheme]'s cards. A color that
  /// would fade into them moves towards more contrast in its own hue, until it
  /// reaches 3:1. Anything visible already stays as it is.
  static Color subjectMarker(Color color, ColorScheme scheme) {
    final surface = scheme.surface;
    final card = scheme.surfaceContainerLowest;
    bool visible(Color candidate) =>
        contrastRatio(candidate, surface) >= 3 &&
        contrastRatio(candidate, card) >= 3;
    if (visible(color)) return color;
    return _markers.putIfAbsent(
      (color.toARGB32(), surface.toARGB32(), card.toARGB32()),
      () {
        final hct = Hct.fromInt(color.toARGB32());
        final step = scheme.brightness == Brightness.dark ? 2 : -2;
        for (var tone = hct.tone; tone >= 0 && tone <= 100; tone += step) {
          final candidate = Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
          if (visible(candidate)) return candidate;
        }
        return scheme.onSurface;
      },
    );
  }

  /// [color] as the background of text in [scheme]'s `onSurface`, as strong as
  /// [alpha] asks for while the text keeps 4.5:1.
  static Color subjectTint(Color color, ColorScheme scheme, double alpha) {
    var tint = color.withValues(alpha: alpha);
    while (tint.a > 0.05 &&
        contrastRatio(
              scheme.onSurface,
              Color.alphaBlend(tint, scheme.surface),
            ) <
            4.5) {
      tint = tint.withValues(alpha: tint.a - 0.05);
    }
    return tint;
  }

  /// Tonal families of the dashboard's event roles. They grow out of the subject
  /// swatches instead of the accent, so a message stays blue on a green accent.
  /// Yellow is the amber swatch turned towards yellow, the same way [_build]
  /// derives the tertiary family from the seed.
  static final TonalPalette _infoTones = _tonesOf(subjectSwatches[0]);
  static final TonalPalette _observationTones = _tonesOf(subjectSwatches[2]);
  static final TonalPalette _noticeTones =
      _tonesOf(subjectSwatches[6], hueShift: 25, minChroma: 56);

  static TonalPalette _tonesOf(
    Color swatch, {
    double hueShift = 0,
    double minChroma = 0,
  }) {
    final hct = Hct.fromInt(swatch.toARGB32());
    return TonalPalette.of(
        (hct.hue + hueShift) % 360, math.max(hct.chroma, minChroma));
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

/// A named set of subject colors, in [AppPalette.subjectSwatchNameKeys] order.
class SubjectPalette {
  const SubjectPalette(this.nameKey, this.swatches);

  final String nameKey;
  final List<Color> swatches;
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

  /// Outline and marker for tests and exams. A saturated red in both modes:
  /// [error] turns a pale salmon in dark mode and the coral marker reads as
  /// orange next to the amber substitute marker.
  Color get exam => _isDark ? const Color(0xFFFF5449) : const Color(0xFFC62828);

  /// Text on a solid [exam] fill. [onError] is only 4.1:1 on it in dark mode,
  /// while the lowest surface keeps at least 4.5:1 in every mode.
  Color get onExam => surfaceContainerLowest;

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

  Color _tone(TonalPalette palette, int tone) => Color(palette.get(tone));
  Color _strong(TonalPalette palette) => _tone(palette, _isDark ? 80 : 40);
  Color _container(TonalPalette palette) =>
      _tone(palette, _isAmoled ? 20 : (_isDark ? 30 : 90));
  Color _onContainer(TonalPalette palette) => _tone(palette, _isDark ? 90 : 10);

  /// Blue, independent of the accent: school messages.
  Color get info => _strong(AppPalette._infoTones);
  Color get infoContainer => _container(AppPalette._infoTones);
  Color get onInfoContainer => _onContainer(AppPalette._infoTones);

  /// Yellow, independent of the accent: absences. Next to [warning], which
  /// reads as orange, it stays clearly distinguishable.
  Color get notice => _strong(AppPalette._noticeTones);
  Color get noticeContainer => _container(AppPalette._noticeTones);
  Color get onNoticeContainer => _onContainer(AppPalette._noticeTones);

  /// Violet, independent of the accent: observations.
  Color get observation => _strong(AppPalette._observationTones);
  Color get observationContainer => _container(AppPalette._observationTones);
  Color get onObservationContainer =>
      _onContainer(AppPalette._observationTones);
}

/// Curated accent colors. Each [seed] is the exact light-mode primary and was
/// chosen to keep at least 4.5:1 contrast for white text on it and for it as
/// text on light surfaces and cards.
enum AppAccent {
  blue(Color(0xFF3972A6), 'palette.accent.blue'),
  violet(Color(0xFF6750A4), 'palette.accent.violet'),
  teal(Color(0xFF00796B), 'palette.accent.teal'),
  green(Color(0xFF2E7D32), 'palette.accent.green'),
  rose(Color(0xFFB03A6B), 'palette.accent.rose'),
  orange(Color(0xFFA0520F), 'palette.accent.orange'),
  slate(Color(0xFF4F5B6B), 'palette.accent.slate');

  const AppAccent(this.seed, this.nameKey);

  final Color seed;
  final String nameKey;

  static AppAccent fromName(String? name) => values.firstWhere(
        (accent) => accent.name == name,
        orElse: () => blue,
      );

  /// Maps a freely picked color from older versions to the closest accent.
  static AppAccent nearest(Color color) {
    final hct = Hct.fromInt(color.toARGB32());
    // Greys and near-greys read best as the neutral slate accent.
    if (hct.chroma < 12) return slate;
    AppAccent best = blue;
    var bestDistance = double.infinity;
    for (final accent in values) {
      if (accent == slate) continue;
      final other = Hct.fromInt(accent.seed.toARGB32());
      final hueDelta = (hct.hue - other.hue).abs() % 360;
      final distance = math.min(hueDelta, 360 - hueDelta);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = accent;
      }
    }
    return best;
  }
}
