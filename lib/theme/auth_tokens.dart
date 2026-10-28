// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Design tokens for the sign-in and password recovery screens.
///
/// The authentication flow is the first thing people see, before any accent
/// preference exists, so it uses a fixed, quiet palette: neutral surfaces, one
/// blue accent and one red for errors. Every text/background pairing meets
/// WCAG AA. Fields are identified by their filled surface and label, so their
/// outline can stay faint.
@immutable
class AuthTokens extends ThemeExtension<AuthTokens> {
  const AuthTokens({
    required this.background,
    required this.groupFill,
    required this.fieldFill,
    required this.fieldFillHover,
    required this.fieldFillFocus,
    required this.fieldBorder,
    required this.hairline,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.accentFill,
    required this.accentFillHover,
    required this.accentFillPressed,
    required this.link,
    required this.onAccent,
    required this.switchThumb,
    required this.disabledFill,
    required this.disabledText,
    required this.error,
    required this.errorText,
    required this.destructiveFill,
    required this.avatarFill,
  });

  /// The single continuous page surface.
  final Color background;

  /// Slightly raised rounded groups (saved accounts, notices).
  final Color groupFill;
  final Color fieldFill;

  /// The field fill shifted slightly lighter on hover (+1.5 %) and focus
  /// (+2 % lightness).
  final Color fieldFillHover, fieldFillFocus;

  /// Faint text field outline; the accent replaces it on focus.
  final Color fieldBorder;

  /// Decorative separators inside groups.
  final Color hairline;
  final Color primaryText, secondaryText;

  /// The one accent: focus rings, the switch, links and the primary button.
  final Color accent;
  final Color accentFill, accentFillHover, accentFillPressed;

  /// Accent-coloured text such as "Passwort vergessen".
  final Color link;

  /// The primary button label: white on the deeper light-mode blue, black
  /// on the brighter dark-mode blue (white would only reach 3.65:1 there).
  final Color onAccent;

  /// The switch thumb, which stays white in both modes.
  final Color switchThumb;

  /// The primary button while it cannot be pressed: neutral, not faded blue.
  final Color disabledFill, disabledText;

  /// Error outlines and icons (non-text, 3:1).
  final Color error;

  /// Error messages (text, 4.5:1).
  final Color errorText;

  /// Fill behind white text on destructive confirmations.
  final Color destructiveFill;
  final Color avatarFill;

  static const light = AuthTokens(
    background: Color(0xFFFFFFFF),
    groupFill: Color(0xFFF2F2F7),
    fieldFill: Color(0xFFF2F2F7),
    fieldFillHover: Color(0xFFF7F7FA),
    fieldFillFocus: Color(0xFFF8F8FB),
    fieldBorder: Color(0xFFE5E5EA),
    hairline: Color(0xFFD2D2D7),
    primaryText: Color(0xFF1D1D1F),
    secondaryText: Color(0xFF6E6E73),
    accent: Color(0xFF0071E3),
    accentFill: Color(0xFF0071E3),
    // Hover goes 4 % darker here: lighter would drop white below 4.5:1.
    accentFillHover: Color(0xFF0067CF),
    accentFillPressed: Color(0xFF005DBA),
    link: Color(0xFF0071E3),
    // 4.7:1 on the fill.
    onAccent: Color(0xFFFFFFFF),
    switchThumb: Color(0xFFFFFFFF),
    disabledFill: Color(0xFFE5E5EA),
    disabledText: Color(0xFF8E8E93),
    error: Color(0xFFFF3B30),
    errorText: Color(0xFFD70015),
    destructiveFill: Color(0xFFD70015),
    avatarFill: Color(0xFFE5E5EA),
  );

  static const dark = AuthTokens(
    background: Color(0xFF000000),
    groupFill: Color(0xFF1C1C1E),
    fieldFill: Color(0xFF1C1C1E),
    fieldFillHover: Color(0xFF202022),
    fieldFillFocus: Color(0xFF212123),
    fieldBorder: Color(0xFF2C2C2E),
    hairline: Color(0xFF38383A),
    primaryText: Color(0xFFF5F5F7),
    secondaryText: Color(0xFFA1A1A6),
    accent: Color(0xFF0A84FF),
    accentFill: Color(0xFF0A84FF),
    accentFillHover: Color(0xFF1E8EFF),
    accentFillPressed: Color(0xFF0075EA),
    link: Color(0xFF0A84FF),
    // 5.76:1 on the fill.
    onAccent: Color(0xFF000000),
    switchThumb: Color(0xFFFFFFFF),
    disabledFill: Color(0xFF2C2C2E),
    disabledText: Color(0xFF636366),
    error: Color(0xFFFF453A),
    errorText: Color(0xFFFF453A),
    destructiveFill: Color(0xFFD70015),
    avatarFill: Color(0xFF3A3A3C),
  );

  // Spacing follows a strict 8 px grid.
  static const double space1 = 8, space2 = 16, space3 = 24, space4 = 32;
  static const double space6 = 48;

  static const double maxContentWidth = 400;

  /// Space kept around a focused field's caret when a covered field is
  /// scrolled into view (only then, and only as far as needed): about 24 px
  /// above the keyboard. Flutter keeps at least room for the selection
  /// handle below the caret, which can make it a little more.
  static const fieldScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 24);
  static const double controlHeight = 50;
  static const BorderRadius radius = BorderRadius.all(Radius.circular(12));

  static AuthTokens of(BuildContext context) =>
      Theme.of(context).extension<AuthTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AuthTokens copyWith({
    Color? background,
    Color? groupFill,
    Color? fieldFill,
    Color? fieldFillHover,
    Color? fieldFillFocus,
    Color? fieldBorder,
    Color? hairline,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
    Color? accentFill,
    Color? accentFillHover,
    Color? accentFillPressed,
    Color? link,
    Color? onAccent,
    Color? switchThumb,
    Color? disabledFill,
    Color? disabledText,
    Color? error,
    Color? errorText,
    Color? destructiveFill,
    Color? avatarFill,
  }) {
    return AuthTokens(
      background: background ?? this.background,
      groupFill: groupFill ?? this.groupFill,
      fieldFill: fieldFill ?? this.fieldFill,
      fieldFillHover: fieldFillHover ?? this.fieldFillHover,
      fieldFillFocus: fieldFillFocus ?? this.fieldFillFocus,
      fieldBorder: fieldBorder ?? this.fieldBorder,
      hairline: hairline ?? this.hairline,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      accent: accent ?? this.accent,
      accentFill: accentFill ?? this.accentFill,
      accentFillHover: accentFillHover ?? this.accentFillHover,
      accentFillPressed: accentFillPressed ?? this.accentFillPressed,
      link: link ?? this.link,
      onAccent: onAccent ?? this.onAccent,
      switchThumb: switchThumb ?? this.switchThumb,
      disabledFill: disabledFill ?? this.disabledFill,
      disabledText: disabledText ?? this.disabledText,
      error: error ?? this.error,
      errorText: errorText ?? this.errorText,
      destructiveFill: destructiveFill ?? this.destructiveFill,
      avatarFill: avatarFill ?? this.avatarFill,
    );
  }

  @override
  AuthTokens lerp(AuthTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AuthTokens(
      background: c(background, other.background),
      groupFill: c(groupFill, other.groupFill),
      fieldFill: c(fieldFill, other.fieldFill),
      fieldFillHover: c(fieldFillHover, other.fieldFillHover),
      fieldFillFocus: c(fieldFillFocus, other.fieldFillFocus),
      fieldBorder: c(fieldBorder, other.fieldBorder),
      hairline: c(hairline, other.hairline),
      primaryText: c(primaryText, other.primaryText),
      secondaryText: c(secondaryText, other.secondaryText),
      accent: c(accent, other.accent),
      accentFill: c(accentFill, other.accentFill),
      accentFillHover: c(accentFillHover, other.accentFillHover),
      accentFillPressed: c(accentFillPressed, other.accentFillPressed),
      link: c(link, other.link),
      onAccent: c(onAccent, other.onAccent),
      switchThumb: c(switchThumb, other.switchThumb),
      disabledFill: c(disabledFill, other.disabledFill),
      disabledText: c(disabledText, other.disabledText),
      error: c(error, other.error),
      errorText: c(errorText, other.errorText),
      destructiveFill: c(destructiveFill, other.destructiveFill),
      avatarFill: c(avatarFill, other.avatarFill),
    );
  }
}

/// Motion tokens for the sign-in screens: calm, short and without bounce.
///
/// Only opacity, transforms and size are animated. With reduced motion
/// ([reduced]) movement is dropped entirely and fades shrink to at most
/// [reducedFade].
// A namespace keeps call sites readable (AuthMotion.fast).
// ignore: avoid_classes_with_only_static_members
abstract final class AuthMotion {
  static const instant = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 180);

  /// The primary button waking up.
  static const medium = Duration(milliseconds: 220);

  /// Error lines growing in.
  static const error = Duration(milliseconds: 200);

  /// Rows leaving a list.
  static const exit = Duration(milliseconds: 240);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const entrance = Duration(milliseconds: 700);

  /// Overlays such as the school suggestions.
  static const overlay = Duration(milliseconds: 160);

  /// The rejected-sign-in shake: three decaying swings of [shakeAmplitude].
  static const shake = Duration(milliseconds: 280);
  static const double shakeAmplitude = 4;

  /// Press highlights on rows and links.
  static const press = Duration(milliseconds: 100);

  /// The primary button dipping on press and coming back.
  static const pressIn = Duration(milliseconds: 90);
  static const pressOut = Duration(milliseconds: 160);
  static const reducedFade = Duration(milliseconds: 100);

  /// Bringing a focused field that the keyboard covers into view.
  static const reveal = Duration(milliseconds: 250);

  /// How long size animations stand still after the keyboard starts moving,
  /// so they never run on top of the inset animation.
  static const keyboardSettle = Duration(milliseconds: 450);

  static const Curve standard = Cubic(0.25, 0.1, 0.25, 1.0);
  static const Curve decelerate = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Curve accelerate = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve pressDown = Curves.easeOut;

  /// Release after a press, without overshoot.
  static const Curve pressRelease = Curves.easeOut;

  static const double entranceOffset = 16;
  static const double revealOffset = 6;
  static const double pressScale = 0.985;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration] for an opacity or colour change.
  static Duration fade(BuildContext context, Duration duration) =>
      reduced(context) && duration > reducedFade ? reducedFade : duration;

  /// [duration] for movement, scaling or resizing; none with reduced motion.
  static Duration move(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Vertical rhythm of the sign-in column. [comfortable] is the design;
/// [compact] and [tight] only exist so a first-run screen without saved
/// accounts fits a portrait phone without scrolling.
@immutable
class AuthSpacing {
  const AuthSpacing({
    required this.page,
    required this.icon,
    required this.iconGap,
    required this.title,
    required this.headerGap,
    required this.field,
    required this.section,
    required this.button,
    required this.footer,
  });

  /// Padding above and below the column.
  final double page;
  final double icon, iconGap;

  /// Title size on phones; wide windows always use the comfortable 34 px.
  final double title;

  /// Between the subtitle and the form.
  final double headerGap;

  /// Between fields.
  final double field;

  /// Before a group (password rules, notices).
  final double section;

  /// Above the primary button.
  final double button;

  /// Above saved accounts and the footer.
  final double footer;

  static const comfortable = AuthSpacing(
      page: 48,
      icon: 80,
      iconGap: 32,
      title: 30,
      headerGap: 32,
      field: 16,
      section: 24,
      button: 24,
      footer: 32);
  static const compact = AuthSpacing(
      page: 24,
      icon: 64,
      iconGap: 24,
      title: 28,
      headerGap: 24,
      field: 12,
      section: 16,
      button: 16,
      footer: 24);
  static const tight = AuthSpacing(
      page: 16,
      icon: 56,
      iconGap: 16,
      title: 28,
      headerGap: 16,
      field: 12,
      section: 16,
      button: 12,
      footer: 16);

  /// Only tried when [tight] overflows by less than [ultraTightReach].
  static const ultraTight = AuthSpacing(
      page: 12,
      icon: 48,
      iconGap: 12,
      title: 26,
      headerGap: 12,
      field: 10,
      section: 12,
      button: 10,
      footer: 12);

  /// From roomiest to tightest.
  static const tiers = [comfortable, compact, tight, ultraTight];

  /// Content must leave at least this much of the viewport free to count as
  /// fitting, so rounding and font differences never leave a sliver to
  /// scroll.
  static const double fitMargin = 4;

  /// The largest overflow at [tight] that [ultraTight] may absorb.
  static const double ultraTightReach = 48;
}

/// A rounded field outline that keeps the floating label inside the field
/// (like a filled field) instead of notching it into the border.
class AuthFieldBorder extends InputBorder {
  const AuthFieldBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = AuthTokens.radius,
  });

  final BorderRadius borderRadius;

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  AuthFieldBorder copyWith({BorderSide? borderSide, BorderRadius? radius}) =>
      AuthFieldBorder(
        borderSide: borderSide ?? this.borderSide,
        borderRadius: radius ?? borderRadius,
      );

  @override
  AuthFieldBorder scale(double t) => AuthFieldBorder(
        borderSide: borderSide.scale(t),
        borderRadius: borderRadius * t,
      );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AuthFieldBorder) {
      return AuthFieldBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AuthFieldBorder) {
      return AuthFieldBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect).deflate(borderSide.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.toRRect(rect));

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;
    canvas.drawRRect(
      borderRadius.toRRect(rect).deflate(borderSide.width / 2),
      borderSide.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthFieldBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
