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

import 'package:collection/collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/grade_average.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/utc_date_time.dart';

enum DashboardEventKind { grade, message, absence, observation, general }

/// The kind of an unseen feed entry. The portal's types are compared without
/// case sensitivity, as in SchoolNotificationEvent. Everything without a kind
/// of its own stays visible as a general event.
DashboardEventKind dashboardEventKindOf(String? type) =>
    switch (type?.toLowerCase()) {
      'grade' => DashboardEventKind.grade,
      'message' || 'messageshared' => DashboardEventKind.message,
      'absence' => DashboardEventKind.absence,
      'observation' => DashboardEventKind.observation,
      _ => DashboardEventKind.general,
    };

/// One unseen event on the dashboard, in place of a bell.
class DashboardEvent {
  const DashboardEvent({
    required this.kind,
    required this.time,
    required this.description,
    this.detail,
    this.subject,
    this.gradeText,
    this.gradeHundredths,
    this.gradePercent,
    this.averageBefore,
    this.averageAfter,
    this.notification,
    this.homework,
  });

  final DashboardEventKind kind;

  /// When the event was entered.
  final UtcDateTime time;

  /// The main text, such as "1. Schularbeit".
  final String description;

  /// A second line, such as the sender of a message.
  final String? detail;
  final String? subject;

  /// The grade as the app shows it, such as "7/8"; null when the grade of a
  /// notification is not in the loaded data.
  final String? gradeText;
  final int? gradeHundredths;
  final double? gradePercent;

  /// The subject average without and with the grade, in hundredths.
  final int? averageBefore;
  final int? averageAfter;

  /// The feed entry behind the event, if any.
  final Notification? notification;

  /// The dashboard entry behind an observation that has no feed entry.
  final Homework? homework;

  /// Stable across rebuilds while the event stays unseen.
  String get id => notification != null
      ? 'notification-${notification!.id}'
      : 'homework-${homework?.id}';
}

/// The value of a grade in percent, or null for a missing grade.
///
/// Every grade is a share of the ten-point scale, so 6 is 60 %. A slash grade
/// is the value between two grades, not a fraction: 7/8 is 7.50, so 75 %.
double? gradePercentOf(int? hundredths) =>
    hundredths == null ? null : hundredths / 10;

class _GradeMatch {
  const _GradeMatch({
    required this.description,
    required this.gradeHundredths,
    required this.subject,
    this.gradeSubject,
    this.semester,
    this.date,
  });

  final String description;
  final int? gradeHundredths;
  final String? subject;
  final Subject? gradeSubject;
  final Semester? semester;
  final UtcDateTime? date;
}

_GradeMatch? _gradeInGradesState(GradesState state, int id) {
  for (final subject in state.subjects) {
    for (final semesterGrades in subject.grades.entries) {
      for (final grade in semesterGrades.value) {
        if (grade.id == id) {
          return _GradeMatch(
            description: grade.name.isNotEmpty ? grade.name : grade.type,
            gradeHundredths: grade.grade,
            subject: subject.name,
            gradeSubject: subject,
            semester: semesterGrades.key,
            date: grade.date,
          );
        }
      }
    }
  }
  return null;
}

_GradeMatch? _gradeOnDashboard(AppState state, int id) {
  for (final day in state.dashboardState.allDays ?? const <Day>[]) {
    for (final homework in day.homework) {
      if (homework.type == HomeworkType.grade && homework.id == id) {
        final subject = state.gradesState.subjects.firstWhereOrNull(
          (subject) =>
              subject.name.toLowerCase() == homework.label?.toLowerCase(),
        );
        final known = state.extractAllSubjects();
        final subtitle = displayedHomeworkSubtitle(homework, known);
        return _GradeMatch(
          description: subtitle.isNotEmpty
              ? subtitle
              : displayedHomeworkTitle(homework, known),
          gradeHundredths: parseBackendGradeHundredths(homework.grade),
          subject: homework.label,
          gradeSubject: subject,
          date: day.date,
        );
      }
    }
  }
  return null;
}

/// The subject average with the grade and, by leaving it out, before it.
(int?, int?) _averages(_GradeMatch match, Semester selected) {
  final subject = match.gradeSubject;
  final grades = subject?.basicGrades(match.semester ?? selected);
  if (grades == null) return (null, null);
  final index = grades.indexWhere((grade) =>
      grade.grade == match.gradeHundredths &&
      (match.date == null || grade.date == match.date));
  if (index < 0) return (null, weightedGradeAverage(grades));
  return (
    weightedGradeAverage([...grades]..removeAt(index)),
    weightedGradeAverage(grades),
  );
}

DashboardEvent _eventOfNotification(AppState state, Notification notification) {
  final kind = dashboardEventKindOf(notification.type);
  final subTitle = notification.subTitle?.trim() ?? '';
  if (kind == DashboardEventKind.grade) {
    final objectId = notification.objectId;
    final match = objectId == null
        ? null
        : _gradeInGradesState(state.gradesState, objectId) ??
            _gradeOnDashboard(state, objectId);
    if (match != null) {
      final gradeText = match.gradeHundredths == null
          ? null
          : formatGradeFromInt(match.gradeHundredths);
      final averages = _averages(match, state.gradesState.semester);
      return DashboardEvent(
        kind: kind,
        time: notification.timeSent,
        description: match.description,
        subject: match.subject,
        gradeText: gradeText,
        gradeHundredths: match.gradeHundredths,
        gradePercent: gradePercentOf(match.gradeHundredths),
        averageBefore: averages.$1,
        averageAfter: averages.$2,
        notification: notification,
      );
    }
  }
  return DashboardEvent(
    kind: kind,
    time: notification.timeSent,
    description: notification.title,
    detail: subTitle.isEmpty ? null : subTitle,
    notification: notification,
  );
}

/// Every unseen event, newest first. Built only from what the notification feed
/// and the dashboard have already loaded, so it causes no requests.
List<DashboardEvent> dashboardEvents(AppState state) {
  final notifications =
      state.notificationState.notifications ?? const <Notification>[];
  final events = [
    for (final notification in notifications)
      _eventOfNotification(state, notification),
  ];
  final announcedObservations = {
    for (final notification in notifications)
      if (dashboardEventKindOf(notification.type) ==
          DashboardEventKind.observation)
        notification.objectId,
  };
  final known = state.extractAllSubjects();
  for (final day in state.dashboardState.allDays ?? const <Day>[]) {
    for (final homework in day.homework) {
      if (homework.type == HomeworkType.observation &&
          (homework.isNew || homework.isChanged) &&
          !announcedObservations.contains(homework.id)) {
        final subtitle = displayedHomeworkSubtitle(homework, known);
        events.add(DashboardEvent(
          kind: DashboardEventKind.observation,
          time: homework.firstSeen,
          description: subtitle.isNotEmpty
              ? subtitle
              : displayedHomeworkTitle(homework, known),
          subject: homework.label,
          homework: homework,
        ));
      }
    }
  }
  return events..sort((a, b) => b.time.compareTo(a.time));
}

/// How many unread messages the feed reports, for the navigation badge.
int unreadMessageCount(AppState state) =>
    (state.notificationState.notifications ?? const <Notification>[])
        .where((notification) =>
            dashboardEventKindOf(notification.type) ==
            DashboardEventKind.message)
        .length;
