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
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

const holidayIconSize = 65.0;

class CalendarWeek extends StatelessWidget {
  final CalendarWeekViewModel vm;
  final String? favoriteSubject;

  const CalendarWeek({
    super.key,
    required this.vm,
    required this.favoriteSubject,
  });

  @override
  Widget build(BuildContext context) {
    final latestHour =
        vm.days.fold<int>(0, (a, b) => a < b.toHour ? b.toHour : a);
    final displayedDays = vm.days.map(
      (day) {
        final filteredHours = favoriteSubject == null
            ? day.hours
            : BuiltList<CalendarHour>(
                day.hours.where(
                  (hour) =>
                      matchesFavoriteSubject(hour.subject, favoriteSubject!),
                ),
              );
        return _DisplayedCalendarDay(
          day: day.rebuild(
            (b) => b.hours.replace(filteredHours),
          ),
          showNoFavoriteSubject: favoriteSubject != null &&
              day.hours.isNotEmpty &&
              filteredHours.isEmpty,
        );
      },
    ).toList();
    return vm.days.isEmpty
        ? vm.noInternet
            ? const NoInternet()
            : const Center(
                child: CircularProgressIndicator(),
              )
        : LastFetchedOverlay(
            lastFetched: vm.days.first.lastFetched,
            noInternet: vm.noInternet,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: displayedDays
                        .map(
                          (displayedDay) => Expanded(
                            child: CalendarDayWidget(
                              calendarDay: displayedDay.day,
                              max: latestHour,
                              subjectNicks: vm.subjectNicks,
                              isSelected:
                                  vm.selection?.date == displayedDay.day.date,
                              selectedHour:
                                  vm.selection?.date == displayedDay.day.date
                                      ? vm.selection?.hour
                                      : null,
                              colorBackground: vm.colorBackground,
                              subjectThemes: vm.subjectThemes,
                              showNoFavoriteSubject:
                                  displayedDay.showNoFavoriteSubject,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
  }
}

class _DisplayedCalendarDay {
  final CalendarDay day;
  final bool showNoFavoriteSubject;

  const _DisplayedCalendarDay({
    required this.day,
    required this.showNoFavoriteSubject,
  });
}

class _HoursChunk extends StatelessWidget {
  final BuiltMap<String, String> subjectNicks;
  final List<CalendarHour> hours;
  final CalendarDay day;
  final int? selectedHour;
  final bool isSelected;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  const _HoursChunk({
    required this.subjectNicks,
    required this.hours,
    required this.day,
    required this.selectedHour,
    required this.isSelected,
    required this.colorBackground,
    required this.subjectThemes,
  });

  @override
  Widget build(BuildContext context) {
    final displayHours = _mergeDisplayHours(hours);
    return Stack(
      children: <Widget>[
        Card(
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.secondary
                  : Colors.grey,
              width: 0.75,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          color: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          child: Container(),
        ),
        Card(
          color: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: List.generate(
              displayHours.length * 2 - 1,
              (n) => n.isEven
                  ? HourWidget(
                      hour: displayHours[n ~/ 2],
                      subjectNicks: subjectNicks,
                      day: day,
                      isSelected: selectedHour != null &&
                          displayHours[n ~/ 2].fromHour <= selectedHour! &&
                          displayHours[n ~/ 2].toHour >= selectedHour!,
                      backgroundColor: colorBackground
                          ? (subjectThemes[displayHours[n ~/ 2].subject] != null
                                  ? Color(
                                      subjectThemes[displayHours[n ~/ 2].subject]!
                                          .color,
                                    ).withValues(alpha: 0.25)
                                  : Colors.transparent)
                          : Colors.transparent,
                      selectedBackgroundColor: colorBackground
                          ? (subjectThemes[displayHours[n ~/ 2].subject] != null
                                  ? Color(
                                      subjectThemes[displayHours[n ~/ 2].subject]!
                                          .color,
                                    ).withValues(alpha: 0.5)
                                  : Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withAlpha(35))
                          : Theme.of(context)
                              .colorScheme
                              .secondary
                              .withAlpha(35),
                    )
                  : const Divider(
                      height: 0,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

List<CalendarHour> _mergeDisplayHours(List<CalendarHour> hours) {
  final merged = <CalendarHour>[];
  for (final hour in hours) {
    if (merged.isEmpty || !_canMergeDisplayHour(merged.last, hour)) {
      merged.add(hour);
      continue;
    }
    final previous = merged.removeLast();
    merged.add(
      previous.rebuild(
        (b) => b
          ..toHour = hour.toHour
          ..timeSpans = ListBuilder<TimeSpan>([
            ...previous.timeSpans,
            ...hour.timeSpans,
          ])
          ..teachers = ListBuilder<Teacher>([
            ...previous.teachers,
            for (final teacher in hour.teachers)
              if (!previous.teachers.any(
                (existing) => equalsIgnoreCase(existing.fullName, teacher.fullName),
              ))
                teacher,
          ])
          ..homeworkExams = ListBuilder<HomeworkExam>([
            ...previous.homeworkExams,
            ...hour.homeworkExams,
          ])
          ..lessonContents = ListBuilder<LessonContent>([
            ...previous.lessonContents,
            ...hour.lessonContents,
          ])
          ..isDetectedSubstitute =
              previous.isDetectedSubstitute || hour.isDetectedSubstitute,
      ),
    );
  }
  return merged;
}

bool _canMergeDisplayHour(CalendarHour previous, CalendarHour next) {
  if (previous.toHour + 1 != next.fromHour) {
    return false;
  }
  if (!equalsIgnoreCase(previous.subject, next.subject)) {
    return false;
  }
  if (previous.classId != next.classId || previous.className != next.className) {
    return false;
  }
  if (previous.subjectId != next.subjectId) {
    return false;
  }
  if (!_sameStringList(previous.rooms, next.rooms)) {
    return false;
  }
  return true;
}

bool _sameStringList(Iterable<String> a, Iterable<String> b) {
  final aList = a.toList();
  final bList = b.toList();
  if (aList.length != bList.length) {
    return false;
  }
  for (var i = 0; i < aList.length; i++) {
    if (!equalsIgnoreCase(aList[i], bList[i])) {
      return false;
    }
  }
  return true;
}


class CalendarDayWidget extends StatelessWidget {
  final int max;
  final CalendarDay calendarDay;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final int? selectedHour;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final bool showNoFavoriteSubject;

  const CalendarDayWidget({
    super.key,
    required this.max,
    required this.calendarDay,
    required this.subjectNicks,
    required this.isSelected,
    required this.selectedHour,
    required this.colorBackground,
    required this.subjectThemes,
    required this.showNoFavoriteSubject,
  });
  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final chunks = <List<CalendarHour>>[];
    for (final hour in calendarDay.hours) {
      if (chunks.isEmpty) {
        chunks.add([hour]);
      } else {
        final last = chunks.last;
        if (last.last.toHour + 1 < hour.fromHour) {
          chunks.add([hour]);
        } else {
          last.add(hour);
        }
      }
    }
    return Column(
      children: <Widget>[
        Text(
          context.l10n.capitalize(
            DateFormat("E", localeTag).format(calendarDay.date),
          ),
        ),
        Text(
          DateFormat("dd.MM", localeTag).format(calendarDay.date),
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
        ),
        if (chunks.isNotEmpty) ...[
          for (var i = 0; i < chunks.length; i++) ...[
            Expanded(
              flex: chunks[i].first.fromHour -
                  (i == 0 ? 0 : chunks[i - 1].last.toHour) -
                  1,
              child: Container(),
            ),
            Expanded(
              flex: chunks[i].last.toHour - chunks[i].first.fromHour + 1,
              child: _HoursChunk(
                hours: chunks[i],
                subjectNicks: subjectNicks,
                day: calendarDay,
                selectedHour: selectedHour,
                isSelected: isSelected,
                colorBackground: colorBackground,
                subjectThemes: subjectThemes,
              ),
            )
          ],
          Expanded(
            flex: max - calendarDay.toHour,
            child: Container(),
          )
        ] else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final iconSize =
                    (availableHeight * 0.6).clamp(36.0, holidayIconSize);
                if (showNoFavoriteSubject) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_alt_off_rounded,
                          size: iconSize,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.t('settings.calendar.noFavoriteSubject'),
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: iconSize,
                        width: iconSize,
                        child: findHolidayIconForSeason(
                          calendarDay.date,
                          Theme.of(context).iconTheme.color!,
                          iconSize,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t('calendar.freeDay'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class HourWidget extends StatelessWidget {
  final CalendarHour hour;
  final CalendarDay day;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final Color backgroundColor;
  final Color selectedBackgroundColor;

  const HourWidget({
    super.key,
    required this.hour,
    required this.subjectNicks,
    required this.day,
    required this.isSelected,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
  });
  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: hour.length,
      child: ClipRect(
        child: InkWell(
          onTap: () {
            actions.calendarActions.select(
              CalendarSelection((b) => b
                ..date = day.date
                ..hour = hour.fromHour),
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: hour.warning
                    ? const BorderSide(color: Colors.red, width: 5)
                    : BorderSide.none,
                right: hour.isDetectedSubstitute
                    ? BorderSide(color: Colors.amber.shade700, width: 5)
                    : BorderSide.none,
              ),
              color: isSelected ? selectedBackgroundColor : backgroundColor,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      subjectNicks[hour.subject.toLowerCase()] ??
                          context.l10n.translateSubjectName(hour.subject),
                      maxLines: 1,
                      softWrap: false,
                    ),
                    if (hour.teachers.isNotEmpty)
                      const SizedBox(
                        height: 5,
                      ),
                    for (final teacher in hour.teachers)
                      Text(
                        teacher.lastName,
                        maxLines: 1,
                        softWrap: false,
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(fontSize: 11),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _dateIsNear(UtcDateTime date1, UtcDateTime date2) {
  return date1.difference(date2).inDays.abs() <= 3;
}

Widget findHolidayIconForSeason(UtcDateTime date, Color color, double size) {
  // Weekends
  if (date.weekday >= 6) {
    return Icon(
      Icons.weekend,
      color: color,
      size: size,
    );
  }
  final month = date.month;
  final day = date.day;
  // Summer
  if (month >= 6 && month <= 9) {
    return Icon(
      Icons.beach_access,
      size: size,
      color: color,
    );
  }
  // Christmas
  if (month == 12 && day >= 22 || month == 1 && day <= 10) {
    return Icon(
      Icons.ac_unit_rounded,
      size: size,
      color: color,
    );
  }
  // Halloween
  if (month == 10 && day >= 24 || month == 11 && day <= 8) {
    return SvgPicture.asset(
      "assets/halloween.svg",
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      height: size,
      width: size,
    );
  }
  // Easter
  final easter = calculateEaster(date.year);
  if (_dateIsNear(date, easter)) {
    return SvgPicture.asset(
      "assets/easter.svg",
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      height: size,
      width: size,
    );
  }
  // Carnival
  final carnival = easter.subtract(const Duration(days: 47));
  if (_dateIsNear(date, carnival)) {
    return SvgPicture.asset(
      "assets/carnival.svg",
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      height: size,
      width: size,
    );
  }

  // Default
  return Icon(
    Icons.celebration,
    size: size,
    color: color,
  );
}

/// Calculate the date of easter
// https://en.wikipedia.org/wiki/Date_of_Easter#Meeus.27s_Julian_algorithm
UtcDateTime calculateEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final g = (8 * b + 13) ~/ 25;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 19 * l) ~/ 433;
  final n = (h + l - 7 * m + 90) ~/ 25;
  final p = (h + l - 7 * m + 33 * n + 19) % 32;
  return UtcDateTime(year, n, p);
}
