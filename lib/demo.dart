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

import 'dart:convert';
import 'dart:io';

import 'package:dr/util.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<dynamic> getDemoResponse(String url, dynamic args) async {
  await _demoStore.ensureLoaded();
  return _demoStore.handle(url, (args as Map<String, Object?>?) ?? const {});
}

Future<dynamic> getDemoBytesResponse(
  String url, {
  required List<int> bytes,
  required String contentType,
  required String fileName,
}) async {
  await _demoStore.ensureLoaded();
  return _demoStore.handleUpload(
    url,
    bytes: bytes,
    contentType: contentType,
    fileName: fileName,
  );
}

Future<void> initializeDemoStore() => _demoStore.ensureLoaded();

@visibleForTesting
Future<void> resetDemoStoreForTest() async {
  await _demoStore.resetForTest();
}

final _DemoStore _demoStore = _DemoStore();

class _DemoStore {
  static const String _storageFileName = 'demo_store_v2.json';

  bool _loaded = false;
  late Map<String, dynamic> _state;
  int _currentSemester = 1;
  String? _storagePath;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _state = _initialState();
    final file = await _storageFile();
    if (await file.exists()) {
      try {
        final decoded = json.decode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          _state = _mergeState(_initialState(), decoded);
        }
      } catch (_) {
        _state = _initialState();
      }
    } else {
      await _persist();
    }
    _loaded = true;
  }

  Future<void> resetForTest() async {
    _loaded = false;
    _storagePath = null;
    final file = await _storageFile();
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        if (await file.exists()) {
          await file.writeAsString('{}');
        }
      }
    }
  }

  dynamic handle(String url, Map<String, Object?> args) {
    if (url.startsWith('?semesterWechsel=')) {
      _currentSemester = int.tryParse(url.split('=').last) ?? 1;
      return <String, Object?>{'success': true};
    }

    switch (url) {
      case 'api/student/all_subjects':
        return _buildAllSubjectsResponse();
      case 'api/student/subject_detail':
        return json.encode(_buildSubjectDetailResponse(args));
      case 'api/student/entry/getGrade':
        return <String, Object?>{'cancelledDescription': ''};
      case 'api/student/dashboard/dashboard':
        return _buildDashboardResponse();
      case 'api/student/dashboard/save_reminder':
        return _saveReminder(args);
      case 'api/student/dashboard/delete_reminder':
        return _deleteReminder(args);
      case 'api/student/dashboard/toggle_reminder':
        return _toggleReminder(args);
      case 'api/student/dashboard/absences':
        return _buildAbsencesResponse();
      case 'api/student/dashboard/absence_future':
        return _addFutureAbsence(args);
      case 'api/student/dashboard/remove_absence_future':
        return _removeFutureAbsence(args);
      case 'api/student/dashboard/absence_reason':
        return _justifyAbsence(args);
      case 'api/calendar/student':
        return _buildCalendarResponse(args);
      case 'api/profile/get':
        return Map<String, Object?>.from(_profileState);
      case 'api/profile/updateNotificationSettings':
        return _updateNotificationSettings(args);
      case 'api/profile/updateProfile':
        return _updateProfile(args);
      case 'api/profile/updateCodiceFiscale':
        return _updateCodiceFiscale(args);
      case 'api/notification/unread':
        return _buildUnreadNotifications();
      case 'api/notification/markAsRead':
        return _markNotificationAsRead(args);
      case 'api/message/getMyMessages':
        return _buildMessages();
      case 'api/message/markAsRead':
        return _markMessageAsRead(args);
      case 'student/certificate':
        return _buildCertificateHtml();
      default:
        return null;
    }
  }

  dynamic handleUpload(
    String url, {
    required List<int> bytes,
    required String contentType,
    required String fileName,
  }) {
    switch (url) {
      case 'api/profile/uploadProfilePicture':
        _profileState['picture'] =
            'demo-upload-${DateTime.now().millisecondsSinceEpoch}-$fileName';
        _persistSync();
        return <String, Object?>{
          'error': null,
          'message': 'OK',
          'name': _profileState['picture'],
        };
      default:
        return <String, Object?>{'error': null};
    }
  }

  Map<String, dynamic> _initialState() {
    return <String, dynamic>{
      'nextReminderId': 10000,
      'nextFutureAbsenceId': 20000,
      'profile': <String, dynamic>{
        'name': 'Demo',
        'email': 'demo@local.invalid',
        'username': 'demo',
        'roleName': 'Schüler/in',
        'notificationsEnabled': true,
        'codiceFiscale': null,
        'picture': null,
        'language': 'de',
      },
      'reminders': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9001,
          'date': _dateOnly(_today().add(const Duration(days: 1))),
          'subtitle': 'Turnbeutel einpacken',
          'label': 'Bewegung und Sport',
          'checked': false,
        },
      ],
      'absenceGroups': _buildInitialAbsenceGroups(),
      'futureAbsences': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 9101,
          'studentId': 1,
          'note': 'doctorAppointment',
          'startDate': _dateOnly(_today().add(const Duration(days: 8))),
          'endDate': _dateOnly(_today().add(const Duration(days: 8))),
          'startTime': 2,
          'endTime': 4,
          'justified': 1,
          'reason': null,
          'reason_signature': 'Demo',
          'reason_timestamp': null,
          'reason_user': 1,
        },
      ],
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 3001,
          'kind': 'welcome',
          'timeSent': _isoDateTime(_today().subtract(const Duration(days: 1))),
          'timeRead': null,
          'submissions': <Map<String, dynamic>>[],
        },
        <String, dynamic>{
          'id': 3002,
          'kind': 'trip',
          'timeSent': _isoDateTime(_today().subtract(const Duration(days: 3))),
          'timeRead': null,
          'submissions': <Map<String, dynamic>>[],
        },
      ],
      'generalNotifications': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 4001,
          'kind': 'localMode',
          'type': 'generic',
          'objectId': null,
          'timeSent': _isoDateTime(_today()),
          'read': false,
        },
      ],
    };
  }

  Map<String, dynamic> _mergeState(
    Map<String, dynamic> defaults,
    Map<String, dynamic> persisted,
  ) {
    final merged = Map<String, dynamic>.from(defaults);
    for (final entry in persisted.entries) {
      if (entry.value is Map && merged[entry.key] is Map) {
        merged[entry.key] = <String, dynamic>{
          ...Map<String, dynamic>.from(merged[entry.key] as Map),
          ...Map<String, dynamic>.from(entry.value as Map),
        };
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  Map<String, dynamic> get _profileState =>
      _state['profile'] as Map<String, dynamic>;

  String get _demoLanguage {
    final language = (_profileState['language'] as String?)?.trim().toLowerCase();
    return switch (language) {
      'en' => 'en',
      'it' => 'it',
      'lld' => 'lld',
      _ => 'de',
    };
  }

  List<Map<String, dynamic>> get _reminders =>
      (_state['reminders'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _absenceGroups =>
      (_state['absenceGroups'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _futureAbsences =>
      (_state['futureAbsences'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _messages =>
      (_state['messages'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _generalNotifications =>
      (_state['generalNotifications'] as List).cast<Map<String, dynamic>>();

  String _text(String key) {
    final values = _demoTranslations[key];
    if (values == null) {
      return key;
    }
    return values[_demoLanguage] ?? values['de'] ?? key;
  }

  String _localizeDashboardTitle(String value) {
    return switch (value) {
      'Test' => _text('dashboardTitleTest'),
      'Hausaufgabe' => _text('dashboardTitleHomework'),
      'Schularbeit' => _text('dashboardTitleSchoolwork'),
      'Prüfung' => _text('dashboardTitleExam'),
      'Projektabgabe' => _text('dashboardTitleProjectSubmission'),
      'Ferien' => _text('dashboardTitleHoliday'),
      _ => value,
    };
  }

  String _localizeFreeText(String value) {
    return switch (value) {
      'Turnbeutel einpacken' => _text('reminderSportsBag'),
      'historyHomework' => _text('historyHomework'),
      'springBreak' => _text('springBreak'),
      '' => '',
      _ => value,
    };
  }

  Map<String, Object?> _localizedAbsenceGroup(Map<String, dynamic> group) {
    return <String, Object?>{
      ...Map<String, Object?>.from(group),
      'reason': _localizeAbsenceText(group['reason'] as String?),
      'note': _localizeAbsenceText(group['note'] as String?),
      'group': (group['group'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (entry) => <String, Object?>{
              ...Map<String, Object?>.from(entry),
              'reason': _localizeAbsenceText(entry['reason'] as String?),
              'note': _localizeAbsenceText(entry['note'] as String?),
            },
          )
          .toList(),
    };
  }

  Map<String, Object?> _localizedFutureAbsence(Map<String, dynamic> absence) {
    return <String, Object?>{
      ...Map<String, Object?>.from(absence),
      'note': _localizeAbsenceText(absence['note'] as String?),
      'reason': _localizeAbsenceText(absence['reason'] as String?),
    };
  }

  String? _localizeAbsenceText(String? value) {
    if (value == null || value.isEmpty) {
      return value;
    }
    return switch (value) {
      'doctorAppointment' => _text('doctorAppointment'),
      'delay' => _text('delay'),
      _ => value,
    };
  }

  String _messageSubject(Map<String, dynamic> message) {
    return switch (message['kind']) {
      'welcome' => _text('messageWelcomeSubject'),
      'trip' => _text('messageTripSubject'),
      _ => _text('messageFallbackSubject'),
    };
  }

  String _messageSender(Map<String, dynamic> message) {
    return switch (message['kind']) {
      'trip' => _text('messageSenderClassBoard'),
      _ => _text('messageSenderOffice'),
    };
  }

  String _messageBody(Map<String, dynamic> message) {
    final lines = switch (message['kind']) {
      'welcome' => <String>[
          _text('messageWelcomeLine1'),
          _text('messageWelcomeLine2'),
        ],
      'trip' => <String>[
          _text('messageTripLine1'),
          _text('messageTripLine2'),
          _text('messageTripLine3'),
        ],
      _ => <String>[_text('messageFallbackLine')],
    };
    return json.encode(
      <String, Object?>{
        'ops': <Map<String, Object?>>[
          for (final line in lines) <String, Object?>{'insert': '$line\n'}
        ],
      },
    );
  }

  String _certificateRow(String label, String value) {
    return '''
<tr>
  <td>$label</td>
  <td>$value</td>
</tr>
''';
  }

  Map<String, Object?> _buildAllSubjectsResponse() {
    return <String, Object?>{
      'subjects': _demoSubjects.map((subject) {
        return <String, Object?>{
          'subject': <String, Object?>{
            'id': subject.id,
            'name': subject.name,
          },
          'grades': subject.gradesForSemester(
            _currentSemester,
            language: _demoLanguage,
          ),
        };
      }).toList(),
    };
  }

  Map<String, Object?> _buildSubjectDetailResponse(Map<String, Object?> args) {
    final subjectId = args['subjectId'] as int?;
    final subject = _demoSubjects.firstWhere(
      (entry) => entry.id == subjectId,
      orElse: () => _demoSubjects.first,
    );
    return <String, Object?>{
      'grades': subject.detailsForSemester(
        _currentSemester,
        language: _demoLanguage,
      ),
      'absences': <Object>[],
      'observations': subject.observationsForSemester(
        _currentSemester,
        language: _demoLanguage,
      ),
      'averageSemester': 0,
      'averageYear': 0,
      'showGrades': 2,
      'showGradesStudentView': 2,
      'isClassHasNoGrades': false,
      'countCompetences': 0,
      'countDescriptions': 0,
      'countObservations': subject
          .observationsForSemester(_currentSemester, language: _demoLanguage)
          .length,
    };
  }

  List<Map<String, Object?>> _buildDashboardResponse() {
    final today = _today();
    final start = today.subtract(const Duration(days: 3));
    final generated = <String, List<Map<String, Object?>>>{};

    for (var offset = 0; offset < 18; offset++) {
      final date = start.add(Duration(days: offset));
      generated[_dateOnly(date)] = _dashboardItemsForDate(date);
    }

    for (final reminder in _reminders) {
      generated
          .putIfAbsent(reminder['date'] as String, () => <Map<String, Object?>>[])
          .add(_dashboardReminderToResponse(reminder));
    }

    final keys = generated.keys.toList()..sort();
    return keys
        .map(
          (date) => <String, Object?>{
            'date': date,
            'items': generated[date]!..sort(_sortDashboardItems),
          },
        )
        .toList();
  }

  int _sortDashboardItems(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final aDeadline = a['deadline'] as String?;
    final bDeadline = b['deadline'] as String?;
    if (aDeadline == null && bDeadline == null) {
      return (a['id'] as int?)!.compareTo((b['id'] as int?)!);
    }
    if (aDeadline == null) {
      return 1;
    }
    if (bDeadline == null) {
      return -1;
    }
    return aDeadline.compareTo(bDeadline);
  }

  Map<String, Object?> _saveReminder(Map<String, Object?> args) {
    final date = (args['date'] as String?) ?? _dateOnly(_today());
    final text = (args['text'] as String?)?.trim() ?? '';
    final reminder = <String, dynamic>{
      'id': _state['nextReminderId'] as int,
      'date': date,
      'title': 'Erinnerung',
      'subtitle': text,
      'label': _guessReminderSubject(text),
      'checked': false,
    };
    _state['nextReminderId'] = (_state['nextReminderId'] as int) + 1;
    _reminders.add(reminder);
    _persistSync();
    return _dashboardReminderToResponse(reminder);
  }

  Map<String, Object?> _deleteReminder(Map<String, Object?> args) {
    final id = args['id'] as int?;
    _reminders.removeWhere((reminder) => reminder['id'] == id);
    _persistSync();
    return <String, Object?>{'success': true};
  }

  Map<String, Object?> _toggleReminder(Map<String, Object?> args) {
    final id = args['id'] as int?;
    final value = args['value'] == true;
    for (final reminder in _reminders) {
      if (reminder['id'] == id) {
        reminder['checked'] = value;
        _persistSync();
        return <String, Object?>{'success': true};
      }
    }
    return <String, Object?>{'success': false};
  }

  Map<String, Object?> _buildAbsencesResponse() {
    final statistics = _calculateAbsenceStatistics();
    return <String, Object?>{
      'statistics': statistics,
      'canEdit': true,
      'absences': _absenceGroups.map(_localizedAbsenceGroup).toList(),
      'futureAbsences': _futureAbsences.map(_localizedFutureAbsence).toList(),
    };
  }

  Map<String, Object?> _addFutureAbsence(Map<String, Object?> args) {
    final entry = <String, dynamic>{
      'id': _state['nextFutureAbsenceId'] as int,
      'studentId': 1,
      'note': (args['reason'] as String?)?.trim(),
      'startDate': (args['startDate'] as String?) ?? _dateOnly(_today()),
      'endDate': (args['endDate'] as String?) ?? _dateOnly(_today()),
      'startTime': args['startTime'] as int? ?? 1,
      'endTime': args['endTime'] as int? ?? 20,
      'justified': 1,
      'reason': null,
      'reason_signature': (args['reason_signature'] as String?)?.trim(),
      'reason_timestamp': null,
      'reason_user': 1,
    };
    _state['nextFutureAbsenceId'] = (_state['nextFutureAbsenceId'] as int) + 1;
    _futureAbsences.add(entry);
    _persistSync();
    return <String, Object?>{
      'success': true,
        'message': _text('absenceSaved'),
      };
  }

  Map<String, Object?> _removeFutureAbsence(Map<String, Object?> args) {
    final futureAbsence = args['futureAbsence'];
    final id = futureAbsence is Map ? futureAbsence['id'] as int? : null;
    _futureAbsences.removeWhere((absence) => absence['id'] == id);
    _persistSync();
    return <String, Object?>{'success': true};
  }

  Map<String, Object?> _justifyAbsence(Map<String, Object?> args) {
    final absenceGroup = args['absenceGroup'];
    if (absenceGroup is! Map) {
      return <String, Object?>{'success': false};
    }
    final groupItems =
        (absenceGroup['group'] as List?)?.cast<Map<dynamic, dynamic>>() ??
            const <Map<dynamic, dynamic>>[];
    final reason = absenceGroup['reason'] as String?;
    final signature = absenceGroup['reason_signature'] as String?;
    for (final group in _absenceGroups) {
      final entries = (group['group'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((entry) => entry['id']).toSet();
      final incomingIds = groupItems.map((entry) => entry['id']).toSet();
      if (ids.length == incomingIds.length && ids.containsAll(incomingIds)) {
        group['justified'] = 2;
        group['reason'] = reason;
        group['reason_signature'] = signature;
        group['reason_timestamp'] = _timestamp(_today());
        for (final entry in entries) {
          entry['justified'] = 2;
          entry['reason'] = reason;
          entry['reason_signature'] = signature;
          entry['reason_timestamp'] = _timestamp(_today());
        }
      }
    }
    _persistSync();
    return <String, Object?>{'success': true};
  }

  Map<String, Map<String, Object?>> _buildCalendarResponse(
    Map<String, Object?> args,
  ) {
    final startDate = DateTime.parse(
      (args['startDate'] as String?) ?? _dateOnly(_today()),
    );
    final monday = startDate.subtract(Duration(days: startDate.weekday - 1));
    final result = <String, Map<String, Object?>>{};

    for (var offset = 0; offset < 5; offset++) {
      final date = monday.add(Duration(days: offset));
      final hours = _calendarTemplateForWeekday(date.weekday);
      final entries = <String, Object?>{};
      for (final lesson in hours) {
        entries['${lesson.period}'] = <String, Object?>{
          'isLesson': 1,
          'hour': lesson.period,
          'linkedHoursCount': 0,
          'lesson': _buildCalendarLesson(date, lesson),
        };
      }
      result[_dateOnly(date)] = <String, Object?>{
        '1': <String, Object?>{
          '1': entries,
        },
      };
    }

    return result;
  }

  Map<String, Object?> _updateNotificationSettings(Map<String, Object?> args) {
    _profileState['notificationsEnabled'] = args['notificationsEnabled'] == true;
    _persistSync();
    return <String, Object?>{'error': null, 'message': 'OK'};
  }

  Map<String, Object?> _updateProfile(Map<String, Object?> args) {
    final email = (args['email'] as String?)?.trim();
    final language = (args['language'] as String?)?.trim();
    if (email != null && email.isNotEmpty) {
      _profileState['email'] = email;
    }
    if (language != null && language.isNotEmpty) {
      _profileState['language'] = language;
    }
    _persistSync();
    return <String, Object?>{
      'error': null,
      'message': 'Profil aktualisiert',
    };
  }

  Map<String, Object?> _updateCodiceFiscale(Map<String, Object?> args) {
    final value = (args['codiceFiscale'] as String?)?.trim();
    if (value != null && value.isNotEmpty) {
      _profileState['codiceFiscale'] = value;
      _persistSync();
    }
    return <String, Object?>{
      'error': null,
      'message': 'Steuernummer gespeichert',
    };
  }

  List<Map<String, Object?>> _buildUnreadNotifications() {
    final notifications = <Map<String, Object?>>[];
    for (final notification in _generalNotifications) {
      if (notification['read'] == true) {
        continue;
      }
      notifications.add(
        <String, Object?>{
          'id': notification['id'] as int,
          'title': switch (notification['kind']) {
            'localMode' => _text('notificationLocalModeTitle'),
            _ => _text('messageFallbackSubject'),
          },
          'type': notification['type'] as String,
          'objectId': notification['objectId'] as int?,
          'subTitle': switch (notification['kind']) {
            'localMode' => _text('notificationLocalModeSubtitle'),
            _ => '',
          },
          'timeSent': notification['timeSent'] as String,
        },
      );
    }
    for (final message in _messages) {
      if (message['timeRead'] != null) {
        continue;
      }
      notifications.add(
        <String, Object?>{
          'id': 5000 + (message['id'] as int),
          'title': _messageSubject(message),
          'type': 'message',
          'objectId': message['id'] as int,
          'subTitle': _messageSender(message),
          'timeSent': message['timeSent'] as String,
        },
      );
    }
    notifications.sort(
      (a, b) =>
          (b['timeSent'] as String?)!.compareTo((a['timeSent'] as String?)!),
    );
    return notifications;
  }

  Map<String, Object?> _markNotificationAsRead(Map<String, Object?> args) {
    final id = args['id'] as int?;
    if (id == null) {
      for (final notification in _generalNotifications) {
        notification['read'] = true;
      }
      for (final message in _messages) {
        message['timeRead'] ??= _isoDateTime(_today());
      }
    } else {
      for (final notification in _generalNotifications) {
        if (notification['id'] == id) {
          notification['read'] = true;
        }
      }
    }
    _persistSync();
    return <String, Object?>{'success': true};
  }

  List<Map<String, Object?>> _buildMessages() {
    return _messages
        .map(
          (message) => <String, Object?>{
            'id': message['id'] as int,
            'subject': _messageSubject(message),
            'text': _messageBody(message),
            'recipientString': 'demo',
            'fromName': _messageSender(message),
            'timeSent': message['timeSent'] as String,
            'timeRead': message['timeRead'] as String?,
            'submissions': (message['submissions'] as List)
                .cast<Map<String, dynamic>>()
                .map((entry) => Map<String, Object?>.from(entry))
                .toList(),
          },
        )
        .toList()
      ..sort(
        (a, b) =>
            (b['timeSent'] as String?)!.compareTo((a['timeSent'] as String?)!),
      );
  }

  Map<String, Object?> _markMessageAsRead(Map<String, Object?> args) {
    final id = args['messageId'] as int?;
    for (final message in _messages) {
      if (message['id'] == id) {
        message['timeRead'] = _isoDateTime(_today());
      }
    }
    _persistSync();
    return <String, Object?>{'success': true};
  }

  String _buildCertificateHtml() {
    final summaryRows = <String>[
      _certificateRow(_text('certificateAverage'), '8.72'),
      _certificateRow(_text('certificateAbsences'), '2'),
      _certificateRow(_text('certificateBehavior'), _text('certificatePositive')),
    ].join();
    final gradeRows = _demoSubjects.take(6).map((subject) {
      final grades = subject.gradesForSemester(
        2,
        language: _demoLanguage,
      );
      final lastGrade =
          grades.isEmpty ? '-' : (grades.last['grade'] as String?)!;
      return '''
<tr>
  <td>${subject.name}</td>
  <td>$lastGrade</td>
</tr>
''';
    }).join();
    return '''
<div class="student-subject-list">
  <div class="default-page-container">
    <h2 class="h2 margin-top">${_text('certificateHeading')}</h2>
    <p>${_text('certificateBody')}</p>
    <p>${_text('certificateDateLabel')}: ${DateFormat('dd.MM.yyyy').format(_today())}</p>
    <h3>${_text('certificateSummary')}</h3>
    <table>
      <tbody>
        $summaryRows
      </tbody>
    </table>
    <h3>${_text('certificateGrades')}</h3>
    <table>
      <thead>
        <tr>
          <th>${_text('certificateSubject')}</th>
          <th>${_text('certificateGrade')}</th>
        </tr>
      </thead>
      <tbody>
        $gradeRows
      </tbody>
    </table>
  </div>
</div>
''';
  }

  List<Map<String, dynamic>> _buildInitialAbsenceGroups() {
    final twoWeeksAgo = _today().subtract(const Duration(days: 14));
    final oneWeekAgo = _today().subtract(const Duration(days: 7));
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'date': '${_dateOnly(oneWeekAgo)} 00:00:00',
        'justified': 1,
        'reason_signature': null,
        'reason_timestamp': null,
        'reason_user': 1,
        'reason': null,
        'note': 'delay',
        'selfdecl_id': null,
        'selfdecl_input': null,
        'group': <Map<String, dynamic>>[
          _absenceEntry(
            id: 7001,
            date: oneWeekAgo,
            hour: 1,
            minutes: 15,
            justified: 1,
          ),
        ],
      },
      <String, dynamic>{
        'date': '${_dateOnly(twoWeeksAgo)} 00:00:00',
        'justified': 2,
        'reason_signature': 'Demo',
        'reason_timestamp': _timestamp(twoWeeksAgo),
        'reason_user': 1,
        'reason': 'doctorAppointment',
        'note': null,
        'selfdecl_id': null,
        'selfdecl_input': null,
        'group': <Map<String, dynamic>>[
          _absenceEntry(
            id: 7002,
            date: twoWeeksAgo,
            hour: 3,
            minutes: 50,
            justified: 2,
            reason: 'doctorAppointment',
            signature: 'Demo',
          ),
          _absenceEntry(
            id: 7003,
            date: twoWeeksAgo,
            hour: 4,
            minutes: 50,
            justified: 2,
            reason: 'doctorAppointment',
            signature: 'Demo',
          ),
        ],
      },
    ];
  }

  Map<String, dynamic> _absenceEntry({
    required int id,
    required DateTime date,
    required int hour,
    required int minutes,
    required int justified,
    String? reason,
    String? signature,
  }) {
    return <String, dynamic>{
      'id': id,
      'minutes': minutes,
      'date': '${_dateOnly(date)} 00:00:00',
      'hour': hour,
      'minutes_begin': minutes == 50 ? 0 : minutes,
      'minutes_end': 0,
      'justified': justified,
      'note': null,
      'reason': reason,
      'reason_signature': signature,
      'reason_timestamp': reason == null ? null : _timestamp(date),
      'reason_user': 1,
      'selfdecl_id': null,
      'selfdecl_input': null,
    };
  }

  Map<String, Object?> _calculateAbsenceStatistics() {
    var counter = 0;
    var delayed = 0;
    var justified = 0;
    var notJustified = 0;
    for (final group in _absenceGroups) {
      final groupEntries = (group['group'] as List).cast<Map<String, dynamic>>();
      for (final entry in groupEntries) {
        counter++;
        final status = entry['justified'] as int? ?? 1;
        if ((entry['minutes'] as int? ?? 0) < 50) {
          delayed++;
        }
        if (status == 2) {
          justified++;
        } else {
          notJustified++;
        }
      }
    }
    return <String, Object?>{
      'counter': counter,
      'counterForSchool': 0,
      'delayed': delayed,
      'justified': justified,
      'notJustified': notJustified,
      'percentage': '3.4',
    };
  }

  Map<String, Object?> _dashboardReminderToResponse(
    Map<String, dynamic> reminder,
  ) {
    final date = DateTime.parse(reminder['date'] as String);
    return <String, Object?>{
      'id': reminder['id'] as int,
      'category': reminder['id'] as int,
      'type': 'homework',
      'title': _text('reminderTitle'),
      'subtitle': _localizeFreeText(reminder['subtitle'] as String),
      'label': reminder['label'] as String?,
      'warning': false,
      'checkable': true,
      'checked': reminder['checked'] == true,
      'deleteable': true,
      'online': 0,
      'submission': null,
      'deadline': '${reminder['date']} 07:45:00',
      'deadlineFormatted': _deadlineFormatted(date, 7, 45),
      'deadlineStart': null,
      'deadlineStartFormatted': 'Donnerstag, 01.01.1970, 01:00',
      'submissionAllowed': 0,
      'submissionResigned': false,
      'submissionIsNowInOvertime': false,
      'homework': 1,
      'done': reminder['checked'] == true ? 1 : null,
      'gradeGroupSubmissions': null,
    };
  }

  String? _guessReminderSubject(String text) {
    for (final subject in _demoSubjects.map((entry) => entry.name)) {
      if (text.toLowerCase().contains(subject.toLowerCase())) {
        return subject;
      }
    }
    return null;
  }

  List<Map<String, Object?>> _dashboardItemsForDate(DateTime date) {
    final items = <Map<String, Object?>>[];
    final weekday = date.weekday;
    final diff = date.difference(_today()).inDays;

    if (weekday == DateTime.monday) {
      items.add(
        _dashboardItem(
          id: 100 + diff,
          date: date,
          hour: 1,
          title: 'Test',
          subtitle: '',
          label: 'Englisch',
          type: 'gradeGroup',
        ),
      );
    }
    if (weekday == DateTime.tuesday) {
      items.add(
        _dashboardItem(
          id: 200 + diff,
          date: date,
          hour: 3,
          title: 'Hausaufgabe',
          subtitle: 'historyHomework',
          label: 'Geschichte',
          type: 'lessonHomework',
          homework: 1,
          checkable: true,
        ),
      );
    }
    if (weekday == DateTime.wednesday) {
      items.add(
        _dashboardItem(
          id: 300 + diff,
          date: date,
          hour: 5,
          title: 'Schularbeit',
          subtitle: '',
          label: 'Deutsch',
          type: 'gradeGroup',
        ),
      );
    }
    if (weekday == DateTime.thursday) {
      items.add(
        _dashboardItem(
          id: 400 + diff,
          date: date,
          hour: 2,
          title: 'Prüfung',
          subtitle: '',
          label: 'Mathematik',
          type: 'gradeGroup',
        ),
      );
    }
    if (weekday == DateTime.friday) {
      items.add(
        _dashboardItem(
          id: 500 + diff,
          date: date,
          hour: 5,
          title: 'Projektabgabe',
          subtitle: '',
          label: 'Projektmanagement',
          type: 'homework',
          homework: 1,
        ),
      );
    }

    if (diff == 0) {
      items.add(
        _dashboardItem(
          id: 6000,
          date: date,
          hour: 7,
          title: 'Ferien',
          subtitle: 'springBreak',
          label: null,
          type: 'observation',
          homework: 1,
        ),
      );
    }

    return items;
  }

  Map<String, Object?> _dashboardItem({
    required int id,
    required DateTime date,
    required int hour,
    required String title,
    required String subtitle,
    required String? label,
    required String type,
    int homework = 0,
    bool checkable = false,
  }) {
    final time = _lessonTime(hour);
    return <String, Object?>{
      'id': id,
      'category': id,
      'type': type,
      'title': _localizeDashboardTitle(title),
      'subtitle': _localizeFreeText(subtitle),
      'label': label,
      'warning': homework == 0,
      'checkable': checkable,
      'checked': false,
      'deleteable': false,
      'online': 0,
      'submission': null,
      'deadline': '${_dateOnly(date)} ${time.value}',
      'deadlineFormatted': _deadlineFormatted(
        date,
        time.hour,
        time.minute,
      ),
      'deadlineStart': null,
      'deadlineStartFormatted': 'Donnerstag, 01.01.1970, 01:00',
      'submissionAllowed': 0,
      'submissionResigned': false,
      'submissionIsNowInOvertime': false,
      'homework': homework,
      'done': null,
      'gradeGroupSubmissions': null,
    };
  }

  _DeadlineTime _lessonTime(int hour) {
    const starts = <int, String>{
      1: '07:50:00',
      2: '08:40:00',
      3: '09:35:00',
      4: '10:25:00',
      5: '11:30:00',
      6: '12:20:00',
      7: '14:10:00',
      8: '15:00:00',
      9: '15:50:00',
    };
    final value = starts[hour] ?? '07:50:00';
    final parts = value.split(':');
    return _DeadlineTime(
      value,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  String _deadlineFormatted(DateTime date, int hour, int minute) {
    const weekdays = <int, String>{
      DateTime.monday: 'Montag',
      DateTime.tuesday: 'Dienstag',
      DateTime.wednesday: 'Mittwoch',
      DateTime.thursday: 'Donnerstag',
      DateTime.friday: 'Freitag',
      DateTime.saturday: 'Samstag',
      DateTime.sunday: 'Sonntag',
    };
    final weekday = weekdays[date.weekday] ?? 'Montag';
    return '$weekday, ${DateFormat('dd.MM.yyyy').format(date)}, '
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  List<_CalendarLessonTemplate> _calendarTemplateForWeekday(int weekday) {
    return switch (weekday) {
      DateTime.monday => const <_CalendarLessonTemplate>[
          _CalendarLessonTemplate(1, 'Systeme und Netze'),
          _CalendarLessonTemplate(3, 'Deutsch'),
          _CalendarLessonTemplate(4, 'Mathematik'),
          _CalendarLessonTemplate(5, 'Projektmanagement'),
          _CalendarLessonTemplate(7, 'Italienisch'),
          _CalendarLessonTemplate(8, 'Bewegung und Sport'),
          _CalendarLessonTemplate(9, 'Englisch'),
        ],
      DateTime.tuesday => const <_CalendarLessonTemplate>[
          _CalendarLessonTemplate(1, 'Geschichte'),
          _CalendarLessonTemplate(2, 'Informatik'),
          _CalendarLessonTemplate(4, 'Englisch'),
          _CalendarLessonTemplate(5, 'Systeme und Netze'),
        ],
      DateTime.wednesday => const <_CalendarLessonTemplate>[
          _CalendarLessonTemplate(1, 'Bewegung und Sport'),
          _CalendarLessonTemplate(2, 'Deutsch'),
          _CalendarLessonTemplate(3, 'Technologie und Planung'),
          _CalendarLessonTemplate(5, 'Italienisch'),
          _CalendarLessonTemplate(7, 'Informatik'),
        ],
      DateTime.thursday => const <_CalendarLessonTemplate>[
          _CalendarLessonTemplate(1, 'Englisch'),
          _CalendarLessonTemplate(2, 'Mathematik'),
          _CalendarLessonTemplate(3, 'Religion'),
          _CalendarLessonTemplate(4, 'Deutsch'),
          _CalendarLessonTemplate(5, 'Geschichte'),
          _CalendarLessonTemplate(6, 'Informatik'),
        ],
      DateTime.friday => const <_CalendarLessonTemplate>[
          _CalendarLessonTemplate(1, 'Projektmanagement'),
          _CalendarLessonTemplate(2, 'Mathematik'),
          _CalendarLessonTemplate(3, 'Informatik'),
          _CalendarLessonTemplate(4, 'Informatik'),
          _CalendarLessonTemplate(5, 'Technologie und Planung'),
        ],
      _ => const <_CalendarLessonTemplate>[],
    };
  }

  Map<String, Object?> _buildCalendarLesson(
    DateTime date,
    _CalendarLessonTemplate lesson,
  ) {
    final time = _timeObjectsForPeriod(lesson.period);
    final subject = _demoSubjects.firstWhere(
      (entry) => entry.name == lesson.subject,
      orElse: () => _demoSubjects.first,
    );
    return <String, Object?>{
      'id': 80000 + (date.weekday * 100) + lesson.period,
      'date': _dateOnly(date),
      'hour': lesson.period,
      'toHour': lesson.period,
      'timeStart': time.startTs,
      'timeEnd': time.endTs,
      'timeToEnd': time.endTs,
      'timeStartObject': time.start,
      'timeEndObject': time.end,
      'timeToEndObject': time.end,
      'timeShowEnabled': true,
      'classId': 1,
      'className': 'Demo',
      'classComment': '',
      'description': '',
      'note': '',
      'lessonShow': true,
      'teachers': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'firstName': _text('teacherPlaceholderFirst'),
          'lastName': _text('teacherPlaceholderLast'),
        },
      ],
      'teachersToNotify': <Object>[],
      'teacherMyself': null,
      'isAutoNotify': false,
      'isLessonTypeNotifyOn': false,
      'exp_lt_default': false,
      'isSecretary': false,
      'subject': <String, Object?>{
        'id': subject.id,
        'name': subject.name,
        'lernfeld': 0,
        'defaultLessonContent': '',
        'defaultLessonContentType': 0,
      },
      'homeworkExams': <Object>[],
      'lessonContents': <Object>[],
      'rooms': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'name': _text('roomPlaceholder'),
        },
      ],
      'readOnly': true,
      'isSubstitute': 0,
      'linkToPreviousHour': 0,
      'linkedHours': <Object>[],
      'criticalObservations': <Object>[],
      'missingStudents': <Object>[],
      'students': <Object>[],
      'grades': <Object>[],
      'observations': <Object>[],
      'absenceOpenAbsencesStudents': <Object>[],
    };
  }

  _TimeObjects _timeObjectsForPeriod(int period) {
    const values = <int, (int, int, int, int)>{
      1: (7, 50, 8, 40),
      2: (8, 40, 9, 30),
      3: (9, 35, 10, 25),
      4: (10, 25, 11, 15),
      5: (11, 30, 12, 20),
      6: (12, 20, 13, 10),
      7: (14, 10, 15, 0),
      8: (15, 0, 15, 50),
      9: (15, 50, 16, 40),
    };
    final tuple = values[period] ?? values[1]!;
    Map<String, Object?> build(int hour, int minute) {
      final hourText = hour.toString().padLeft(2, '0');
      final minuteText = minute.toString().padLeft(2, '0');
      final ts = (hour * 3600) + (minute * 60);
      return <String, Object?>{
        'h': hourText,
        'm': minuteText,
        'ts': ts,
        'text': '$hourText:$minuteText',
        'html': '$hourText<sup>$minuteText</sup>',
      };
    }

    return _TimeObjects(
      start: build(tuple.$1, tuple.$2),
      end: build(tuple.$3, tuple.$4),
      startTs: (tuple.$1 * 3600) + (tuple.$2 * 60),
      endTs: (tuple.$3 * 3600) + (tuple.$4 * 60),
    );
  }

  Future<void> _persist() async {
    final file = await _storageFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(_state));
  }

  void _persistSync() {
    final path = _storagePath;
    if (path == null) {
      return;
    }
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(json.encode(_state));
  }

  Future<File> _storageFile() async {
    if (_storagePath != null) {
      return File(_storagePath!);
    }
    final dir = await getApplicationSupportDirectory();
    _storagePath = '${dir.path}/$_storageFileName';
    return File(_storagePath!);
  }
}

class _TimeObjects {
  const _TimeObjects({
    required this.start,
    required this.end,
    required this.startTs,
    required this.endTs,
  });

  final Map<String, Object?> start;
  final Map<String, Object?> end;
  final int startTs;
  final int endTs;
}

class _DeadlineTime {
  const _DeadlineTime(this.value, this.hour, this.minute);

  final String value;
  final int hour;
  final int minute;
}

class _CalendarLessonTemplate {
  const _CalendarLessonTemplate(this.period, this.subject);

  final int period;
  final String subject;
}

class _DemoSubject {
  const _DemoSubject({
    required this.id,
    required this.name,
    required this.firstSemester,
    required this.secondSemester,
  });

  final int id;
  final String name;
  final List<_DemoGrade> firstSemester;
  final List<_DemoGrade> secondSemester;

  List<Map<String, Object?>> gradesForSemester(
    int semester, {
    required String language,
  }) {
    return _semesterGrades(semester)
        .map((grade) => grade.toBasicGrade(language: language))
        .toList();
  }

  List<Map<String, Object?>> detailsForSemester(
    int semester, {
    required String language,
  }) {
    return _semesterGrades(semester)
        .map((grade) => grade.toDetailGrade(id, language: language))
        .toList();
  }

  List<Map<String, Object?>> observationsForSemester(
    int semester, {
    required String language,
  }) {
    final grades = _semesterGrades(semester);
    if (grades.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final firstDate = grades.first.date;
    return <Map<String, Object?>>[
      <String, Object?>{
        'id': 60000 + id,
        'note': '',
        'date': _dateOnly(firstDate),
        'typeId': 19,
        'typeName': _demoGradeTypeText('Plus', language),
        'cancelled': 0,
        'created': _demoCreatedText(language, firstDate),
        'subjectId': id,
        'classId': 1,
        'studentId': 1,
        'hidden': 0,
      },
    ];
  }

  List<_DemoGrade> _semesterGrades(int semester) {
    return semester == 2 ? secondSemester : firstSemester;
  }
}

class _DemoGrade {
  const _DemoGrade({
    required this.id,
    required this.date,
    required this.grade,
    required this.weight,
    required this.type,
    required this.name,
  });

  final int id;
  final DateTime date;
  final String grade;
  final int weight;
  final String type;
  final String name;

  Map<String, Object?> toBasicGrade({required String language}) {
    return <String, Object?>{
      'grade': grade,
      'weight': weight,
      'date': _dateOnly(date),
      'cancelled': 0,
      'type': _demoGradeTypeText(type, language),
    };
  }

  Map<String, Object?> toDetailGrade(
    int subjectId, {
    required String language,
  }) {
    return <String, Object?>{
      'id': id,
      'grade': grade,
      'weight': weight,
      'typeId': 7,
      'typeName': _demoGradeTypeText(type, language),
      'name': _demoGradeNameText(name, language),
      'description': '',
      'date': _dateOnly(date),
      'cancelled': false,
      'created': _demoCreatedText(language, date),
      'subjectId': subjectId,
      'classId': 1,
      'studentId': 1,
      'createdTimeStamp': _timestamp(date),
      'cancelledTimeStamp': null,
      'competences': <Object>[],
    };
  }
}

DateTime _today() => DateTime(now.year, now.month, now.day);

String _dateOnly(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String _timestamp(DateTime date) =>
    '${DateFormat('yyyy-MM-dd').format(date)} 08:00:00';

String _isoDateTime(DateTime date) =>
    DateTime(date.year, date.month, date.day, 8).toIso8601String();

String _demoCreatedText(String language, DateTime date) {
  final dateText = DateFormat('dd.MM.yyyy').format(date);
  return switch (language) {
    'en' => 'Entered by Teacher Placeholder on $dateText',
    'it' => 'Inserito da Docente segnaposto il $dateText',
    'lld' => 'Inserì da insignante placeholder ai $dateText',
    _ => 'Von Lehrperson Platzhalter am $dateText eingetragen',
  };
}

String _demoGradeTypeText(String value, String language) {
  const translations = <String, Map<String, String>>{
    'Schularbeit': {
      'de': 'Schularbeit',
      'en': 'Schoolwork',
      'it': 'Compito in classe',
      'lld': 'Compit de classa',
    },
    'Mitarbeit': {
      'de': 'Mitarbeit',
      'en': 'Participation',
      'it': 'Partecipazione',
      'lld': 'Colaboraziun',
    },
    'Prüfung': {
      'de': 'Prüfung',
      'en': 'Exam',
      'it': 'Esame',
      'lld': 'Ejam',
    },
    'Test': {
      'de': 'Test',
      'en': 'Test',
      'it': 'Test',
      'lld': 'Test',
    },
    'Präsentation': {
      'de': 'Präsentation',
      'en': 'Presentation',
      'it': 'Presentazione',
      'lld': 'Prejentaziun',
    },
    'Projekt': {
      'de': 'Projekt',
      'en': 'Project',
      'it': 'Progetto',
      'lld': 'Proiet',
    },
    'Mündlich': {
      'de': 'Mündlich',
      'en': 'Oral',
      'it': 'Orale',
      'lld': 'Oral',
    },
    'Abgabe': {
      'de': 'Abgabe',
      'en': 'Submission',
      'it': 'Consegna',
      'lld': 'Consegna',
    },
    'Bewertung': {
      'de': 'Bewertung',
      'en': 'Assessment',
      'it': 'Valutazione',
      'lld': 'Valutaziun',
    },
    'Referat': {
      'de': 'Referat',
      'en': 'Presentation',
      'it': 'Relazione',
      'lld': 'Referat',
    },
    'Plus': {
      'de': 'Plus',
      'en': 'Plus',
      'it': 'Più',
      'lld': 'Plü',
    },
  };
  return translations[value]?[language] ?? translations[value]?['de'] ?? value;
}

String _demoGradeNameText(String value, String language) {
  const translations = <String, Map<String, String>>{
    'Textanalyse': {
      'de': 'Textanalyse',
      'en': 'Text analysis',
      'it': 'Analisi del testo',
      'lld': 'Analisa dl test',
    },
    'Lesetagebuch': {
      'de': 'Lesetagebuch',
      'en': 'Reading journal',
      'it': 'Diario di lettura',
      'lld': 'Diarì de letöra',
    },
    'Interpretation': {
      'de': 'Interpretation',
      'en': 'Interpretation',
      'it': 'Interpretazione',
      'lld': 'Interpretaziun',
    },
    'Lineare Funktionen': {
      'de': 'Lineare Funktionen',
      'en': 'Linear functions',
      'it': 'Funzioni lineari',
      'lld': 'Funziuns lineares',
    },
    'Quadratische Gleichungen': {
      'de': 'Quadratische Gleichungen',
      'en': 'Quadratic equations',
      'it': 'Equazioni quadratiche',
      'lld': 'Ecwaziuns cuadratiches',
    },
    'Kurzkontrolle': {
      'de': 'Kurzkontrolle',
      'en': 'Quick quiz',
      'it': 'Verifica breve',
      'lld': 'Controla cürta',
    },
    'Vocabulary Unit 2': {
      'de': 'Vokabeln Unit 2',
      'en': 'Vocabulary Unit 2',
      'it': 'Vocabolario Unit 2',
      'lld': 'Vocabuler Unit 2',
    },
    'Climate Change': {
      'de': 'Climate Change',
      'en': 'Climate Change',
      'it': 'Cambiamento climatico',
      'lld': 'Mudamënt climatic',
    },
    'Flutter Grundlagen': {
      'de': 'Flutter Grundlagen',
      'en': 'Flutter basics',
      'it': 'Fondamenti di Flutter',
      'lld': 'Bases de Flutter',
    },
    'Datenstrukturen': {
      'de': 'Datenstrukturen',
      'en': 'Data structures',
      'it': 'Strutture dati',
      'lld': 'Strutures de dac',
    },
    'SQL Übungen': {
      'de': 'SQL Übungen',
      'en': 'SQL exercises',
      'it': 'Esercizi SQL',
      'lld': 'Esercizis SQL',
    },
    'Industrialisierung': {
      'de': 'Industrialisierung',
      'en': 'Industrialization',
      'it': 'Industrializzazione',
      'lld': 'Industrialisaziun',
    },
    'Europa im 20. Jahrhundert': {
      'de': 'Europa im 20. Jahrhundert',
      'en': 'Europe in the 20th century',
      'it': 'Europa nel XX secolo',
      'lld': 'Europa tl 20. secul',
    },
    'Grammatica': {
      'de': 'Grammatica',
      'en': 'Grammar',
      'it': 'Grammatica',
      'lld': 'Gramatica',
    },
    'Conversazione': {
      'de': 'Conversazione',
      'en': 'Conversation',
      'it': 'Conversazione',
      'lld': 'Conversaziun',
    },
    'Netzwerkplan': {
      'de': 'Netzwerkplan',
      'en': 'Network plan',
      'it': 'Piano di rete',
      'lld': 'Plan de rëi',
    },
    'Routing': {
      'de': 'Routing',
      'en': 'Routing',
      'it': 'Routing',
      'lld': 'Routing',
    },
    'CAD Entwurf': {
      'de': 'CAD Entwurf',
      'en': 'CAD draft',
      'it': 'Bozza CAD',
      'lld': 'Boza CAD',
    },
    'Werkstattplanung': {
      'de': 'Werkstattplanung',
      'en': 'Workshop planning',
      'it': 'Pianificazione laboratorio',
      'lld': 'Planisaziun dl laboratore',
    },
    'Sprintplanung': {
      'de': 'Sprintplanung',
      'en': 'Sprint planning',
      'it': 'Pianificazione sprint',
      'lld': 'Planisaziun sprint',
    },
    'Roadmap': {
      'de': 'Roadmap',
      'en': 'Roadmap',
      'it': 'Roadmap',
      'lld': 'Roadmap',
    },
    'Koordination': {
      'de': 'Koordination',
      'en': 'Coordination',
      'it': 'Coordinazione',
      'lld': 'Coordinaziun',
    },
    'Ausdauer': {
      'de': 'Ausdauer',
      'en': 'Endurance',
      'it': 'Resistenza',
      'lld': 'Resistënza',
    },
    'Diskussion': {
      'de': 'Diskussion',
      'en': 'Discussion',
      'it': 'Discussione',
      'lld': 'Discussiun',
    },
    'Ethik': {
      'de': 'Ethik',
      'en': 'Ethics',
      'it': 'Etica',
      'lld': 'Etica',
    },
  };
  return translations[value]?[language] ?? translations[value]?['de'] ?? value;
}

final List<_DemoSubject> _demoSubjects = <_DemoSubject>[
  _DemoSubject(
    id: 1,
    name: 'Deutsch',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 101,
        date: _today().subtract(const Duration(days: 70)),
        grade: '8.00',
        weight: 100,
        type: 'Schularbeit',
        name: 'Textanalyse',
      ),
      _DemoGrade(
        id: 102,
        date: _today().subtract(const Duration(days: 45)),
        grade: '9.00',
        weight: 100,
        type: 'Mitarbeit',
        name: 'Lesetagebuch',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 103,
        date: _today().subtract(const Duration(days: 18)),
        grade: '8.50',
        weight: 100,
        type: 'Prüfung',
        name: 'Interpretation',
      ),
    ],
  ),
  _DemoSubject(
    id: 2,
    name: 'Mathematik',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 201,
        date: _today().subtract(const Duration(days: 75)),
        grade: '7.50',
        weight: 100,
        type: 'Test',
        name: 'Lineare Funktionen',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 202,
        date: _today().subtract(const Duration(days: 20)),
        grade: '8.00',
        weight: 100,
        type: 'Schularbeit',
        name: 'Quadratische Gleichungen',
      ),
      _DemoGrade(
        id: 203,
        date: _today().subtract(const Duration(days: 8)),
        grade: '9.00',
        weight: 100,
        type: 'Mitarbeit',
        name: 'Kurzkontrolle',
      ),
    ],
  ),
  _DemoSubject(
    id: 3,
    name: 'Englisch',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 301,
        date: _today().subtract(const Duration(days: 62)),
        grade: '8.00',
        weight: 100,
        type: 'Test',
        name: 'Vocabulary Unit 2',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 302,
        date: _today().subtract(const Duration(days: 15)),
        grade: '9.00',
        weight: 100,
        type: 'Präsentation',
        name: 'Climate Change',
      ),
    ],
  ),
  _DemoSubject(
    id: 4,
    name: 'Informatik',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 401,
        date: _today().subtract(const Duration(days: 66)),
        grade: '9.00',
        weight: 100,
        type: 'Projekt',
        name: 'Flutter Grundlagen',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 402,
        date: _today().subtract(const Duration(days: 12)),
        grade: '10.00',
        weight: 100,
        type: 'Test',
        name: 'Datenstrukturen',
      ),
      _DemoGrade(
        id: 403,
        date: _today().subtract(const Duration(days: 5)),
        grade: '9.00',
        weight: 100,
        type: 'Mitarbeit',
        name: 'SQL Übungen',
      ),
    ],
  ),
  _DemoSubject(
    id: 5,
    name: 'Geschichte',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 501,
        date: _today().subtract(const Duration(days: 58)),
        grade: '8.00',
        weight: 100,
        type: 'Test',
        name: 'Industrialisierung',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 502,
        date: _today().subtract(const Duration(days: 11)),
        grade: '8.00',
        weight: 100,
        type: 'Prüfung',
        name: 'Europa im 20. Jahrhundert',
      ),
    ],
  ),
  _DemoSubject(
    id: 6,
    name: 'Italienisch',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 601,
        date: _today().subtract(const Duration(days: 80)),
        grade: '7.50',
        weight: 100,
        type: 'Test',
        name: 'Grammatica',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 602,
        date: _today().subtract(const Duration(days: 10)),
        grade: '8.00',
        weight: 100,
        type: 'Mündlich',
        name: 'Conversazione',
      ),
    ],
  ),
  _DemoSubject(
    id: 7,
    name: 'Systeme und Netze',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 701,
        date: _today().subtract(const Duration(days: 52)),
        grade: '9.00',
        weight: 100,
        type: 'Projekt',
        name: 'Netzwerkplan',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 702,
        date: _today().subtract(const Duration(days: 9)),
        grade: '8.50',
        weight: 100,
        type: 'Test',
        name: 'Routing',
      ),
    ],
  ),
  _DemoSubject(
    id: 8,
    name: 'Technologie und Planung',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 801,
        date: _today().subtract(const Duration(days: 63)),
        grade: '8.00',
        weight: 100,
        type: 'Abgabe',
        name: 'CAD Entwurf',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 802,
        date: _today().subtract(const Duration(days: 7)),
        grade: '9.00',
        weight: 100,
        type: 'Projekt',
        name: 'Werkstattplanung',
      ),
    ],
  ),
  _DemoSubject(
    id: 9,
    name: 'Projektmanagement',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 901,
        date: _today().subtract(const Duration(days: 61)),
        grade: '9.00',
        weight: 100,
        type: 'Mitarbeit',
        name: 'Sprintplanung',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 902,
        date: _today().subtract(const Duration(days: 6)),
        grade: '9.50',
        weight: 100,
        type: 'Projekt',
        name: 'Roadmap',
      ),
    ],
  ),
  _DemoSubject(
    id: 10,
    name: 'Bewegung und Sport',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 1001,
        date: _today().subtract(const Duration(days: 59)),
        grade: '9.00',
        weight: 100,
        type: 'Bewertung',
        name: 'Koordination',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 1002,
        date: _today().subtract(const Duration(days: 4)),
        grade: '10.00',
        weight: 100,
        type: 'Bewertung',
        name: 'Ausdauer',
      ),
    ],
  ),
  _DemoSubject(
    id: 11,
    name: 'Religion',
    firstSemester: <_DemoGrade>[
      _DemoGrade(
        id: 1101,
        date: _today().subtract(const Duration(days: 57)),
        grade: '8.00',
        weight: 100,
        type: 'Mitarbeit',
        name: 'Diskussion',
      ),
    ],
    secondSemester: <_DemoGrade>[
      _DemoGrade(
        id: 1102,
        date: _today().subtract(const Duration(days: 3)),
        grade: '8.50',
        weight: 100,
        type: 'Referat',
        name: 'Ethik',
      ),
    ],
  ),
];

const Map<String, Map<String, String>> _demoTranslations =
    <String, Map<String, String>>{
      'absenceSaved': {
        'de': 'Absenz gespeichert',
        'en': 'Absence saved',
        'it': 'Assenza salvata',
        'lld': 'Assënza salvada',
      },
      'reminderTitle': {
        'de': 'Erinnerung',
        'en': 'Reminder',
        'it': 'Promemoria',
        'lld': 'Monitoranza',
      },
      'reminderSportsBag': {
        'de': 'Turnbeutel einpacken',
        'en': 'Pack your sports bag',
        'it': 'Prepara la borsa per sport',
        'lld': 'Meti ite la borsa por sport',
      },
      'historyHomework': {
        'de': 'Kapitel 4 zusammenfassen',
        'en': 'Summarize chapter 4',
        'it': 'Riassumi il capitolo 4',
        'lld': 'Fai n riassunt dl capitol 4',
      },
      'springBreak': {
        'de': 'Frühlingsferien',
        'en': 'Spring break',
        'it': 'Vacanze di primavera',
        'lld': 'Vacanzes de primavëra',
      },
      'doctorAppointment': {
        'de': 'Arzttermin',
        'en': 'Doctor appointment',
        'it': 'Visita medica',
        'lld': 'Apointamënt dal dotur',
      },
      'delay': {
        'de': 'Verspätung',
        'en': 'Delay',
        'it': 'Ritardo',
        'lld': 'Retard',
      },
      'dashboardTitleTest': {
        'de': 'Test',
        'en': 'Test',
        'it': 'Test',
        'lld': 'Test',
      },
      'dashboardTitleHomework': {
        'de': 'Hausaufgabe',
        'en': 'Homework',
        'it': 'Compito',
        'lld': 'Compit',
      },
      'dashboardTitleSchoolwork': {
        'de': 'Schularbeit',
        'en': 'Schoolwork',
        'it': 'Compito in classe',
        'lld': 'Compit de classa',
      },
      'dashboardTitleExam': {
        'de': 'Prüfung',
        'en': 'Exam',
        'it': 'Esame',
        'lld': 'Ejam',
      },
      'dashboardTitleProjectSubmission': {
        'de': 'Projektabgabe',
        'en': 'Project submission',
        'it': 'Consegna progetto',
        'lld': 'Consegna dl proiet',
      },
      'dashboardTitleHoliday': {
        'de': 'Ferien',
        'en': 'Holiday',
        'it': 'Vacanza',
        'lld': 'Vacanza',
      },
      'messageWelcomeSubject': {
        'de': 'Willkommen im Demo-Konto',
        'en': 'Welcome to the demo account',
        'it': 'Benvenuto nell’account demo',
        'lld': 'Bëgnodü tl account demo',
      },
      'messageTripSubject': {
        'de': 'Mitteilung zum Lehrausflug',
        'en': 'Message about the field trip',
        'it': 'Comunicazione sulla gita scolastica',
        'lld': 'Comunicaziun sön la gita scola',
      },
      'messageFallbackSubject': {
        'de': 'Demo-Mitteilung',
        'en': 'Demo message',
        'it': 'Messaggio demo',
        'lld': 'Mesaj demo',
      },
      'messageSenderOffice': {
        'de': 'Sekretariat',
        'en': 'Office',
        'it': 'Segreteria',
        'lld': 'Sekretariat',
      },
      'messageSenderClassBoard': {
        'de': 'Klassenvorstand',
        'en': 'Class board',
        'it': 'Coordinatore di classe',
        'lld': 'Cunsëi de classa',
      },
      'messageWelcomeLine1': {
        'de': 'Dieses Demo-Konto funktioniert vollständig lokal auf dem Gerät.',
        'en': 'This demo account runs entirely locally on the device.',
        'it': 'Questo account demo funziona interamente in locale sul dispositivo.',
        'lld': 'Chësc account demo laora daldöt local sön le aparat.',
      },
      'messageWelcomeLine2': {
        'de': 'Du kannst Erinnerungen, Absenzen und Profileinstellungen gefahrlos testen.',
        'en': 'You can safely test reminders, absences, and profile settings.',
        'it': 'Puoi testare senza rischi promemoria, assenze e impostazioni del profilo.',
        'lld': 'Podes provè monitoranzes, assënzes y impostaziuns dl profil sainza rischi.',
      },
      'messageTripLine1': {
        'de': 'Am Freitag findet der Demo-Lehrausflug ins Technikmuseum statt.',
        'en': 'The demo field trip to the technology museum takes place on Friday.',
        'it': 'Venerdì si terrà la gita demo al museo della tecnologia.',
        'lld': 'Vëndres é la gita demo al museum dla tecnologia.',
      },
      'messageTripLine2': {
        'de': 'Treffpunkt ist um 07:30 Uhr vor dem Haupteingang.',
        'en': 'Meeting point is at 7:30 AM in front of the main entrance.',
        'it': 'Il ritrovo è alle 07:30 davanti all’ingresso principale.',
        'lld': 'L ncunter é ales 07:30 dan le gran ingrès.',
      },
      'messageTripLine3': {
        'de': 'Bitte eine Trinkflasche und Schreibmaterial mitnehmen.',
        'en': 'Please bring a water bottle and writing materials.',
        'it': 'Porta con te una borraccia e il materiale per scrivere.',
        'lld': 'Prëi con te na boza d’aiga y material por scrie.',
      },
      'messageFallbackLine': {
        'de': 'Dies ist eine lokal erzeugte Demo-Mitteilung.',
        'en': 'This is a locally generated demo message.',
        'it': 'Questo è un messaggio demo generato localmente.',
        'lld': 'Chësc é n mesaj demo generé localmënter.',
      },
      'notificationLocalModeTitle': {
        'de': 'Demo-Hinweis',
        'en': 'Demo note',
        'it': 'Nota demo',
        'lld': 'Nota demo',
      },
      'notificationLocalModeSubtitle': {
        'de': 'Dieses Konto funktioniert vollständig lokal.',
        'en': 'This account works fully offline and locally.',
        'it': 'Questo account funziona interamente in locale.',
        'lld': 'Chësc account laora daldöt local.',
      },
      'certificateHeading': {
        'de': 'Demo-Zeugnis',
        'en': 'Demo certificate',
        'it': 'Certificato demo',
        'lld': 'Zertificat demo',
      },
      'certificateBody': {
        'de': 'Dieses Zeugnis wird lokal im Demo-Konto erzeugt.',
        'en': 'This certificate is generated locally in the demo account.',
        'it': 'Questo certificato viene generato localmente nell’account demo.',
        'lld': 'Chësc zertificat vën generé localmënter tl account demo.',
      },
      'certificateDateLabel': {
        'de': 'Stand',
        'en': 'Issued',
        'it': 'Data',
        'lld': 'Data',
      },
      'certificateSummary': {
        'de': 'Übersicht',
        'en': 'Summary',
        'it': 'Riepilogo',
        'lld': 'Resumè',
      },
      'certificateGrades': {
        'de': 'Noten',
        'en': 'Grades',
        'it': 'Voti',
        'lld': 'Proi',
      },
      'certificateSubject': {
        'de': 'Fach',
        'en': 'Subject',
        'it': 'Materia',
        'lld': 'Diciplina',
      },
      'certificateGrade': {
        'de': 'Note',
        'en': 'Grade',
        'it': 'Voto',
        'lld': 'Pro',
      },
      'certificateAverage': {
        'de': 'Durchschnitt',
        'en': 'Average',
        'it': 'Media',
        'lld': 'Media',
      },
      'certificateAbsences': {
        'de': 'Absenzen',
        'en': 'Absences',
        'it': 'Assenze',
        'lld': 'Assënzes',
      },
      'certificateBehavior': {
        'de': 'Verhalten',
        'en': 'Conduct',
        'it': 'Comportamento',
        'lld': 'Comportamënt',
      },
      'certificatePositive': {
        'de': 'Sehr positiv',
        'en': 'Very positive',
        'it': 'Molto positivo',
        'lld': 'Massa positif',
      },
      'teacherPlaceholderFirst': {
        'de': 'Lehrperson',
        'en': 'Teacher',
        'it': 'Docente',
        'lld': 'Insignante',
      },
      'teacherPlaceholderLast': {
        'de': 'Platzhalter',
        'en': 'Placeholder',
        'it': 'Segnaposto',
        'lld': 'Placeholder',
      },
      'roomPlaceholder': {
        'de': 'Raum Platzhalter',
        'en': 'Room Placeholder',
        'it': 'Aula segnaposto',
        'lld': 'Aula placeholder',
      },
    };
