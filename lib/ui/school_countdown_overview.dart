// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.

import 'package:dr/app_clock.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_timeline.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SchoolCountdownOverview extends StatelessWidget {
  const SchoolCountdownOverview({
    super.key,
    required this.timeline,
    this.onOpenCalendarAt,
  });

  final SchoolTimeline timeline;
  final Future<void> Function(DateTime date)? onOpenCalendarAt;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appClock,
      builder: (context, _) {
        final today = appClock.now;
        final holiday = timeline.holidayCountdownAt(today);
        final deadline = timeline.gradeDeadlineCountdownAt(today);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HolidayCountdownCard(
                countdown: holiday,
                today: today,
                onOpenCalendarAt: onOpenCalendarAt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GradeDeadlineCountdownCard(
                countdown: deadline,
                onOpenCalendarAt: onOpenCalendarAt,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HolidayCountdownCard extends StatelessWidget {
  const _HolidayCountdownCard({
    required this.countdown,
    required this.today,
    required this.onOpenCalendarAt,
  });

  final HolidayCountdown? countdown;
  final DateTime today;
  final Future<void> Function(DateTime date)? onOpenCalendarAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = countdown;
    if (value == null) {
      return _CountdownCard(
        icon: Icons.beach_access_rounded,
        title: l10n.text('schoolCountdown.holidays.title'),
        primaryText: l10n.text('schoolCountdown.holidays.none'),
        secondaryText: l10n.text('schoolCountdown.missingData'),
      );
    }

    final remaining = value.isOnHoliday
        ? _remainingHolidayText(l10n, value.remainingDays)
        : _remainingDaysText(l10n, value.remainingDays);
    return _CountdownCard(
      key: const ValueKey('holiday-countdown-card'),
      icon: value.isOnHoliday
          ? Icons.celebration_rounded
          : Icons.beach_access_rounded,
      title: l10n.text('schoolCountdown.holidays.title'),
      primaryText: remaining,
      secondaryText: value.isOnHoliday
          ? l10n.text(
              'schoolCountdown.holidays.until',
              args: {'date': _formatDate(context, value.holiday.end)},
            )
          : l10n.text(
              'schoolCountdown.holidays.from',
              args: {'date': _formatDate(context, value.holiday.start)},
            ),
      progress: value.progress,
      onTap: onOpenCalendarAt == null
          ? null
          : () => onOpenCalendarAt!(
                value.isOnHoliday ? today : value.holiday.start,
              ),
    );
  }
}

class _GradeDeadlineCountdownCard extends StatelessWidget {
  const _GradeDeadlineCountdownCard({
    required this.countdown,
    required this.onOpenCalendarAt,
  });

  final GradeDeadlineCountdown? countdown;
  final Future<void> Function(DateTime date)? onOpenCalendarAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = countdown;
    if (value == null) {
      return _CountdownCard(
        icon: Icons.fact_check_outlined,
        title: l10n.text('schoolCountdown.grades.title'),
        primaryText: l10n.text('schoolCountdown.grades.none'),
        secondaryText: l10n.text('schoolCountdown.missingData'),
      );
    }

    return _CountdownCard(
      key: const ValueKey('grade-deadline-countdown-card'),
      icon: Icons.fact_check_outlined,
      title: l10n.text('schoolCountdown.grades.title'),
      primaryText: value.remainingDays == 0
          ? l10n.text('schoolCountdown.grades.today')
          : _remainingDaysText(l10n, value.remainingDays),
      secondaryText: l10n.text(
        'schoolCountdown.grades.date',
        args: {'date': _formatDate(context, value.deadline.date)},
      ),
      progress: value.progress,
      onTap: onOpenCalendarAt == null
          ? null
          : () => onOpenCalendarAt!(value.deadline.date),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    super.key,
    required this.icon,
    required this.title,
    required this.primaryText,
    required this.secondaryText,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String primaryText;
  final String secondaryText;
  final double? progress;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progressValue = progress?.clamp(0.0, 1.0);
    return SizedBox(
      height: 184,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 22, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  primaryText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondaryText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (progressValue != null) ...[
                  const Spacer(),
                  Semantics(
                    label: context.l10n.text('schoolCountdown.progress'),
                    value: '${(progressValue * 100).round()} %',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: progressValue,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      context.l10n.text(
                        'schoolCountdown.progressValue',
                        args: {'percent': '${(progressValue * 100).round()}'},
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _remainingHolidayText(AppLocalizations l10n, int days) {
  if (days == 1) {
    return l10n.text('schoolCountdown.holidays.oneDay');
  }
  return l10n.text(
    'schoolCountdown.holidays.days',
    args: {'days': '$days'},
  );
}

String _remainingDaysText(AppLocalizations l10n, int days) {
  if (days == 1) {
    return l10n.text('schoolCountdown.oneDay');
  }
  return l10n.text(
    'schoolCountdown.days',
    args: {'days': '$days'},
  );
}

String _formatDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
        .format(date);
