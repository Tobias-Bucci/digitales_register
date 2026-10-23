import 'package:flutter/material.dart';

/// Visual categories use the existing statistics thresholds, in hundredths.
/// They do not change the passing threshold (6) or any grade calculations.
enum GradeCategory { failing, satisfactory, good }

GradeCategory? gradeCategory(num? hundredths) {
  if (hundredths == null || !hundredths.isFinite || hundredths < 0) return null;
  if (hundredths < 600) return GradeCategory.failing;
  if (hundredths < 800) return GradeCategory.satisfactory;
  return GradeCategory.good;
}

Color? gradeColor(num? hundredths) => switch (gradeCategory(hundredths)) {
      GradeCategory.failing => Colors.red,
      GradeCategory.satisfactory => Colors.orange,
      GradeCategory.good => Colors.green,
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
    final category = colorized ? gradeCategory(hundredths) : null;
    if (category == null) return Text(text, style: textStyle);
    final scheme = Theme.of(context).colorScheme;
    final (foreground, background) = switch (category) {
      GradeCategory.failing => (scheme.onErrorContainer, scheme.errorContainer),
      GradeCategory.satisfactory => (
          Colors.orange.shade900,
          Colors.orange.shade100
        ),
      GradeCategory.good => (Colors.green.shade900, Colors.green.shade100),
    };
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
