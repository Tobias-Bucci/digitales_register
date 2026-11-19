import 'dart:math' as math;

import 'package:dr/dashboard_events.dart'
    show DashboardEventKind, dashboardEventKindOf;
import 'package:dr/data.dart' show Notification, formatGradeFromInt;
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/ui/server_notifications/school_notification_grade.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Shown for icon names this version does not know yet.
const serverNotificationFallbackIcon = Icons.campaign_outlined;

/// The icon names of the contract. New ones can appear on the server at any
/// time, and they get [serverNotificationFallbackIcon] until mapped here.
const serverNotificationIcons = <String, IconData>{
  'info': Icons.info_outline_rounded,
  'update': Icons.system_update_alt_rounded,
  'wrench': Icons.build_outlined,
  'warning': Icons.warning_amber_rounded,
  'bell': Icons.notifications_none_rounded,
  'calendar': Icons.event_outlined,
  'megaphone': Icons.campaign_outlined,
  'shield': Icons.shield_outlined,
  'star': Icons.star_outline_rounded,
  'poll': Icons.poll_outlined,
};

IconData serverNotificationIcon(String name) =>
    serverNotificationIcons[name] ?? serverNotificationFallbackIcon;

/// The type keys of the contract that the app names in its own language.
const serverNotificationTranslatedTypeKeys = {
  'info',
  'update',
  'maintenance',
  'critical',
  'poll',
};

/// The name of [type] to show and to speak. The server writes its label in
/// one language only, so the well-known keys get the app's translation; any
/// other key keeps the server's label.
String serverNotificationTypeLabel(
  AppLocalizations l10n,
  ServerNotificationType type,
) =>
    serverNotificationTranslatedTypeKeys.contains(type.key)
        ? l10n.text('appNotifications.type.${type.key}')
        : type.label;

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

/// [color] moved towards [towards] until it reaches WCAG AA against
/// [background]. The server picks type colors without knowing the theme.
Color readableServerNotificationColor(
  Color color, {
  required Color background,
  required Color towards,
}) {
  for (var step = 0.0; step <= 1; step += 0.05) {
    final candidate = Color.lerp(color, towards, step)!;
    if (_contrast(candidate, background) >= 4.5) return candidate;
  }
  return towards;
}

/// Colors of a notification type on the current theme.
class ServerNotificationTypeColors {
  factory ServerNotificationTypeColors.of(
    BuildContext context,
    ServerNotificationType type,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final base =
        type.colorValue == null ? scheme.primary : Color(type.colorValue!);
    final background = Color.alphaBlend(
      base.withValues(alpha: 0.16),
      scheme.surfaceContainerLow,
    );
    return ServerNotificationTypeColors._(
      background: background,
      foreground: readableServerNotificationColor(base,
          background: background, towards: scheme.onSurface),
    );
  }

  const ServerNotificationTypeColors._({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

/// The type's icon on a tint of its color. Decorative for screen readers,
/// because the label next to it says the same.
class ServerNotificationTypeIcon extends StatelessWidget {
  const ServerNotificationTypeIcon({
    super.key,
    required this.type,
    this.size = 40,
  });

  final ServerNotificationType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ServerNotificationTypeColors.of(context, type);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(
          serverNotificationIcon(type.icon),
          size: size * 0.55,
          color: colors.foreground,
        ),
      ),
    );
  }
}

/// Marks an entry of the school's feed, next to [ServerNotificationTypeIcon]s.
///
/// What it shows follows the entry's [type] (#153): a clock for absences, the
/// grade itself for a new grade, and the school for everything else. A grade
/// whose text has no usable grade shows the icon of the grades instead of a
/// number. Decorative for screen readers, because the text next to it says
/// the same.
class SchoolNotificationIcon extends StatelessWidget {
  const SchoolNotificationIcon({
    super.key,
    this.type,
    this.grade,
    this.colorGrades = true,
    this.size = 40,
  });

  /// The icon of [notification], with the grade its text announces.
  SchoolNotificationIcon.of(
    Notification notification, {
    Key? key,
    bool colorGrades = true,
    double size = 40,
  }) : this(
          key: key,
          type: notification.type,
          grade: schoolNotificationGradeOf(notification),
          colorGrades: colorGrades,
          size: size,
        );

  /// The type of the feed entry, such as `grade` or `absence`, in any case.
  final String? type;

  /// The grade of the entry, shown for entries of the type `grade` only.
  final SchoolNotificationGrade? grade;

  /// Whether the grade takes the colour of its badge on the grades page.
  final bool colorGrades;
  final double size;

  /// The grade as the grades page writes it, or as the register wrote it
  /// when the app cannot read it.
  String _gradeText(BuildContext context, SchoolNotificationGrade grade) {
    final hundredths = grade.hundredths;
    if (hundredths == null) return grade.text;
    final text = formatGradeFromInt(hundredths);
    return text.contains(',') && ResponsiveNavigationScope.isActive(context)
        ? GradesFormat.of(context).grade(text)
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = dashboardEventKindOf(type);
    final grade = kind == DashboardEventKind.grade ? this.grade : null;
    final (foreground, background) =
        (colorGrades ? gradeBadgeColors(scheme, grade?.hundredths) : null) ??
            (scheme.onSecondaryContainer, scheme.secondaryContainer);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: grade == null ? null : EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: grade != null
            // Long values and large text shrink to fit instead of being cut.
            ? Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _gradeText(context, grade),
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                  ),
                ),
              )
            : Icon(
                switch (kind) {
                  DashboardEventKind.absence => Icons.schedule_rounded,
                  DashboardEventKind.grade => Icons.auto_graph_rounded,
                  _ => Icons.school_outlined,
                },
                size: size * 0.55,
                color: foreground,
              ),
      ),
    );
  }
}

/// Like [formatServerNotificationTime] for the school's wall-clock timestamps,
/// which must not be converted to another zone.
String formatSchoolNotificationTime(BuildContext context, DateTime time) {
  final tag = context.l10n.locale.toLanguageTag();
  return DateFormat('d. MMM yyyy, HH:mm', tag).format(time);
}

/// Date and time in the user's language and time zone.
String formatServerNotificationTime(BuildContext context, DateTime time) {
  final tag = context.l10n.locale.toLanguageTag();
  return DateFormat('d. MMM yyyy, HH:mm', tag).format(time.toLocal());
}
