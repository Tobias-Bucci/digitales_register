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

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:collection/collection.dart';

import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

final calendarReducerBuilder = NestedReducerBuilder<AppState, AppStateBuilder,
    CalendarState, CalendarStateBuilder>(
  (s) => s.calendarState,
  (b) => b.calendarState,
)
  ..add(CalendarActionsNames.loaded, _loaded)
  ..add(CalendarActionsNames.setCurrentMonday, _currentMonday)
  ..add(CalendarActionsNames.select, _selectedDay)
  ..add(CalendarActionsNames.recalculateSubstitutes, _recalculateSubstitutes)
  ..add(CalendarActionsNames.onDownloadFile, _downloadFile)
  ..add(CalendarActionsNames.fileAvailable, _fileAvailable);

void _loaded(CalendarState state, Action<CalendarLoadedPayload> action,
    CalendarStateBuilder builder) {
  final loadedDays = action.payload.data.map(
    (k, dynamic e) {
      final date = UtcDateTime.parse(k);
      return MapEntry(
        date,
        tryParse<CalendarDayBuilder, dynamic>(
          e,
          (dynamic e) => _parseCalendarDay(
            getMap(getMap(e)!.values.first.values.first)!,
            date,
            state.days[date],
          ),
        ).build(),
      );
    },
  );
  final mergedDays = Map<UtcDateTime, CalendarDay>.from(state.days.toMap())
    ..addAll(loadedDays);
  builder.days.replace(_detectSubstitutes(mergedDays, action.payload.config));
}

void _currentMonday(CalendarState state, Action<UtcDateTime> action,
    CalendarStateBuilder builder) {
  builder.currentMonday = action.payload;
}

void _selectedDay(CalendarState state, Action<CalendarSelection?> action,
    CalendarStateBuilder builder) {
  builder.selection = action.payload?.toBuilder();
}

void _recalculateSubstitutes(
    CalendarState state,
    Action<SubstituteDetectionConfig> action,
    CalendarStateBuilder builder) {
  builder.days.replace(
    _detectSubstitutes(
      state.days.toMap(),
      action.payload,
    ),
  );
}

CalendarDayBuilder _parseCalendarDay(
  Map day,
  UtcDateTime date,
  CalendarDay? oldDay,
) {
  return CalendarDayBuilder()
    ..lastFetched = UtcDateTime.now()
    ..date = date
    ..hours = ListBuilder(
      (day.values.toList()
            ..removeWhere((dynamic e) => e == null || e["isLesson"] == 0)
            ..sort(
              (dynamic a, dynamic b) => getInt(a["hour"])!.compareTo(
                getInt(b["hour"])!,
              ),
            ))
          .map<CalendarHour>(
        (dynamic h) => tryParse(
          getMap(h)!,
          (Map map) => _parseHour(
            map,
            date,
            oldDay,
          ),
        ).build(),
      ),
    );
}

CalendarHourBuilder _parseHour(
  Map hour,
  UtcDateTime date,
  CalendarDay? oldDay,
) {
  final lesson = getMap(hour["lesson"])!;
  final timeSpans = ListBuilder<TimeSpan>();
  for (final linkedLesson in <dynamic>[
    lesson,
    ...getList(lesson["linkedHours"]) ?? <dynamic>[],
  ]) {
    final date = tryParse(
      getString(linkedLesson["date"])!,
      (String s) => UtcDateTime.parse(s),
    );
    UtcDateTime parseTime(UtcDateTime date, Map timeObject) {
      final h = getInt(timeObject["h"])!;
      final m = getInt(timeObject["m"])!;
      return UtcDateTime(date.year, date.month, date.day, h, m);
    }

    final from = parseTime(date, getMap(linkedLesson["timeStartObject"])!);
    final to = parseTime(date, getMap(linkedLesson["timeEndObject"])!);

    timeSpans.add(
      TimeSpan(
        (b) => b
          ..from = from
          ..to = to,
      ),
    );
  }

  final fromHour = getInt(lesson["hour"])!;
  final toHour = getInt(lesson["toHour"])!;

  final oldHour = oldDay?.hours.firstWhereOrNull(
    (hour) =>
        (hour.fromHour <= fromHour && hour.toHour >= toHour) ||
        (hour.fromHour >= fromHour && hour.toHour <= toHour),
  );

  return CalendarHourBuilder()
    ..fromHour = fromHour
    ..toHour = toHour
    ..classId = getInt(lesson["classId"])
    ..className = getString(lesson["className"])
    ..subjectId = getInt(lesson["subject"]["id"])
    ..timeSpans = timeSpans
    ..rooms = ListBuilder(
      getList(lesson["rooms"])!.map<String>((dynamic r) => r["name"] as String),
    )
    ..subject = getString(lesson["subject"]["name"])
    ..teachers = ListBuilder(
      getList(lesson["teachers"])!.map<Teacher>(
        (dynamic r) => Teacher((b) => b
          ..firstName = getString(r["firstName"])
          ..lastName = getString(r["lastName"])),
      ),
    )
    ..homeworkExams = ListBuilder(
      (lesson["homeworkExams"] as List).map<HomeworkExam>(
          (dynamic e) => tryParse(getMap(e)!, _parseHomeworkExam)),
    )
    ..lessonContents = ListBuilder(
      (lesson["lessonContents"] as List).map<LessonContent>(
        (dynamic e) => tryParse(
          getMap(e)!,
          (Map map) => _parseLessonContent(
            map,
            date,
            oldHour,
          ),
        ),
      ),
    );
}

Map<UtcDateTime, CalendarDay> _detectSubstitutes(
  Map<UtcDateTime, CalendarDay> days,
  dynamic settings,
) {
  if (!_substituteDetectionEnabled(settings)) {
    return {
      for (final entry in days.entries)
        entry.key: entry.value.rebuild(
          (day) => day.hours = ListBuilder<CalendarHour>(
            entry.value.hours.map(
              (hour) => hour.rebuild((b) => b.isDetectedSubstitute = false),
            ),
          ),
        ),
    };
  }

  final teacherCountsBySlot = <String, Map<String, int>>{};

  for (final entry in days.entries) {
    final date = entry.key;
    for (final hour in entry.value.hours) {
      final teacherSignature = _teacherSignature(hour.teachers);
      if (teacherSignature.isEmpty) {
        continue;
      }
      for (final slotKey in _slotKeysForHour(date, hour)) {
        final teacherCounts =
            teacherCountsBySlot.putIfAbsent(slotKey, () => <String, int>{});
        teacherCounts.update(
          teacherSignature,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  return {
    for (final entry in days.entries)
      entry.key: entry.value.rebuild(
        (day) => day.hours = ListBuilder<CalendarHour>(
          entry.value.hours.map(
            (hour) => hour.rebuild(
              (b) => b.isDetectedSubstitute =
                  _isDetectedSubstitute(
                entry.key,
                hour,
                teacherCountsBySlot,
                settings,
              ),
            ),
          ),
        ),
      ),
  };
}

bool _isDetectedSubstitute(
  UtcDateTime date,
  CalendarHour hour,
  Map<String, Map<String, int>> teacherCountsBySlot,
  dynamic settings,
) {
  if (hour.teachers.length != 1) {
    return false;
  }

  final teacherSignature = _teacherSignature(hour.teachers);
  if (teacherSignature.isEmpty) {
    return false;
  }
  if (_isConfiguredPrimaryTeacher(settings, hour, teacherSignature)) {
    return false;
  }

  for (final slotKey in _slotKeysForHour(date, hour)) {
    final teacherCounts = teacherCountsBySlot[slotKey];
    if (teacherCounts == null || teacherCounts.length < 2) {
      continue;
    }

    final sortedCounts = teacherCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final leader = sortedCounts.first;
    final runnerUpCount = sortedCounts.length > 1 ? sortedCounts[1].value : 0;
    final currentCount = teacherCounts[teacherSignature] ?? 0;
    final hasStableBaseline = leader.value >= 2 && leader.value > runnerUpCount;

    if (hasStableBaseline &&
        leader.key != teacherSignature &&
        leader.value > currentCount) {
      return true;
    }
  }

  return false;
}

bool _isConfiguredPrimaryTeacher(
  dynamic settings,
  CalendarHour hour,
  String teacherSignature,
) {
  for (final entry in _substitutePrimaryTeachers(settings).entries) {
    if (!equalsIgnoreCase(entry.key, hour.subject)) {
      continue;
    }
    return entry.value.any(
      (teacher) => equalsIgnoreCase(teacher, teacherSignature),
    );
  }
  return false;
}

bool _substituteDetectionEnabled(dynamic settings) {
  if (settings is SettingsState) {
    return settings.substituteDetectionEnabled;
  }
  if (settings is SubstituteDetectionConfig) {
    return settings.enabled;
  }
  throw ArgumentError.value(settings, 'settings');
}

BuiltMap<String, BuiltList<String>> _substitutePrimaryTeachers(
  dynamic settings,
) {
  if (settings is SettingsState) {
    return settings.substitutePrimaryTeachers;
  }
  if (settings is SubstituteDetectionConfig) {
    return settings.primaryTeachers;
  }
  throw ArgumentError.value(settings, 'settings');
}

List<String> _slotKeysForHour(UtcDateTime date, CalendarHour hour) {
  return [
    for (var lessonHour = hour.fromHour; lessonHour <= hour.toHour; lessonHour++)
      _slotKeyForLessonHour(date, hour, lessonHour),
  ];
}

String _slotKeyForLessonHour(
  UtcDateTime date,
  CalendarHour hour,
  int lessonHour,
) {
  final classPart = hour.classId?.toString() ?? hour.className ?? '';
  final subjectPart = hour.subjectId?.toString() ?? hour.subject;
  return '$classPart|$subjectPart|${date.weekday}|$lessonHour';
}

String _teacherSignature(BuiltList<Teacher> teachers) {
  return (teachers.toList()
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(
              b.fullName.toLowerCase(),
            )))
      .map((teacher) => teacher.fullName.toLowerCase())
      .join('|');
}

HomeworkExam _parseHomeworkExam(Map homeworkExam) {
  return HomeworkExam((b) => b
    ..deadline = UtcDateTime.parse(getString(homeworkExam["deadline"])!)
    ..hasGradeGroupSubmissions =
        getBool(homeworkExam["hasGradeGroupSubmissions"])
    ..hasGrades = getBool(homeworkExam["hasGrades"])
    ..warning = homeworkExam["homework"] == 0
    ..homework = homeworkExam["homework"] != 0
    ..id = getInt(homeworkExam["id"])
    ..name = getString(homeworkExam["name"])
    ..online = homeworkExam["online"] != 0
    ..typeId = getInt(homeworkExam["typeId"])
    ..typeName = getString(homeworkExam["typeName"]));
}

LessonContent _parseLessonContent(
    Map lessonContent, UtcDateTime date, CalendarHour? oldHour) {
  return LessonContent(
    (b) => b
      ..name = getString(lessonContent["name"])
      ..typeName = getString(lessonContent["typeName"])
      ..submissions = tryParse(
          getList(lessonContent["lessonContentSubmissions"]), (List? input) {
        return input
            ?.map(
              (dynamic submission) => _parseLessonContentSubmission(
                getMap(submission)!,
                date,
                oldHour,
              ),
            )
            .whereType<LessonContentSubmission>()
            .toBuiltList()
            .toBuilder();
      }),
  );
}

LessonContentSubmission? _parseLessonContentSubmission(
  Map submission,
  UtcDateTime date,
  CalendarHour? oldHour,
) {
  final type = getString(submission["type"]);
  if (type != "file") {
    return null;
  }
  final originalName = getString(submission["originalName"]);
  final id = getString(submission["id"]);
  final fileAvailable = oldHour?.lessonContents.any((content) =>
          content.submissions.any((submission) =>
              submission.originalName == originalName &&
              submission.id == id &&
              submission.fileAvailable)) ??
      false;

  return LessonContentSubmission(
    (b) => b
      ..type = type
      ..originalName = originalName
      ..id = id
      ..lessonContentId = getString(submission["lessonContentId"])
      ..date = date
      ..fileAvailable = fileAvailable,
  );
}

void _downloadFile(CalendarState state, Action<LessonContentSubmission> action,
    CalendarStateBuilder builder) {
  builder.days[action.payload.date] =
      builder.days[action.payload.date]!.rebuild(
    (b) => b
      ..hours = ListBuilder(
        <CalendarHour>[
          for (final hour in b.hours.build())
            hour.rebuild(
              (b) => b
                ..lessonContents = ListBuilder(
                  <LessonContent>[
                    for (final lessonContent in b.lessonContents.build())
                      lessonContent.rebuild(
                        (b) => b
                          ..submissions = ListBuilder(
                            <LessonContentSubmission>[
                              for (final submission in b.submissions.build())
                                if (submission.originalName ==
                                    action.payload.originalName)
                                  submission.rebuild(
                                    (b) => b..downloading = true,
                                  )
                                else
                                  submission
                            ],
                          ),
                      )
                  ],
                ),
            )
        ],
      ),
  );
}

void _fileAvailable(CalendarState state, Action<LessonContentSubmission> action,
    CalendarStateBuilder builder) {
  builder.days[action.payload.date] =
      builder.days[action.payload.date]!.rebuild(
    (b) => b
      ..hours = ListBuilder(
        <CalendarHour>[
          for (final hour in b.hours.build())
            hour.rebuild(
              (b) => b
                ..lessonContents = ListBuilder(
                  <LessonContent>[
                    for (final lessonContent in b.lessonContents.build())
                      lessonContent.rebuild(
                        (b) => b
                          ..submissions = ListBuilder(
                            <LessonContentSubmission>[
                              for (final submission in b.submissions.build())
                                if (submission.originalName ==
                                    action.payload.originalName)
                                  submission.rebuild(
                                    (b) => b
                                      ..downloading = false
                                      ..fileAvailable =
                                          action.payload.fileAvailable,
                                  )
                                else
                                  submission
                            ],
                          ),
                      )
                  ],
                ),
            )
        ],
      ),
  );
}
