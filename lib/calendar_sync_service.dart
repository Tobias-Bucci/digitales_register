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
import 'dart:developer';

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _calendarSyncMethodChannel = MethodChannel('dr/calendar_sync');
const _calendarSyncRecordsKey = 'calendarSyncRecords';
const _calendarSyncMarkerPrefix = '[Digitales Register Sync: ';

enum CalendarSyncEnableResult {
  ready,
  permissionDenied,
  noWritableCalendar,
  unsupported,
}

class CalendarSyncDesiredItem {
  const CalendarSyncDesiredItem({
    required this.syncKey,
    required this.title,
    required this.description,
    required this.date,
    required this.fingerprint,
  });

  final String syncKey;
  final String title;
  final String description;
  final UtcDateTime date;
  final String fingerprint;
}

class CalendarSyncRecord {
  const CalendarSyncRecord({
    required this.syncKey,
    required this.eventId,
    required this.calendarId,
    required this.fingerprint,
  });

  factory CalendarSyncRecord.fromJson(Map<String, dynamic> json) {
    return CalendarSyncRecord(
      syncKey: getString(json['syncKey']) ?? '',
      eventId: getInt(json['eventId']) ?? 0,
      calendarId: getInt(json['calendarId']) ?? 0,
      fingerprint: getString(json['fingerprint']) ?? '',
    );
  }

  final String syncKey;
  final int eventId;
  final int calendarId;
  final String fingerprint;

  Map<String, Object> toJson() {
    return <String, Object>{
      'syncKey': syncKey,
      'eventId': eventId,
      'calendarId': calendarId,
      'fingerprint': fingerprint,
    };
  }
}

class CalendarSyncUpsertRequest {
  const CalendarSyncUpsertRequest({
    required this.calendarId,
    required this.title,
    required this.description,
    required this.startMillisUtc,
    required this.endMillisUtc,
    this.eventId,
  });

  final int calendarId;
  final String title;
  final String description;
  final int startMillisUtc;
  final int endMillisUtc;
  final int? eventId;
}

typedef CalendarSyncPermissionOverride = Future<bool> Function();
typedef CalendarSyncDefaultCalendarOverride = Future<int?> Function();
typedef CalendarSyncUpsertOverride = Future<int?> Function(
  CalendarSyncUpsertRequest request,
);
typedef CalendarSyncDeleteOverride = Future<void> Function(int eventId);

class CalendarSyncService {
  static CalendarSyncPermissionOverride? requestPermissionOverride;
  static CalendarSyncDefaultCalendarOverride? getDefaultCalendarIdOverride;
  static CalendarSyncUpsertOverride? upsertEventOverride;
  static CalendarSyncDeleteOverride? deleteEventOverride;

  static Future<CalendarSyncEnableResult> prepareForEnable() async {
    if (!isAndroidPlatform) {
      return CalendarSyncEnableResult.unsupported;
    }

    final permissionGranted = await _requestPermission();
    if (!permissionGranted) {
      return CalendarSyncEnableResult.permissionDenied;
    }

    final calendarId = await _getDefaultCalendarId();
    if (calendarId == null) {
      return CalendarSyncEnableResult.noWritableCalendar;
    }

    return CalendarSyncEnableResult.ready;
  }

  static Future<bool> reconcile(AppState state) async {
    if (!isAndroidPlatform || !state.settingsState.calendarSyncEnabled) {
      return true;
    }

    final calendarId = await _getDefaultCalendarId();
    if (calendarId == null) {
      return false;
    }

    final desiredItems = collectDesiredItems(state);
    final desiredByKey = <String, CalendarSyncDesiredItem>{
      for (final item in desiredItems) item.syncKey: item,
    };

    final records = await _readRecords();
    final updatedRecords = Map<String, CalendarSyncRecord>.from(records);
    var success = true;

    for (final entry in records.entries) {
      if (desiredByKey.containsKey(entry.key)) {
        continue;
      }
      try {
        await _deleteEvent(entry.value.eventId);
        updatedRecords.remove(entry.key);
      } catch (e, trace) {
        success = false;
        log(
          'Failed to delete calendar event for ${entry.key}',
          error: e,
          stackTrace: trace,
        );
      }
    }

    for (final item in desiredItems) {
      final existing = updatedRecords[item.syncKey];
      if (existing != null &&
          existing.calendarId == calendarId &&
          existing.fingerprint == item.fingerprint) {
        continue;
      }

      try {
        var existingEventId = existing?.eventId;
        if (existing != null && existing.calendarId != calendarId) {
          await _deleteEvent(existing.eventId);
          existingEventId = null;
        }

        final eventId = await _upsertEvent(
          CalendarSyncUpsertRequest(
            eventId: existingEventId,
            calendarId: calendarId,
            title: item.title,
            description: _appendMarker(item.description, item.syncKey),
            startMillisUtc: _allDayStart(item.date).millisecondsSinceEpoch,
            endMillisUtc:
                _allDayStart(item.date).add(const Duration(days: 1)).millisecondsSinceEpoch,
          ),
        );

        if (eventId == null) {
          success = false;
          continue;
        }

        updatedRecords[item.syncKey] = CalendarSyncRecord(
          syncKey: item.syncKey,
          eventId: eventId,
          calendarId: calendarId,
          fingerprint: item.fingerprint,
        );
      } catch (e, trace) {
        success = false;
        log(
          'Failed to upsert calendar event for ${item.syncKey}',
          error: e,
          stackTrace: trace,
        );
      }
    }

    await _writeRecords(updatedRecords);
    return success;
  }

  static Future<bool> deleteTrackedEvents() async {
    final records = await _readRecords();
    if (records.isEmpty) {
      return true;
    }

    final remaining = <String, CalendarSyncRecord>{};
    var success = true;
    for (final entry in records.entries) {
      try {
        await _deleteEvent(entry.value.eventId);
      } catch (e, trace) {
        success = false;
        remaining[entry.key] = entry.value;
        log(
          'Failed to remove tracked calendar event for ${entry.key}',
          error: e,
          stackTrace: trace,
        );
      }
    }

    await _writeRecords(remaining);
    return success;
  }

  static List<CalendarSyncDesiredItem> collectDesiredItems(AppState state) {
    final today = UtcDateTime(now.year, now.month, now.day);
    final items = <String, CalendarSyncDesiredItem>{};

    final dashboardDays = state.dashboardState.allDays ?? const <Day>[];
    for (final day in dashboardDays) {
      final dueDate = UtcDateTime(day.date.year, day.date.month, day.date.day);
      if (dueDate.isBefore(today)) {
        continue;
      }

      for (final homework in day.homework) {
        if (!_shouldSyncDashboardHomework(homework)) {
          continue;
        }

        final syncKey = homework.type == HomeworkType.homework
            ? 'reminder:${homework.id}'
            : 'dashboard:${_dateKey(dueDate)}:${homework.type.name}:${homework.id > 0 ? homework.id : _stableHash('${homework.title}|${homework.subtitle}|${homework.label ?? ''}')}';
        items[syncKey] = _buildDesiredItem(
          syncKey: syncKey,
          title: homework.title,
          date: dueDate,
          details: <String>[
            if (homework.label != null && homework.label!.isNotEmpty)
              homework.label!,
            if (homework.subtitle.isNotEmpty) homework.subtitle,
          ],
        );
      }
    }

    for (final day in state.calendarState.days.values) {
      for (final hour in day.hours) {
        for (final homeworkExam in hour.homeworkExams) {
          final dueDate = UtcDateTime(
            homeworkExam.deadline.year,
            homeworkExam.deadline.month,
            homeworkExam.deadline.day,
          );
          if (dueDate.isBefore(today)) {
            continue;
          }
          final syncKey = 'calendar:${homeworkExam.id}';
          items[syncKey] = _buildDesiredItem(
            syncKey: syncKey,
            title: homeworkExam.name,
            date: dueDate,
            details: <String>[
              if (homeworkExam.typeName.isNotEmpty) homeworkExam.typeName,
              if (hour.subject.isNotEmpty) hour.subject,
            ],
          );
        }
      }
    }

    final result = items.values.toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) {
          return byDate;
        }
        return a.syncKey.compareTo(b.syncKey);
      });
    return result;
  }

  static CalendarSyncDesiredItem _buildDesiredItem({
    required String syncKey,
    required String title,
    required UtcDateTime date,
    required List<String> details,
  }) {
    final normalizedTitle = title.trim().isEmpty ? 'Digitales Register' : title.trim();
    final description = details
        .map((detail) => detail.trim())
        .where((detail) => detail.isNotEmpty)
        .toSet()
        .join('\n');
    return CalendarSyncDesiredItem(
      syncKey: syncKey,
      title: normalizedTitle,
      description: description,
      date: date,
      fingerprint: _stableHash(
        '$normalizedTitle|$description|${date.toIso8601String()}',
      ).toString(),
    );
  }

  static bool _shouldSyncDashboardHomework(Homework homework) {
    return homework.type == HomeworkType.homework ||
        homework.type == HomeworkType.lessonHomework ||
        homework.type == HomeworkType.gradeGroup;
  }

  static String _appendMarker(String description, String syncKey) {
    final marker = '$_calendarSyncMarkerPrefix$syncKey]';
    if (description.isEmpty) {
      return marker;
    }
    return '$description\n\n$marker';
  }

  static UtcDateTime _allDayStart(UtcDateTime date) {
    return UtcDateTime(date.year, date.month, date.day);
  }

  static Future<bool> _requestPermission() async {
    if (requestPermissionOverride != null) {
      return requestPermissionOverride!();
    }

    final granted = await _calendarSyncMethodChannel
        .invokeMethod<bool>('requestCalendarPermission');
    return granted ?? false;
  }

  static Future<int?> _getDefaultCalendarId() async {
    if (getDefaultCalendarIdOverride != null) {
      return getDefaultCalendarIdOverride!();
    }

    return _calendarSyncMethodChannel.invokeMethod<int>('getDefaultCalendarId');
  }

  static Future<int?> _upsertEvent(CalendarSyncUpsertRequest request) async {
    if (upsertEventOverride != null) {
      return upsertEventOverride!(request);
    }

    return _calendarSyncMethodChannel.invokeMethod<int>(
      'upsertCalendarEvent',
      <String, Object?>{
        'eventId': request.eventId,
        'calendarId': request.calendarId,
        'title': request.title,
        'description': request.description,
        'startMillisUtc': request.startMillisUtc,
        'endMillisUtc': request.endMillisUtc,
      },
    );
  }

  static Future<void> _deleteEvent(int eventId) async {
    if (deleteEventOverride != null) {
      await deleteEventOverride!(eventId);
      return;
    }

    await _calendarSyncMethodChannel.invokeMethod<void>(
      'deleteCalendarEvent',
      <String, Object>{'eventId': eventId},
    );
  }

  static Future<Map<String, CalendarSyncRecord>> _readRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_calendarSyncRecordsKey);
    if (raw == null || raw.isEmpty) {
      return <String, CalendarSyncRecord>{};
    }

    try {
      final decoded = json.decode(raw);
      final list = getList(decoded) ?? const <dynamic>[];
      final records = <String, CalendarSyncRecord>{};
      for (final entry in list) {
        if (entry is! Map) {
          continue;
        }
        final record = CalendarSyncRecord.fromJson(
          entry.map<String, dynamic>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        if (record.syncKey.isEmpty || record.eventId == 0) {
          continue;
        }
        records[record.syncKey] = record;
      }
      return records;
    } catch (e, trace) {
      log(
        'Failed to parse stored calendar sync records',
        error: e,
        stackTrace: trace,
      );
      return <String, CalendarSyncRecord>{};
    }
  }

  static Future<void> _writeRecords(Map<String, CalendarSyncRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _calendarSyncRecordsKey,
      json.encode(
        records.values.map((record) => record.toJson()).toList(growable: false),
      ),
    );
  }

  static String _dateKey(UtcDateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static int _stableHash(String input) {
    var hash = 0x811C9DC5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7fffffff;
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    requestPermissionOverride = null;
    getDefaultCalendarIdOverride = null;
    upsertEventOverride = null;
    deleteEventOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_calendarSyncRecordsKey);
  }
}
