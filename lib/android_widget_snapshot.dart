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
import 'package:dr/utc_date_time.dart';

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
      generatedAt: UtcDateTime.now(),
      languageCode: state.settingsState.languageCode,
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
  return const AndroidDashboardWidgetSnapshot(
    title: 'Dashboard',
    subtitle: 'In der App oeffnen',
    emptyMessage: 'Oeffne die App, um Eintraege anzuzeigen',
    items: <AndroidDashboardWidgetItem>[],
  );
}

AndroidGradesWidgetSnapshot _buildGradesSnapshot(AppState state) {
  return const AndroidGradesWidgetSnapshot(
    title: 'Noten',
    subtitle: 'In der App oeffnen',
    emptyMessage: 'Oeffne die App, um Noten anzuzeigen',
    overallAverage: '',
    subjects: <AndroidGradesWidgetItem>[],
  );
}

AndroidTodayWidgetSnapshot _buildTodaySnapshot(AppState state) {
  return const AndroidTodayWidgetSnapshot(
    title: 'Heute',
    subtitle: 'In der App oeffnen',
    emptyMessage: 'Oeffne die App, um den Stundenplan anzuzeigen',
    items: <AndroidTodayWidgetItem>[],
  );
}
