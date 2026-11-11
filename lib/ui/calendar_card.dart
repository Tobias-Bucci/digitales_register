// Copyright (C) 2021 Michael Debertol
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

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/external_links.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/main.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

typedef SubmissionCallback = void Function(LessonContentSubmission submission);

class CalendarCard extends StatelessWidget {
  final CalendarHour hour;
  final SubjectTheme theme;
  final bool selected;
  final SubmissionCallback onOpenFile;
  final bool noInternet;

  const CalendarCard({
    super.key,
    required this.hour,
    required this.theme,
    required this.selected,
    required this.onOpenFile,
    required this.noInternet,
  });

  String formatTime(UtcDateTime dateTime) {
    final context = navigatorKey?.currentContext;
    final locale = context == null
        ? 'de'
        : Localizations.localeOf(context).toLanguageTag();
    return DateFormat.Hm(locale).format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final localizedSubject = context.l10n.translateSubjectName(hour.subject);
    final l10n = context.l10n;
    final newDesign = ResponsiveNavigationScope.isActive(context);
    final contentRows = <Widget>[];
    final seenRows = <String>{};

    void addContentRow({
      required String title,
      required String content,
      required IconData icon,
      Color iconColor = Colors.grey,
    }) {
      final normalizedTitle = title.trim().toLowerCase();
      final normalizedContent = content.trim().toLowerCase();
      final dedupeKey = '$normalizedTitle|$normalizedContent';
      if (normalizedContent.isEmpty || !seenRows.add(dedupeKey)) {
        return;
      }
      contentRows.add(
        _ContentItem(
          title: title,
          content: content,
          icon: icon,
          iconColor: newDesign && iconColor == Colors.grey
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : iconColor,
          newDesign: newDesign,
        ),
      );
    }

    if (hour.teachers.isNotEmpty) {
      addContentRow(
        title: hour.teachers.length == 1
            ? l10n.text('calendar.teacher.single')
            : l10n.text('calendar.teacher.multiple'),
        content:
            hour.teachers.map((t) => "${t.firstName} ${t.lastName}").join(", "),
        icon: hour.teachers.length == 1 ? Icons.person : Icons.people,
      );
    }
    if (hour.rooms.isNotEmpty) {
      addContentRow(
        title: l10n.text('calendar.rooms'),
        content: hour.rooms.join(", "),
        icon: Icons.meeting_room,
      );
    }
    for (final lessonContent in hour.lessonContents) {
      addContentRow(
        title: lessonContent.typeName,
        content: lessonContent.name,
        icon: Icons.school,
      );
      for (final submission in lessonContent.submissions) {
        contentRows.add(
          _SubmissionWidget(
            submission: submission,
            noInternet: noInternet,
            onOpenFile: onOpenFile,
            newDesign: newDesign,
          ),
        );
      }
    }
    for (final homeworkExam in hour.homeworkExams) {
      final title = homeworkExam.homework
          ? l10n.text('dashboard.homework')
          : l10n.translateSchoolTerm(homeworkExam.typeName);
      addContentRow(
        title: title,
        content: homeworkExam.name,
        icon: homeworkExam.warning ? Icons.grade : Icons.assignment,
        iconColor: homeworkExam.warning
            ? Theme.of(context).colorScheme.exam
            : Theme.of(context).colorScheme.onSurfaceVariant,
      );
      if (isLocalReminderAssessmentHomeworkExam(homeworkExam)) {
        addContentRow(
          title: l10n.text('calendar.selfCreatedAssessment'),
          content: l10n.text(
            'calendar.selfCreatedAssessmentBody',
            args: {'type': l10n.translateSchoolTerm(homeworkExam.typeName)},
          ),
          icon: Icons.edit_note,
        );
      }
    }

    final timeRow = hour.timeSpans.isEmpty
        ? null
        : _ContentItem(
            title: hour.fromHour == hour.toHour
                ? l10n.text(
                    'calendar.period.single',
                    args: {'from': hour.fromHour.toString()},
                  )
                : l10n.text(
                    'calendar.period.range',
                    args: {
                      'from': hour.fromHour.toString(),
                      'to': hour.toHour.toString(),
                    },
                  ),
            content: hour.timeSpans
                .map((span) =>
                    "${formatTime(span.from)} – ${formatTime(span.to)}")
                .join(", "),
            icon: Icons.schedule,
            iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
            newDesign: true,
          );
    if (newDesign) {
      return _GlassCalendarCard(
        hour: hour,
        subject: localizedSubject,
        color: Color(theme.color),
        selected: selected,
        rows: [if (timeRow != null) timeRow, ...contentRows],
      );
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: selected
            ? BorderSide(
                color: Theme.of(context).colorScheme.secondary,
                width: 2,
              )
            : BorderSide.none,
      ),
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (name + teacher)
            Row(
              children: [
                CircledLetter(
                  letter: localizedSubject.characters.first,
                  color: Color(theme.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizedSubject,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (hour.isDetectedSubstitute)
                  Container(
                    key: const Key('calendar-substitute-chip'),
                    width: 6,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppPalette.markerWarning,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            // Time (index and time)
            if (hour.timeSpans.isNotEmpty)
              _ContentItem(
                title: hour.fromHour == hour.toHour
                    ? l10n.text(
                        'calendar.period.single',
                        args: {'from': hour.fromHour.toString()},
                      )
                    : l10n.text(
                        'calendar.period.range',
                        args: {
                          'from': hour.fromHour.toString(),
                          'to': hour.toHour.toString(),
                        },
                      ),
                content: hour.timeSpans
                    .map((span) =>
                        "${formatTime(span.from)} – ${formatTime(span.to)}")
                    .join(", "),
                icon: Icons.schedule,
              ),
            ...contentRows,
          ]
              .expand(
                (element) => [
                  const SizedBox(height: 8),
                  element,
                ],
              )
              .toList(),
        ),
      ),
    );
  }
}

/// A letter in a colored circle
class CircledLetter extends StatelessWidget {
  final String letter;
  final Color color;
  const CircledLetter({
    super.key,
    required this.letter,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AppPalette.onSubjectColor(color);
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: textColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ContentItem extends StatelessWidget {
  final String title, content;
  final IconData icon;
  final Color iconColor;
  const _ContentItem({
    required this.title,
    required this.content,
    required this.icon,
    this.iconColor = Colors.grey,
    this.newDesign = false,
  });

  final bool newDesign;

  @override
  Widget build(BuildContext context) {
    if (newDesign) {
      final theme = Theme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                LinkifiedText(
                  content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            icon,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              LinkifiedText(content),
            ],
          ),
        )
      ],
    );
  }
}

class _SubmissionWidget extends StatelessWidget {
  final LessonContentSubmission submission;
  final bool noInternet;
  final SubmissionCallback onOpenFile;
  const _SubmissionWidget({
    required this.submission,
    required this.noInternet,
    required this.onOpenFile,
    this.newDesign = false,
  });

  final bool newDesign;

  @override
  Widget build(BuildContext context) {
    final caption = submission.isLink
        ? linkCaption(submission.originalName, submission.link)
        : null;
    final canOpen = submission.isLink
        ? parseExternalLink(submission.link) != null
        : submission.fileAvailable || !noInternet;
    if (newDesign) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              submission.isLink ? Icons.link_rounded : Icons.attachment,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.attachmentLabel(1),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  submission.originalName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                AnimatedLinearProgressIndicator(show: submission.downloading),
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: glassControlStyle(scheme),
                  onPressed: canOpen ? () => onOpenFile(submission) : null,
                  icon: Icon(
                    submission.isLink
                        ? Icons.open_in_new_rounded
                        : Icons.file_open_outlined,
                    size: 18,
                  ),
                  label: Text(context.l10n.text('common.open')),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            submission.isLink ? Icons.link_rounded : Icons.attachment,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.attachmentLabel(1),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                submission.originalName,
              ),
              if (caption != null)
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              AnimatedLinearProgressIndicator(show: submission.downloading),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: canOpen
                      ? () {
                          onOpenFile(submission);
                        }
                      : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(context.l10n.text('common.open')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A lesson of the day in the new design: a glass card with the subject in
/// its colour, then the facts of the lesson.
class _GlassCalendarCard extends StatelessWidget {
  const _GlassCalendarCard({
    required this.hour,
    required this.subject,
    required this.color,
    required this.selected,
    required this.rows,
  });

  final CalendarHour hour;
  final String subject;
  final Color color;
  final bool selected;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      foregroundDecoration: selected
          ? ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: DesignTokens.cardBorderRadius,
                side: BorderSide(color: scheme.primary, width: 2),
              ),
            )
          : null,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          subject.characters.first,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppPalette.onSubjectColor(color),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      subject,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (hour.isDetectedSubstitute)
                  Container(
                    key: const Key('calendar-substitute-chip'),
                    width: 6,
                    height: 32,
                    decoration: ShapeDecoration(
                      color: scheme.warning,
                      shape: const StadiumBorder(),
                    ),
                  ),
              ],
            ),
            for (final row in rows) ...[
              const SizedBox(height: 10),
              row,
            ],
          ],
        ),
      ),
    );
  }
}
