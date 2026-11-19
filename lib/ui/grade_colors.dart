import 'package:dr/grades/grade_category.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:flutter/material.dart';

Color? gradeColor(num? hundredths) => switch (gradeCategory(hundredths)) {
      GradeCategory.failing => AppPalette.markerNegative,
      GradeCategory.satisfactory => AppPalette.markerWarning,
      GradeCategory.good => AppPalette.markerPositive,
      null => null,
    };

/// The foreground and background of the badge of [hundredths], by
/// [gradeCategory], or null for a missing grade. Every grade badge uses it.
(Color, Color)? gradeBadgeColors(ColorScheme scheme, num? hundredths) =>
    switch (gradeCategory(hundredths)) {
      GradeCategory.failing => (scheme.onErrorContainer, scheme.errorContainer),
      GradeCategory.satisfactory => (
          scheme.onWarningContainer,
          scheme.warningContainer
        ),
      GradeCategory.good => (
          scheme.onSuccessContainer,
          scheme.successContainer
        ),
      null => null,
    };

/// A shared badge for individual grades and averages. Missing grades remain
/// plain text, as do grades when the user's color preference is disabled.
class GradeBadge extends StatelessWidget {
  const GradeBadge({
    super.key,
    required this.text,
    required this.hundredths,
    required this.colorized,
    this.style,
    this.cancelled = false,
  });

  final String text;
  final num? hundredths;
  final bool colorized;
  final TextStyle? style;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    var textStyle = style;
    if (cancelled) {
      textStyle = (textStyle ?? const TextStyle())
          .copyWith(decoration: TextDecoration.lineThrough);
    }
    final colors = colorized
        ? gradeBadgeColors(Theme.of(context).colorScheme, hundredths)
        : null;
    if (colors == null) return Text(text, style: textStyle);
    final (foreground, background) = colors;
    return DecoratedBox(
      decoration:
          ShapeDecoration(color: background, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(text,
            style: (textStyle ?? const TextStyle()).copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}
