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

import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

const int androidWidgetSnapshotSchemaVersion = 1;

enum AndroidWidgetSnapshotStatus {
  ready,
  loggedOut,
  dataSavingDisabled,
  appLocked,
}

class AndroidWidgetSnapshot {
  const AndroidWidgetSnapshot({
    required this.meta,
    required this.dashboard,
    required this.grades,
    required this.today,
  });

  final AndroidWidgetSnapshotMeta meta;
  final AndroidDashboardWidgetSnapshot dashboard;
  final AndroidGradesWidgetSnapshot grades;
  final AndroidTodayWidgetSnapshot today;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': androidWidgetSnapshotSchemaVersion,
      'meta': meta.toJson(),
      'dashboard': dashboard.toJson(),
      'grades': grades.toJson(),
      'today': today.toJson(),
    };
  }
}

class AndroidWidgetSnapshotMeta {
  const AndroidWidgetSnapshotMeta({
    required this.status,
    required this.generatedAt,
    required this.languageCode,
    this.username,
    this.server,
  });

  final AndroidWidgetSnapshotStatus status;
  final UtcDateTime generatedAt;
  final String languageCode;
  final String? username;
  final String? server;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'generatedAt': generatedAt.toIso8601String(),
      'languageCode': languageCode,
      'username': username,
      'server': server,
    };
  }
}

class AndroidDashboardWidgetSnapshot {
  const AndroidDashboardWidgetSnapshot({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.items,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<AndroidDashboardWidgetItem> items;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'emptyMessage': emptyMessage,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class AndroidDashboardWidgetItem {
  const AndroidDashboardWidgetItem({
    required this.subject,
    required this.title,
    required this.subtitle,
    required this.dayLabel,
    this.trailing,
    required this.warning,
    required this.done,
  });

  final String subject;
  final String title;
  final String subtitle;
  final String dayLabel;
  final String? trailing;
  final bool warning;
  final bool done;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'subject': subject,
      'title': title,
      'subtitle': subtitle,
      'dayLabel': dayLabel,
      'trailing': trailing,
      'warning': warning,
      'done': done,
    };
  }
}

class AndroidGradesWidgetSnapshot {
  const AndroidGradesWidgetSnapshot({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.overallAverage,
    required this.subjects,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final String overallAverage;
  final List<AndroidGradesWidgetItem> subjects;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'emptyMessage': emptyMessage,
      'overallAverage': overallAverage,
      'subjects': subjects.map((item) => item.toJson()).toList(),
    };
  }
}

class AndroidGradesWidgetItem {
  const AndroidGradesWidgetItem({
    required this.subject,
    required this.average,
  });

  final String subject;
  final String average;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'subject': subject,
      'average': average,
    };
  }
}

class AndroidTodayWidgetSnapshot {
  const AndroidTodayWidgetSnapshot({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.items,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<AndroidTodayWidgetItem> items;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'emptyMessage': emptyMessage,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class AndroidTodayWidgetItem {
  const AndroidTodayWidgetItem({
    required this.subject,
    required this.timeLabel,
    required this.roomLabel,
    required this.warning,
  });

  final String subject;
  final String timeLabel;
  final String roomLabel;
  final bool warning;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'subject': subject,
      'timeLabel': timeLabel,
      'roomLabel': roomLabel,
      'warning': warning,
    };
  }
}

AndroidWidgetSnapshot buildAndroidWidgetSnapshot(AppState state) {
  final status = _statusForState(state);
  return AndroidWidgetSnapshot(
    meta: AndroidWidgetSnapshotMeta(
      status: status,
      generatedAt: now,
      languageCode: state.settingsState.languageCode,
      username: state.loginState.username,
      server: state.url,
    ),
    dashboard: _buildDashboardSnapshot(state),
    grades: _buildGradesSnapshot(state),
    today: _buildTodaySnapshot(state),
  );
}

AndroidWidgetSnapshotStatus _statusForState(AppState state) {
  if (!state.loginState.loggedIn || state.loginState.username == null) {
    return AndroidWidgetSnapshotStatus.loggedOut;
  }
  if (state.settingsState.noDataSaving) {
    return AndroidWidgetSnapshotStatus.dataSavingDisabled;
  }
  if (state.settingsState.biometricAppLockEnabled) {
    return AndroidWidgetSnapshotStatus.appLocked;
  }
  return AndroidWidgetSnapshotStatus.ready;
}

AndroidDashboardWidgetSnapshot _buildDashboardSnapshot(AppState state) {
  final items = appSelectors
      .dashboardDays(state)
      .expand(
        (day) => day.homework.map(
          (homework) => AndroidDashboardWidgetItem(
            subject: _subjectLabel(state, homework.label),
            title: homework.title,
            subtitle: homework.subtitle,
            dayLabel: day.displayName,
            trailing: homework.gradeFormatted,
            warning: homework.warning,
            done: homework.checked,
          ),
        ),
      )
      .take(5)
      .toList(growable: false);

  return AndroidDashboardWidgetSnapshot(
    title: 'Dashboard',
    subtitle: state.dashboardState.future
        ? 'Kommende Eintraege'
        : 'Vergangene Eintraege',
    emptyMessage: 'Keine Dashboard-Eintraege vorhanden',
    items: items,
  );
}

AndroidGradesWidgetSnapshot _buildGradesSnapshot(AppState state) {
  final favoriteSubjects = state.settingsState.favoriteSubjects;
  final semester = state.gradesState.semester;
  final subjects = state.gradesState.subjects.toList()
    ..sort(
      (a, b) {
        final aFavorite = containsSubjectIgnoreCase(favoriteSubjects, a.name);
        final bFavorite = containsSubjectIgnoreCase(favoriteSubjects, b.name);
        if (aFavorite != bFavorite) {
          return aFavorite ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      },
    );

  final gradeItems = subjects
      .where((subject) => subject.average(semester) != null)
      .map(
        (subject) => AndroidGradesWidgetItem(
          subject: _subjectLabel(state, subject.name),
          average: subject.averageFormatted(semester),
        ),
      )
      .toList(growable: false);

  return AndroidGradesWidgetSnapshot(
    title: 'Noten',
    subtitle: semester.name,
    emptyMessage: 'Keine Notendaten vorhanden',
    overallAverage: appSelectors.allSubjectsAverage(state),
    subjects: gradeItems,
  );
}

AndroidTodayWidgetSnapshot _buildTodaySnapshot(AppState state) {
  final todayDate = UtcDateTime(now.year, now.month, now.day);
  CalendarDay? today;
  for (final day in state.calendarState.days.values) {
    if (day.date == todayDate) {
      today = day;
      break;
    }
  }

  final items = (today?.hours.toList() ?? const <CalendarHour>[])
      .map(
        (hour) => AndroidTodayWidgetItem(
          subject: _subjectLabel(state, hour.subject),
          timeLabel:
              '${hour.fromHour}.${hour.toHour == hour.fromHour ? '' : '-${hour.toHour}.'} Stunde',
          roomLabel: hour.rooms.isEmpty ? 'Kein Raum' : hour.rooms.join(', '),
          warning: hour.warning,
        ),
      )
      .take(6)
      .toList(growable: false);

  return AndroidTodayWidgetSnapshot(
    title: 'Heute',
    subtitle: Day.format(todayDate),
    emptyMessage: 'Keine Stunden fuer heute gespeichert',
    items: items,
  );
}

String _subjectLabel(AppState state, String? subject) {
  if (subject == null || subject.isEmpty) {
    return 'Ohne Fach';
  }
  final resolvedKey =
      findSubjectIgnoreCase(state.settingsState.subjectNicks.keys, subject);
  final nick = state.settingsState.subjectNicks[subject] ??
      (resolvedKey == null
          ? null
          : state.settingsState.subjectNicks[resolvedKey]);
  return nick ?? subject;
}
