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
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:html/parser.dart' as html;
import 'package:intl/intl.dart';

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
    required this.schoolBag,
    required this.preparation,
    required this.planningValidOn,
  });

  final AndroidWidgetSnapshotMeta meta;
  final AndroidDashboardWidgetSnapshot dashboard;
  final AndroidGradesWidgetSnapshot grades;
  final AndroidTodayWidgetSnapshot today;
  final AndroidDashboardWidgetSnapshot schoolBag;
  final AndroidDashboardWidgetSnapshot preparation;
  final String planningValidOn;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': androidWidgetSnapshotSchemaVersion,
      'meta': meta.toJson(),
      'dashboard': dashboard.toJson(),
      'grades': grades.toJson(),
      'today': today.toJson(),
      'schoolBag': schoolBag.toJson(),
      'preparation': preparation.toJson(),
      'planningValidOn': planningValidOn,
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
    this.category,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final String overallAverage;
  final String? category;
  final List<AndroidGradesWidgetItem> subjects;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'emptyMessage': emptyMessage,
      'overallAverage': overallAverage,
      'category': category,
      'subjects': subjects.map((item) => item.toJson()).toList(),
    };
  }
}

class AndroidGradesWidgetItem {
  const AndroidGradesWidgetItem({
    required this.subject,
    required this.average,
    this.category,
  });

  final String subject;
  final String average;
  final String? category;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'subject': subject,
      'average': average,
      'category': category,
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
  final planning = _buildPreparation(state, status);
  return AndroidWidgetSnapshot(
    meta: AndroidWidgetSnapshotMeta(
      status: status,
      generatedAt: realNow,
      languageCode: state.settingsState.languageCode,
    ),
    dashboard: _buildDashboardSnapshot(state),
    grades: _buildGradesSnapshot(state),
    today: _buildTodaySnapshot(state),
    schoolBag: planning.$1,
    preparation: planning.$2,
    planningValidOn: DateFormat('yyyy-MM-dd').format(realNow),
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

String _tr(AppState state, String de, String it, String en) =>
    state.settingsState.languageCode == 'it'
        ? it
        : (state.settingsState.languageCode == 'en' ? en : de);

String _dateLabel(AppState state, UtcDateTime date) {
  final difference = date.stripTime().difference(now.stripTime()).inDays;
  if (difference == 0) return _tr(state, 'Heute', 'Oggi', 'Today');
  if (difference == 1) return _tr(state, 'Morgen', 'Domani', 'Tomorrow');
  return DateFormat('dd.MM.').format(date);
}

AndroidDashboardWidgetSnapshot _buildDashboardSnapshot(AppState state) {
  final ready = _statusForState(state) == AndroidWidgetSnapshotStatus.ready;
  final days = ready
      ? (state.dashboardState.allDays
              ?.where((day) => !day.date.stripTime().isBefore(now.stripTime()))
              .toList() ??
          <Day>[])
      : <Day>[];
  days.sort((a, b) => a.date.compareTo(b.date));
  final items = <AndroidDashboardWidgetItem>[];
  final seen = <String>{};
  final knownSubjects = ready ? state.extractAllSubjects() : <String>[];
  for (final day in days) {
    for (final homework in day.homework) {
      if (homework.deleted || homework.checked) continue;
      final label = displayedHomeworkLabelForDate(
          state, day.date, homework, knownSubjects);
      final key = '${day.date.stripTime()}|${homework.id}|${homework.type}';
      if (!seen.add(key)) continue;
      items.add(AndroidDashboardWidgetItem(
        subject: _widgetText(label ?? _tr(state, 'Eintrag', 'Voce', 'Entry')),
        title: _widgetText(homework.title),
        subtitle: _widgetText(homework.subtitle),
        dayLabel: _dateLabel(state, day.date),
        trailing: homework.gradeFormatted,
        warning: displayedHomeworkWarning(homework, knownSubjects),
        done: false,
      ));
    }
  }
  return AndroidDashboardWidgetSnapshot(
    title: 'Dashboard',
    subtitle:
        _tr(state, 'Kommende Einträge', 'Prossimi impegni', 'Upcoming entries'),
    emptyMessage: _tr(
        state,
        state.dashboardState.allDays == null
            ? 'Dashboard noch nicht geladen'
            : 'Keine kommenden Einträge',
        state.dashboardState.allDays == null
            ? 'Dashboard non ancora caricato'
            : 'Nessun impegno in programma',
        state.dashboardState.allDays == null
            ? 'Dashboard not loaded yet'
            : 'No upcoming entries'),
    items: items.take(40).toList(),
  );
}

AndroidGradesWidgetSnapshot _buildGradesSnapshot(AppState state) {
  final ready = _statusForState(state) == AndroidWidgetSnapshotStatus.ready;
  final semester = state.gradesState.semester;
  final average = ready ? overallGradeAverage(state) : null;
  final subjects = <AndroidGradesWidgetItem>[];
  if (ready) {
    for (final subject in state.gradesState.subjects) {
      final value = subject.average(semester);
      subjects.add(AndroidGradesWidgetItem(
          subject: _widgetText(subject.name),
          average: value == null ? '—' : subject.averageFormatted(semester),
          category: state.settingsState.colorGrades
              ? gradeCategory(value)?.name
              : null));
    }
  }
  return AndroidGradesWidgetSnapshot(
    title: _tr(state, 'Noten', 'Voti', 'Grades'),
    subtitle: semester == Semester.all
        ? _tr(state, 'Beide Semester', 'Entrambi i quadrimestri',
            'Both semesters')
        : _tr(state, '${semester.n}. Semester', '${semester.n}° quadrimestre',
            'Semester ${semester.n}'),
    emptyMessage: _tr(state, 'Noch keine Noten vorhanden',
        'Nessun voto disponibile', 'No grades available yet'),
    overallAverage: average == null ? '' : gradeAverageFormat.format(average),
    category: state.settingsState.colorGrades && average != null
        ? gradeCategory(average * 100)?.name
        : null,
    // Put actual averages before subjects which have no grades yet, retaining
    // the app's order within both groups so small widgets show useful values.
    subjects: [
      ...subjects.where((item) => item.average != '—'),
      ...subjects.where((item) => item.average == '—'),
    ],
  );
}

AndroidTodayWidgetSnapshot _buildTodaySnapshot(AppState state) {
  final ready = _statusForState(state) == AndroidWidgetSnapshotStatus.ready;
  CalendarDay? today;
  if (ready) {
    for (final day in state.calendarState.days.values) {
      if (day.date.stripTime() == now.stripTime()) {
        today = day;
        break;
      }
    }
  }
  final hours = today?.hours.toList() ?? <CalendarHour>[];
  hours.sort((a, b) => a.fromHour.compareTo(b.fromHour));
  return AndroidTodayWidgetSnapshot(
    title: _tr(state, 'Heute', 'Oggi', 'Today'),
    subtitle: DateFormat('dd.MM.yyyy').format(now),
    emptyMessage: _tr(
        state,
        today == null
            ? 'Für heute ist noch kein Stundenplan geladen'
            : 'Heute kein Unterricht',
        today == null
            ? 'Orario di oggi non ancora caricato'
            : 'Oggi nessuna lezione',
        today == null
            ? 'Today’s timetable has not been loaded'
            : 'No lessons today'),
    items: [
      for (final hour in hours)
        AndroidTodayWidgetItem(
          subject: _widgetText(hour.subject),
          timeLabel: hour.timeSpans.isEmpty
              ? _tr(
                  state,
                  '${hour.fromHour}–${hour.toHour}. Stunde',
                  '${hour.fromHour}–${hour.toHour}ª ora',
                  'Period ${hour.fromHour}–${hour.toHour}')
              : '${DateFormat('HH:mm').format(hour.timeSpans.first.from)}–${DateFormat('HH:mm').format(hour.timeSpans.last.to)}',
          roomLabel: hour.rooms.join(' · '),
          warning: hour.warning || hour.isDetectedSubstitute,
        )
    ],
  );
}

// Preparation sections exclude account identifiers, grades and attachments.
(AndroidDashboardWidgetSnapshot, AndroidDashboardWidgetSnapshot)
    _buildPreparation(AppState state, AndroidWidgetSnapshotStatus status) {
  final language = state.settingsState.languageCode;
  String tr(String de, String it, String en) =>
      language == 'it' ? it : (language == 'en' ? en : de);
  final bagTitle = tr('Schultasche', 'Zaino', 'School bag');
  final taskTitle = tr('Hausaufgaben', 'Compiti', 'Homework');
  final open = tr(
      'App öffnen, um aktuelle Daten zu laden',
      'Apri l’app per caricare dati aggiornati',
      'Open the app to load current data');
  AndroidDashboardWidgetSnapshot section(String title, String subtitle,
          String empty, List<AndroidDashboardWidgetItem> items) =>
      AndroidDashboardWidgetSnapshot(
          title: title, subtitle: subtitle, emptyMessage: empty, items: items);
  final unavailable = (
    section(bagTitle, '', open, []),
    section(taskTitle, '', open, []),
  );
  if (status != AndroidWidgetSnapshotStatus.ready) return unavailable;

  final today = now.stripTime();
  final calendar = {
    for (final day in state.calendarState.days.values)
      day.date.stripTime(): day,
  };
  bool fresh(UtcDateTime? fetched) =>
      fetched != null &&
      !fetched.isBefore(realNow.subtract(const Duration(days: 7))) &&
      !fetched.isAfter(realNow.add(const Duration(minutes: 5)));

  CalendarDay? next;
  // Missing weekdays are unknown, not holidays. Explicit empty calendar days
  // may be skipped. Weekend lessons are supported when supplied by the school.
  for (var offset = 1; offset <= 14; offset++) {
    final date = today.add(Duration(days: offset));
    final day = calendar[date];
    if (day == null && date.weekday >= DateTime.saturday) continue;
    if (day == null || !fresh(day.lastFetched)) return unavailable;
    if (day.hours.isNotEmpty) {
      next = day;
      break;
    }
  }
  if (next == null) return unavailable;
  final target = next.date.stripTime();
  final dateLabel = DateFormat('dd.MM.yyyy').format(target);
  final pack = tr('Einpacken', 'Da mettere nello zaino', 'Pack');
  final remove = tr('Kann heraus', 'Da togliere', 'Can remove');
  final materials = tr(
      'Bücher und Materialien für dieses Fach',
      'Libri e materiali per questa materia',
      'Books and materials for this subject');
  AndroidDashboardWidgetItem item(String subject, String title,
          {String subtitle = '', bool warning = false}) =>
      AndroidDashboardWidgetItem(
          subject: _widgetText(subject),
          title: _widgetText(title),
          subtitle: _widgetText(subtitle),
          dayLabel: dateLabel,
          warning: warning,
          done: false);
  final subjects = next.hours
      .map((hour) => hour.subject.trim())
      .where((subject) => subject.isNotEmpty)
      .toSet();
  final bag = [
    for (final subject in subjects) item(subject, pack, subtitle: materials)
  ];
  // Compare with the last known school day, but never cross an unknown weekday.
  CalendarDay? previous;
  for (var offset = 0; offset <= 7; offset++) {
    final date = today.subtract(Duration(days: offset));
    final day = calendar[date];
    if (day == null && date.weekday >= DateTime.saturday) continue;
    if (day == null || !fresh(day.lastFetched)) break;
    if (day.hours.isNotEmpty) {
      previous = day;
      break;
    }
  }
  final tasks = <AndroidDashboardWidgetItem>[];
  final taskSubjects = <String>{};
  final seen = <String>{};
  void addTask(String subject, String title, String subtitle, bool warning) {
    final key =
        '${_widgetText(subject)}|${_widgetText(title)}|${_widgetText(subtitle)}';
    if (!seen.add(key)) return;
    taskSubjects.add(subject.trim());
    tasks.add(item(subject, title, subtitle: subtitle, warning: warning));
  }

  Day? dashboardDay;
  for (final day in state.dashboardState.allDays ?? <Day>[]) {
    if (day.date.stripTime() == target && fresh(day.lastRequested)) {
      dashboardDay = day;
      break;
    }
  }
  if (dashboardDay != null) {
    for (final homework in dashboardDay.homework) {
      if (homework.deleted || homework.checked) continue;
      if (homework.type != HomeworkType.lessonHomework &&
          homework.type != HomeworkType.homework &&
          homework.type != HomeworkType.gradeGroup) {
        continue;
      }
      addTask(homework.label ?? taskTitle, homework.title, homework.subtitle,
          homework.warning);
    }
  }
  // Calendar assessments supplement homework when the dashboard is unavailable.
  for (final hour in next.hours) {
    for (final exam in hour.homeworkExams) {
      if (exam.hasGrades) continue;
      // A dashboard entry is authoritative, including its completion state.
      if (dashboardDay?.homework.any((entry) => entry.id == exam.id) == true) {
        continue;
      }
      addTask(hour.subject, exam.name, exam.typeName, exam.warning);
    }
  }
  if (previous != null && dashboardDay != null) {
    for (final subject
        in previous.hours.map((hour) => hour.subject.trim()).toSet()) {
      if (subject.isEmpty ||
          subjects.contains(subject) ||
          taskSubjects.contains(subject)) {
        continue;
      }
      bag.add(item(subject, remove,
          subtitle: tr(
              'Laut Stundenplan; Materialien für offene Aufgaben behalten',
              'Secondo l’orario; conserva i materiali per i compiti aperti',
              'Based on timetable; keep materials for unfinished work')));
    }
  }
  final loaded = tr('Stand', 'Aggiornato', 'Updated');
  final updated = DateFormat('dd.MM. HH:mm').format(next.lastFetched!);
  final subtitle = '$dateLabel · $loaded $updated';
  if (dashboardDay == null) {
    tasks.add(item(
        taskTitle,
        tr('Hausaufgaben nicht vollständig geladen',
            'Compiti non caricati completamente', 'Homework not fully loaded'),
        subtitle: open,
        warning: true));
  }
  return (
    section(bagTitle, subtitle, open, bag),
    section(
        taskTitle,
        subtitle,
        tr(
            'Keine offenen Aufgaben für diesen Schultag',
            'Nessun compito aperto per questo giorno',
            'No pending tasks for this school day'),
        tasks),
  );
}

String _widgetText(String value) {
  final text = (html.parseFragment(value).text ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length <= 180 ? text : '${text.substring(0, 177)}…';
}
