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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

enum LocalReminderAssessmentType {
  test,
  classwork,
  exam,
}

class LocalReminderAssessment {
  const LocalReminderAssessment({
    required this.type,
    required this.command,
    required this.trigger,
    required this.period,
    required this.remainder,
    required this.subject,
    required this.name,
  });

  final LocalReminderAssessmentType type;
  final String command;
  final String trigger;
  final int? period;
  final String remainder;
  final String? subject;
  final String name;

  String get serverTypeName => switch (type) {
        LocalReminderAssessmentType.test => 'Test',
        LocalReminderAssessmentType.classwork => 'Schularbeit',
        LocalReminderAssessmentType.exam => 'Prüfung',
      };

  String get displayTitle => serverTypeName;

  String? get displaySubtitle {
    if (name.isEmpty || equalsIgnoreCase(name, serverTypeName)) {
      return null;
    }
    return name;
  }

  String? get displayLabel => subject;

  String get calendarSubject {
    if (subject != null && subject!.isNotEmpty) {
      return subject!;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return serverTypeName;
  }

  String get calendarName {
    if (name.isNotEmpty) {
      return name;
    }
    return serverTypeName;
  }
}

class LocalReminderAssessmentSuggestion {
  const LocalReminderAssessmentSuggestion({
    required this.type,
    required this.command,
  });

  final LocalReminderAssessmentType type;
  final String command;
}

const _localReminderAssessmentCommands = <String, LocalReminderAssessmentType>{
  't': LocalReminderAssessmentType.test,
  'test': LocalReminderAssessmentType.test,
  'cw': LocalReminderAssessmentType.classwork,
  'classwork': LocalReminderAssessmentType.classwork,
  'schoolwork': LocalReminderAssessmentType.classwork,
  'sa': LocalReminderAssessmentType.classwork,
  'ex': LocalReminderAssessmentType.exam,
  'exam': LocalReminderAssessmentType.exam,
};

const _defaultLocalReminderAssessmentCommands =
    <LocalReminderAssessmentType, String>{
  LocalReminderAssessmentType.test: 'test',
  LocalReminderAssessmentType.classwork: 'cw',
  LocalReminderAssessmentType.exam: 'exam',
};

LocalReminderAssessment? parseLocalReminderAssessment(
  String text,
  Iterable<String> knownSubjects,
) {
  final trimmed = text.trim();
  final match =
      RegExp(r'^/([A-Za-z]+)(?:@([1-9]\d*))?(?:\s+(.*))?$').firstMatch(trimmed);
  if (match == null) {
    return null;
  }

  const trigger = '/';
  final command = match.group(1)!.toLowerCase();
  final type = _localReminderAssessmentCommands[command];
  if (type == null) {
    return null;
  }

  final period = int.tryParse(match.group(2) ?? '');
  final remainder = (match.group(3) ?? '').trim();
  final subject = _findMatchingSubject(remainder, knownSubjects);
  final name =
      subject == null ? remainder : remainder.substring(subject.length).trim();

  return LocalReminderAssessment(
    type: type,
    command: command,
    trigger: trigger,
    period: period,
    remainder: remainder,
    subject: subject,
    name: name,
  );
}

HomeworkType effectiveHomeworkType(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  if (parseLocalReminderAssessment(
        homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
        knownSubjects,
      ) !=
      null) {
    return HomeworkType.gradeGroup;
  }
  return homework.type;
}

bool isLocalReminderAssessmentHomework(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  return parseLocalReminderAssessment(
        homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
        knownSubjects,
      ) !=
      null;
}

String displayedHomeworkTitle(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  final parsed = parseLocalReminderAssessment(
    homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
    knownSubjects,
  );
  return parsed?.displayTitle ?? homework.title;
}

String displayedHomeworkSubtitle(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  final parsed = parseLocalReminderAssessment(
    homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
    knownSubjects,
  );
  return parsed?.displaySubtitle ?? homework.subtitle;
}

String? displayedHomeworkLabel(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  final parsed = parseLocalReminderAssessment(
    homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
    knownSubjects,
  );
  return parsed?.displayLabel ?? homework.label;
}

String? displayedHomeworkLabelForDate(
  AppState state,
  UtcDateTime date,
  Homework homework, [
  Iterable<String>? knownSubjects,
]) {
  final subjects = knownSubjects ?? state.extractAllSubjects();
  final parsed = parseLocalReminderAssessment(
    homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
    subjects,
  );
  final displayLabel = parsed?.displayLabel ?? homework.label;
  if (displayLabel != null && displayLabel.isNotEmpty) {
    return displayLabel;
  }
  if (parsed == null || parsed.period == null) {
    return displayLabel;
  }
  return _projectedSubjectForLocalReminderAssessment(state, date, parsed);
}

bool displayedHomeworkWarning(
  Homework homework,
  Iterable<String> knownSubjects,
) {
  final parsed = parseLocalReminderAssessment(
    homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
    knownSubjects,
  );
  return parsed != null || homework.warning;
}

bool isLocalReminderAssessmentHomeworkExam(HomeworkExam homeworkExam) {
  return homeworkExam.id < 0 &&
      homeworkExam.typeId < 0 &&
      !homeworkExam.homework;
}

bool localReminderAssessmentHasCalendarSlot(
  AppState state,
  UtcDateTime date,
  LocalReminderAssessment parsed,
) {
  final baseHours = state.calendarState.days[date]?.hours;
  if (baseHours == null || baseHours.isEmpty) {
    return false;
  }
  return _findProjectionTargetHour(baseHours: baseHours, parsed: parsed) !=
      null;
}

CalendarDay? calendarDayWithLocalReminderAssessments(
  AppState state,
  UtcDateTime date,
) {
  return _mergeLocalReminderAssessmentsIntoCalendarDay(
    state,
    date,
    state.calendarState.days[date],
  );
}

List<CalendarDay> calendarDaysForWeekWithLocalReminderAssessments(
  AppState state,
  UtcDateTime monday,
) {
  final weekEnd = monday.add(const Duration(days: 7));
  final dates = <UtcDateTime>{
    for (final day in state.calendarState.daysForWeek(monday))
      UtcDateTime(day.date.year, day.date.month, day.date.day),
  };
  for (final day in state.dashboardState.allDays ?? const <Day>[]) {
    final date = UtcDateTime(day.date.year, day.date.month, day.date.day);
    if (!date.isBefore(monday) && date.isBefore(weekEnd)) {
      if (day.homework.any(
        (homework) {
          final parsed = parseLocalReminderAssessment(
            homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
            state.extractAllSubjects(),
          );
          return parsed != null &&
              parsed.period != null &&
              localReminderAssessmentHasCalendarSlot(state, date, parsed);
        },
      )) {
        dates.add(date);
      }
    }
  }

  final result = dates
      .map((date) => _mergeLocalReminderAssessmentsIntoCalendarDay(
            state,
            date,
            state.calendarState.days[date],
          ))
      .whereType<CalendarDay>()
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return result;
}

List<LocalReminderAssessmentSuggestion> localReminderAssessmentSuggestions(
  String input,
) {
  final trimmed = input.trimLeft();
  if (!trimmed.startsWith('/')) {
    return const <LocalReminderAssessmentSuggestion>[];
  }

  final token = trimmed.substring(1).split(RegExp(r'\s+')).first.toLowerCase();
  return _defaultLocalReminderAssessmentCommands.entries
      .where(
        (entry) =>
            token.isEmpty ||
            entry.value.startsWith(token) ||
            entry.key.name.startsWith(token),
      )
      .map(
        (entry) => LocalReminderAssessmentSuggestion(
          type: entry.key,
          command: entry.value,
        ),
      )
      .toList(growable: false);
}

String applyLocalReminderAssessmentSuggestion(
  String input,
  LocalReminderAssessmentSuggestion suggestion,
) {
  final leadingWhitespaceMatch = RegExp(r'^\s*').firstMatch(input);
  final leadingWhitespace = leadingWhitespaceMatch?.group(0) ?? '';
  final trimmedLeft = input.substring(leadingWhitespace.length);
  final remainder = trimmedLeft.replaceFirst(RegExp(r'^/[^\s]*\s*'), '');
  final replacement = '$leadingWhitespace/${suggestion.command}@';
  return remainder.isEmpty ? replacement : '$replacement $remainder';
}

CalendarDay? _mergeLocalReminderAssessmentsIntoCalendarDay(
  AppState state,
  UtcDateTime date,
  CalendarDay? baseDay,
) {
  final localAssessments =
      <({Homework homework, LocalReminderAssessment parsed})>[];
  for (final day in state.dashboardState.allDays ?? const <Day>[]) {
    if (day.date.stripTime() != date.stripTime()) {
      continue;
    }
    for (final homework in day.homework) {
      final parsedMaybe = parseLocalReminderAssessment(
        homework.subtitle.isNotEmpty ? homework.subtitle : homework.title,
        state.extractAllSubjects(),
      );
      if (parsedMaybe == null || parsedMaybe.period == null) {
        continue;
      }
      final parsed = parsedMaybe;
      localAssessments.add((homework: homework, parsed: parsed));
    }
  }

  if (localAssessments.isEmpty) {
    return baseDay;
  }

  final hours = baseDay?.hours.toList() ?? <CalendarHour>[];

  for (final assessment in localAssessments) {
    final targetHourIndex = _findProjectionTargetHour(
      baseHours: BuiltList<CalendarHour>(hours),
      parsed: assessment.parsed,
    );
    if (targetHourIndex == null) {
      continue;
    }

    final localExam = HomeworkExam(
      (b) => b
        ..id = -assessment.homework.id.abs()
        ..name = assessment.parsed.calendarName
        ..homework = false
        ..online = false
        ..deadline = date
        ..hasGrades = false
        ..hasGradeGroupSubmissions = false
        ..typeId = -(assessment.parsed.type.index + 1)
        ..typeName = assessment.parsed.serverTypeName
        ..warning = true,
    );

    hours[targetHourIndex] = hours[targetHourIndex].rebuild(
      (b) => b.homeworkExams.add(localExam),
    );
  }

  hours.sort((a, b) => a.fromHour.compareTo(b.fromHour));

  return CalendarDay(
    (b) => b
      ..date = date
      ..hours = ListBuilder<CalendarHour>(hours)
      ..lastFetched = baseDay?.lastFetched,
  );
}

int? _findProjectionTargetHour({
  required BuiltList<CalendarHour> baseHours,
  required LocalReminderAssessment parsed,
}) {
  final period = parsed.period;
  if (period == null) {
    return null;
  }

  final exactSubjectMatch = baseHours.indexWhere(
    (hour) =>
        hour.fromHour <= period &&
        hour.toHour >= period &&
        equalsIgnoreCase(hour.subject, parsed.calendarSubject),
  );
  if (exactSubjectMatch != -1) {
    return exactSubjectMatch;
  }

  final matchingPeriod = baseHours.indexWhere(
    (hour) => hour.fromHour <= period && hour.toHour >= period,
  );
  if (matchingPeriod != -1) {
    return matchingPeriod;
  }

  return null;
}

String? _projectedSubjectForLocalReminderAssessment(
  AppState state,
  UtcDateTime date,
  LocalReminderAssessment parsed,
) {
  final baseHours = state.calendarState.days[date]?.hours;
  if (baseHours == null || baseHours.isEmpty) {
    return null;
  }
  final targetHourIndex = _findProjectionTargetHour(
    baseHours: baseHours,
    parsed: parsed,
  );
  if (targetHourIndex == null) {
    return null;
  }
  final subject = baseHours[targetHourIndex].subject.trim();
  return subject.isEmpty ? null : subject;
}

String? _findMatchingSubject(String input, Iterable<String> knownSubjects) {
  final normalizedInput = input.trim();
  if (normalizedInput.isEmpty) {
    return null;
  }

  final sortedSubjects = knownSubjects.toSet().toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final subject in sortedSubjects) {
    if (!_startsWithIgnoreCase(normalizedInput, subject)) {
      continue;
    }
    if (normalizedInput.length == subject.length) {
      return subject;
    }
    final nextChar = normalizedInput[subject.length];
    if (RegExp(r'[\s:;,\-]').hasMatch(nextChar)) {
      return subject;
    }
  }
  return null;
}

bool _startsWithIgnoreCase(String input, String prefix) {
  if (prefix.length > input.length) {
    return false;
  }
  return input.substring(0, prefix.length).toLowerCase() ==
      prefix.toLowerCase();
}
