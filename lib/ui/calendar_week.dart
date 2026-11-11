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
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

const holidayIconSize = 65.0;

class CalendarWeek extends StatelessWidget {
  final CalendarWeekViewModel vm;
  final String? favoriteSubject;
  final bool loading;
  final VoidCallback? onRetry;

  const CalendarWeek({
    super.key,
    required this.vm,
    required this.favoriteSubject,
    this.loading = true,
    this.onRetry,
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
    if (ResponsiveNavigationScope.isActive(context)) {
      return _GlassWeek(
        vm: vm,
        displayedDays: displayedDays,
        latestHour: latestHour,
        loading: loading,
        onRetry: onRetry,
      );
    }
    return vm.days.isEmpty
        ? vm.noInternet
            ? const NoInternet()
            : loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(context.t('calendar.noWeekData'),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('calendar-retry-week'),
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: Text(context.t('calendar.retry')),
                        ),
                      ]),
                    ),
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
                  : Theme.of(context).colorScheme.outline,
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
                              ? AppPalette.subjectTint(
                                  Color(
                                    subjectThemes[displayHours[n ~/ 2].subject]!
                                        .color,
                                  ),
                                  Theme.of(context).colorScheme,
                                  0.25,
                                )
                              : Colors.transparent)
                          : Colors.transparent,
                      selectedBackgroundColor: colorBackground
                          ? (subjectThemes[displayHours[n ~/ 2].subject] != null
                              ? AppPalette.subjectTint(
                                  Color(
                                    subjectThemes[displayHours[n ~/ 2].subject]!
                                        .color,
                                  ),
                                  Theme.of(context).colorScheme,
                                  0.5,
                                )
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
                (existing) =>
                    equalsIgnoreCase(existing.fullName, teacher.fullName),
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
  if (previous.classId != next.classId ||
      previous.className != next.className) {
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
    final today = Day.dateToday();
    final isToday = calendarDay.date == today;
    final colorScheme = Theme.of(context).colorScheme;
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
        Container(
          key: isToday ? const Key('calendar-today-indicator') : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: isToday
              ? BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Column(
            children: [
              Text(
                context.l10n.capitalize(
                  DateFormat("E", localeTag).format(calendarDay.date),
                ),
                style: isToday
                    ? TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      )
                    : null,
              ),
              Text(
                DateFormat("dd.MM", localeTag).format(calendarDay.date),
                style: DefaultTextStyle.of(context).style.copyWith(
                      fontSize: 12,
                      color: isToday ? colorScheme.onPrimaryContainer : null,
                    ),
              ),
            ],
          ),
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
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.exam, width: 5)
                    : BorderSide.none,
                right: hour.isDetectedSubstitute
                    ? const BorderSide(
                        color: AppPalette.markerWarning, width: 5)
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

/// The height of one line of [style] at the text scale of [context].
double _lineHeight(BuildContext context, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ág', style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// The week of the new design: the days side by side, their lessons on light
/// glass, state cards in place of the week when there is nothing to show.
class _GlassWeek extends StatelessWidget {
  const _GlassWeek({
    required this.vm,
    required this.displayedDays,
    required this.latestHour,
    required this.loading,
    required this.onRetry,
  });

  final CalendarWeekViewModel vm;
  final List<_DisplayedCalendarDay> displayedDays;
  final int latestHour;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (vm.days.isEmpty) {
      if (vm.noInternet) {
        return GlassStateCard(
          key: const Key('calendar-week-offline'),
          icon: Icons.wifi_off_rounded,
          title: l10n.text('offline.title'),
          body: l10n.text('offline.body'),
          actionLabel: l10n.text('calendar.retry'),
          onAction: onRetry,
        );
      }
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return GlassStateCard(
        key: const Key('calendar-retry-week'),
        icon: Icons.event_busy_rounded,
        title: l10n.text('calendar.noWeekData'),
        body: l10n.text('offline.retryLater'),
        actionLabel: l10n.text('calendar.retry'),
        onAction: onRetry,
      );
    }
    final UtcDateTime? lastFetched = vm.days.first.lastFetched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vm.noInternet)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassOfflineHint(
              key: const Key('calendar-last-fetched'),
              message: lastFetched == null
                  ? l10n.text('offline.title')
                  : l10n.text(
                      'grades.offlineMode',
                      args: {'time': l10n.formatTimeAgo(lastFetched)},
                    ),
              onRetry: onRetry ?? () {},
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final displayedDay in displayedDays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _GlassDay(
                      calendarDay: displayedDay.day,
                      max: latestHour,
                      subjectNicks: vm.subjectNicks,
                      isSelected: vm.selection?.date == displayedDay.day.date,
                      selectedHour: vm.selection?.date == displayedDay.day.date
                          ? vm.selection?.hour
                          : null,
                      colorBackground: vm.colorBackground,
                      subjectThemes: vm.subjectThemes,
                      showNoFavoriteSubject: displayedDay.showNoFavoriteSubject,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day of [_GlassWeek]: its name and date, then its lessons where they
/// fall in the day.
class _GlassDay extends StatelessWidget {
  const _GlassDay({
    required this.max,
    required this.calendarDay,
    required this.subjectNicks,
    required this.isSelected,
    required this.selectedHour,
    required this.colorBackground,
    required this.subjectThemes,
    required this.showNoFavoriteSubject,
  });

  final int max;
  final CalendarDay calendarDay;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final int? selectedHour;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;
  final bool showNoFavoriteSubject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final isToday = calendarDay.date == Day.dateToday();
    final chunks = <List<CalendarHour>>[];
    for (final hour in calendarDay.hours) {
      if (chunks.isEmpty || chunks.last.last.toHour + 1 < hour.fromHour) {
        chunks.add([hour]);
      } else {
        chunks.last.add(hour);
      }
    }
    final headerColor =
        isToday ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: Container(
            key: isToday ? const Key('calendar-today-indicator') : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: isToday
                ? ShapeDecoration(
                    color: scheme.primaryContainer,
                    shape: const StadiumBorder(),
                  )
                : null,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.capitalize(
                      DateFormat("E", localeTag).format(calendarDay.date),
                    ),
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isToday ? headerColor : scheme.onSurface,
                    ),
                  ),
                  Text(
                    DateFormat("dd.MM", localeTag).format(calendarDay.date),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: headerColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: chunks.isEmpty
              ? _GlassFreeDay(
                  date: calendarDay.date,
                  noFavoriteSubject: showNoFavoriteSubject,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < chunks.length; i++) ...[
                      Expanded(
                        flex: chunks[i].first.fromHour -
                            (i == 0 ? 0 : chunks[i - 1].last.toHour) -
                            1,
                        child: const SizedBox.shrink(),
                      ),
                      Expanded(
                        flex: chunks[i].last.toHour -
                            chunks[i].first.fromHour +
                            1,
                        child: _GlassHoursChunk(
                          hours: chunks[i],
                          subjectNicks: subjectNicks,
                          day: calendarDay,
                          selectedHour: selectedHour,
                          isSelected: isSelected,
                          colorBackground: colorBackground,
                          subjectThemes: subjectThemes,
                        ),
                      ),
                    ],
                    Expanded(
                      flex: max - calendarDay.toHour,
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A day without lessons, or without lessons of the chosen subject.
class _GlassFreeDay extends StatelessWidget {
  const _GlassFreeDay({required this.date, required this.noFavoriteSubject});

  final UtcDateTime date;
  final bool noFavoriteSubject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxHeight * 0.3).clamp(24.0, 48.0);
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: iconSize,
                    child: noFavoriteSubject
                        ? Icon(
                            Icons.filter_alt_off_rounded,
                            size: iconSize,
                            color: color,
                          )
                        : findHolidayIconForSeason(date, color, iconSize),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.t(
                      noFavoriteSubject
                          ? 'settings.calendar.noFavoriteSubject'
                          : 'calendar.freeDay',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lessons that follow each other without a gap, on one card.
class _GlassHoursChunk extends StatelessWidget {
  const _GlassHoursChunk({
    required this.subjectNicks,
    required this.hours,
    required this.day,
    required this.selectedHour,
    required this.isSelected,
    required this.colorBackground,
    required this.subjectThemes,
  });

  final BuiltMap<String, String> subjectNicks;
  final List<CalendarHour> hours;
  final CalendarDay day;
  final int? selectedHour;
  final bool isSelected;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayHours = _mergeDisplayHours(hours);
    final selectedFallback = scheme.primary.withValues(alpha: 0.14);
    Color? tint(CalendarHour hour, double amount) {
      final theme = subjectThemes[hour.subject];
      if (!colorBackground || theme == null) return null;
      return AppPalette.subjectTint(Color(theme.color), scheme, amount);
    }

    return Container(
      foregroundDecoration: isSelected
          ? ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius: DesignTokens.cardBorderRadius,
                side: BorderSide(color: scheme.primary, width: 1.5),
              ),
            )
          : null,
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: DesignTokens.cardBorderRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < displayHours.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                _GlassHour(
                  hour: displayHours[i],
                  subjectNicks: subjectNicks,
                  day: day,
                  isSelected: selectedHour != null &&
                      displayHours[i].fromHour <= selectedHour! &&
                      displayHours[i].toHour >= selectedHour!,
                  backgroundColor:
                      tint(displayHours[i], 0.25) ?? Colors.transparent,
                  selectedBackgroundColor:
                      tint(displayHours[i], 0.5) ?? selectedFallback,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One lesson of the week: its subject and as many of its teachers as fit.
/// When the cell gets very small, as on a phone held sideways, the subject
/// shrinks to its height and is cut off with an ellipsis, never mid-glyph.
class _GlassHour extends StatelessWidget {
  const _GlassHour({
    required this.hour,
    required this.subjectNicks,
    required this.day,
    required this.isSelected,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
  });

  static const _shape = RoundedRectangleBorder();

  final CalendarHour hour;
  final CalendarDay day;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final Color backgroundColor;
  final Color selectedBackgroundColor;

  void _select() {
    actions.calendarActions.select(
      CalendarSelection((b) => b
        ..date = day.date
        ..hour = hour.fromHour),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subject = subjectNicks[hour.subject.toLowerCase()] ??
        context.l10n.translateSubjectName(hour.subject);
    final teachers = [for (final teacher in hour.teachers) teacher.lastName];
    final subjectStyle = theme.textTheme.labelMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final teacherStyle = theme.textTheme.labelSmall!.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Flexible(
      flex: hour.length,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: [subject, ...teachers].join(', '),
        onTap: _select,
        excludeSemantics: true,
        child: GlassFocusRing(
          shape: _shape,
          activeTint: scheme.onSurface.withValues(alpha: 0.05),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _select,
              mouseCursor: NewDesignTheme.clickCursor,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isSelected ? selectedBackgroundColor : backgroundColor,
                  border: Border(
                    left: hour.warning
                        ? BorderSide(color: scheme.exam, width: 4)
                        : BorderSide.none,
                    right: hour.isDetectedSubstitute
                        ? BorderSide(color: scheme.warning, width: 4)
                        : BorderSide.none,
                  ),
                ),
                child: SizedBox.expand(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: LayoutBuilder(
                      builder: (context, constraints) => _content(
                        context,
                        constraints,
                        subject: subject,
                        teachers: teachers,
                        subjectStyle: subjectStyle,
                        teacherStyle: teacherStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    BoxConstraints constraints, {
    required String subject,
    required List<String> teachers,
    required TextStyle subjectStyle,
    required TextStyle teacherStyle,
  }) {
    final subjectHeight = _lineHeight(context, subjectStyle);
    if (constraints.maxHeight < subjectHeight) {
      // Smaller rather than cut through the letters.
      final fontSize = subjectStyle.fontSize!;
      final scale = MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
      return Center(
        child: Text(
          subject,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.linear(
            scale * 0.98 * constraints.maxHeight / subjectHeight,
          ),
          style: subjectStyle,
        ),
      );
    }
    final teacherHeight = _lineHeight(context, teacherStyle);
    var room = constraints.maxHeight - subjectHeight - 2;
    final shown = <String>[];
    for (final teacher in teachers) {
      if (room < teacherHeight) break;
      shown.add(teacher);
      room -= teacherHeight;
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          subject,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: subjectStyle,
        ),
        if (shown.isNotEmpty) const SizedBox(height: 2),
        for (final teacher in shown)
          Text(
            teacher,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: teacherStyle,
          ),
      ],
    );
  }
}
