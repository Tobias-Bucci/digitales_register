// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.

import 'package:dr/data.dart';

/// A named interval in which the existing school calendar contains no lessons.
class SchoolHoliday {
  const SchoolHoliday({
    required this.name,
    required this.start,
    required this.end,
  });

  final String name;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) {
    final day = _dateOnly(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

/// A grading deadline found among the existing calendar/dashboard events.
class GradeDeadline {
  const GradeDeadline({
    required this.name,
    required this.date,
  });

  final String name;
  final DateTime date;
}

class HolidayCountdown {
  const HolidayCountdown({
    required this.holiday,
    required this.isOnHoliday,
    required this.remainingDays,
    required this.progress,
    required this.periodStart,
  });

  final SchoolHoliday holiday;
  final bool isOnHoliday;
  final int remainingDays;
  final double progress;
  final DateTime periodStart;
}

class GradeDeadlineCountdown {
  const GradeDeadlineCountdown({
    required this.deadline,
    required this.remainingDays,
    required this.progress,
    required this.periodStart,
  });

  final GradeDeadline deadline;
  final int remainingDays;
  final double progress;
  final DateTime periodStart;
}

/// Extracts school periods from data that is already loaded for the dashboard
/// and calendar. It deliberately does not maintain a separate holiday list.
class SchoolTimeline {
  const SchoolTimeline({
    required this.holidays,
    required this.gradeDeadlines,
    this.schoolYearStart,
  });

  final List<SchoolHoliday> holidays;
  final List<GradeDeadline> gradeDeadlines;
  final DateTime? schoolYearStart;

  factory SchoolTimeline.fromCalendarData({
    required Iterable<Day> dashboardDays,
    required Iterable<CalendarDay> calendarDays,
  }) {
    final days = dashboardDays.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final explicitHolidayDays = <DateTime, String>{};
    final deadlines = <DateTime, GradeDeadline>{};
    DateTime? detectedSchoolYearStart;

    for (final day in days) {
      final date = _dateOnly(day.date);
      for (final item in day.homework) {
        final searchable = _normalize(
          '${item.title} ${item.subtitle} ${item.label ?? ''}',
        );
        if (_isHolidayEntry(searchable)) {
          explicitHolidayDays[date] = item.subtitle.trim().isEmpty
              ? item.title.trim()
              : item.subtitle.trim();
        }
        if (_isGradeDeadlineEntry(searchable)) {
          deadlines[date] = GradeDeadline(
            name: item.title.trim(),
            date: date,
          );
        }
        if (_isSchoolYearStartEntry(searchable)) {
          detectedSchoolYearStart = _earlier(detectedSchoolYearStart, date);
        }
      }
    }

    final calendar = calendarDays.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final inferredFreeWeekdays = <DateTime>{};
    for (final day in calendar) {
      final date = _dateOnly(day.date);
      if (date.weekday <= DateTime.friday && day.hours.isEmpty) {
        inferredFreeWeekdays.add(date);
      }
      if (day.hours.isNotEmpty) {
        detectedSchoolYearStart = _earlier(detectedSchoolYearStart, date);
      }
    }

    if (detectedSchoolYearStart == null && days.isNotEmpty) {
      detectedSchoolYearStart = _dateOnly(days.first.date);
    }

    final holidays = <SchoolHoliday>[
      ..._groupNamedHolidayDays(explicitHolidayDays),
      ..._groupInferredFreeDays(
        inferredFreeWeekdays.difference(explicitHolidayDays.keys.toSet()),
      ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    return SchoolTimeline(
      holidays: _removeOverlappingFallbacks(holidays),
      gradeDeadlines: deadlines.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
      schoolYearStart: detectedSchoolYearStart,
    );
  }

  HolidayCountdown? holidayCountdownAt(DateTime value) {
    final today = _dateOnly(value);
    SchoolHoliday? current;
    SchoolHoliday? next;
    SchoolHoliday? previous;
    for (final holiday in holidays) {
      if (holiday.contains(today)) {
        current = holiday;
        break;
      }
      if (holiday.end.isBefore(today)) {
        previous = holiday;
      } else if (holiday.start.isAfter(today)) {
        next = holiday;
        break;
      }
    }

    if (current != null) {
      return HolidayCountdown(
        holiday: current,
        isOnHoliday: true,
        remainingDays: current.end.difference(today).inDays + 1,
        progress: _progress(today, current.start, current.end),
        periodStart: current.start,
      );
    }
    if (next == null) {
      return null;
    }

    var periodStart =
        previous?.end.add(const Duration(days: 1)) ?? schoolYearStart ?? today;
    if (periodStart.isAfter(today)) {
      periodStart = today;
    }
    return HolidayCountdown(
      holiday: next,
      isOnHoliday: false,
      remainingDays: next.start.difference(today).inDays,
      progress: _progress(today, periodStart, next.start),
      periodStart: periodStart,
    );
  }

  GradeDeadlineCountdown? gradeDeadlineCountdownAt(DateTime value) {
    final today = _dateOnly(value);
    GradeDeadline? previous;
    GradeDeadline? next;
    for (final deadline in gradeDeadlines) {
      if (deadline.date.isBefore(today)) {
        previous = deadline;
      } else {
        next = deadline;
        break;
      }
    }
    if (next == null) {
      return null;
    }

    var periodStart =
        previous?.date.add(const Duration(days: 1)) ?? schoolYearStart ?? today;
    if (periodStart.isAfter(today)) {
      periodStart = today;
    }
    return GradeDeadlineCountdown(
      deadline: next,
      remainingDays: next.date.difference(today).inDays,
      progress: _progress(today, periodStart, next.date),
      periodStart: periodStart,
    );
  }
}

List<SchoolHoliday> _groupNamedHolidayDays(Map<DateTime, String> values) {
  final dates = values.keys.toList()..sort();
  final result = <SchoolHoliday>[];
  for (final date in dates) {
    final name = values[date]!;
    if (result.isNotEmpty &&
        result.last.name == name &&
        date.difference(result.last.end).inDays == 1) {
      final previous = result.removeLast();
      result.add(SchoolHoliday(name: name, start: previous.start, end: date));
    } else {
      result.add(SchoolHoliday(name: name, start: date, end: date));
    }
  }
  return result;
}

List<SchoolHoliday> _groupInferredFreeDays(Set<DateTime> values) {
  final dates = values.toList()..sort();
  final result = <SchoolHoliday>[];
  for (final date in dates) {
    if (result.isNotEmpty) {
      final gap = date.difference(result.last.end).inDays;
      final bridgesWeekend = result.last.end.weekday == DateTime.friday &&
          date.weekday == DateTime.monday &&
          gap == 3;
      if (gap == 1 || bridgesWeekend) {
        final previous = result.removeLast();
        result.add(
          SchoolHoliday(name: '', start: previous.start, end: date),
        );
        continue;
      }
    }
    result.add(SchoolHoliday(name: '', start: date, end: date));
  }
  return result;
}

List<SchoolHoliday> _removeOverlappingFallbacks(List<SchoolHoliday> values) {
  final named = values.where((holiday) => holiday.name.isNotEmpty).toList();
  return values.where((holiday) {
    if (holiday.name.isNotEmpty) return true;
    return !named.any(
      (entry) =>
          !holiday.end.isBefore(entry.start) &&
          !holiday.start.isAfter(entry.end),
    );
  }).toList();
}

bool _isHolidayEntry(String value) => <String>[
      'sospensione delle lezioni',
      'vacanza',
      'vacanze',
      'ferien',
      'schulfrei',
      'unterrichtsfrei',
      'school holiday',
      'school closure',
    ].any(value.contains);

bool _isGradeDeadlineEntry(String value) => <String>[
      'notenschluss',
      'bewertungsschluss',
      'schluss der bewertung',
      'chiusura valutazioni',
      'chiusura voti',
      'grade deadline',
      'grading deadline',
      'assessment deadline',
      'fin dla valutaziun',
    ].any(value.contains);

bool _isSchoolYearStartEntry(String value) => <String>[
      'inizio delle lezioni',
      'schulbeginn',
      'unterrichtsbeginn',
      'start of school',
      'start of classes',
      'scomenciamënt dla scola',
    ].any(value.contains);

String _normalize(String value) => value.trim().toLowerCase();

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime? _earlier(DateTime? current, DateTime candidate) =>
    current == null || candidate.isBefore(current) ? candidate : current;

double _progress(DateTime value, DateTime start, DateTime end) {
  if (!end.isAfter(start)) {
    return value.isBefore(start) ? 0 : 1;
  }
  final total = end.difference(start).inDays;
  final elapsed = value.difference(start).inDays;
  return (elapsed / total).clamp(0.0, 1.0);
}
