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
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final locale =
        context == null ? 'de' : Localizations.localeOf(context).toLanguageTag();
    return DateFormat.Hm(locale).format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final localizedSubject = context.l10n.translateSubjectName(hour.subject);
    final l10n = context.l10n;
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
          iconColor: iconColor,
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
        iconColor: homeworkExam.warning ? Colors.red : Colors.grey,
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
              ],
            ),
            // Time (index and time)
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
    final textColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
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
  });

  @override
  Widget build(BuildContext context) {
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
              SelectableText(content),
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
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.attachment,
            color: Colors.grey,
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
              AnimatedLinearProgressIndicator(show: submission.downloading),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: !submission.fileAvailable && noInternet
                      ? null
                      : () {
                          onOpenFile(submission);
                        },
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
