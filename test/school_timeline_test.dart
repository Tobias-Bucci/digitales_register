// Copyright (C) 2026 Tobias Bucci

import 'package:built_collection/built_collection.dart';
import 'package:dr/data.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  test('extracts and groups named holidays from existing dashboard data', () {
    final timeline = SchoolTimeline.fromCalendarData(
      dashboardDays: <Day>[
        buildDay(
          date: UtcDateTime(2025, 12, 24),
          homework: <Homework>[
            buildHomework(
              title: 'Sospensione delle lezioni',
              subtitle: 'Vacanze natalizie',
              type: HomeworkType.observation,
            ),
          ],
        ),
        buildDay(
          date: UtcDateTime(2025, 12, 25),
          homework: <Homework>[
            buildHomework(
              id: 2,
              title: 'Sospensione delle lezioni',
              subtitle: 'Vacanze natalizie',
              type: HomeworkType.observation,
            ),
          ],
        ),
      ],
      calendarDays: const <CalendarDay>[],
    );

    expect(timeline.holidays, hasLength(1));
    expect(timeline.holidays.single.name, 'Vacanze natalizie');
    expect(timeline.holidays.single.start, DateTime(2025, 12, 24));
    expect(timeline.holidays.single.end, DateTime(2025, 12, 25));
  });

  test(
      'uses empty weekdays from the calendar without treating weekends as holidays',
      () {
    CalendarDay calendarDay(DateTime date) => CalendarDay(
          (b) => b
            ..date = UtcDateTime.makeUtc(date)
            ..hours = ListBuilder<CalendarHour>(),
        );

    final timeline = SchoolTimeline.fromCalendarData(
      dashboardDays: const <Day>[],
      calendarDays: <CalendarDay>[
        calendarDay(DateTime(2026, 2, 14)), // Saturday
        calendarDay(DateTime(2026, 2, 16)), // Monday
      ],
    );

    expect(timeline.holidays, hasLength(1));
    expect(timeline.holidays.single.start, DateTime(2026, 2, 16));
    expect(timeline.holidays.single.end, DateTime(2026, 2, 16));
  });

  test('holiday countdown handles start, end, 0 and 100 percent', () {
    final timeline = SchoolTimeline(
      schoolYearStart: DateTime(2025, 9),
      holidays: <SchoolHoliday>[
        SchoolHoliday(
          name: 'Weihnachtsferien',
          start: DateTime(2025, 12, 24),
          end: DateTime(2026, 1, 5),
        ),
      ],
      gradeDeadlines: const <GradeDeadline>[],
    );

    final before = timeline.holidayCountdownAt(DateTime(2025, 9))!;
    expect(before.isOnHoliday, isFalse);
    expect(before.progress, 0);

    final firstDay = timeline.holidayCountdownAt(DateTime(2025, 12, 24))!;
    expect(firstDay.isOnHoliday, isTrue);
    expect(firstDay.progress, 0);
    expect(firstDay.remainingDays, 13);

    final lastDay = timeline.holidayCountdownAt(DateTime(2026, 1, 5))!;
    expect(lastDay.isOnHoliday, isTrue);
    expect(lastDay.progress, 1);
    expect(lastDay.remainingDays, 1);

    expect(timeline.holidayCountdownAt(DateTime(2026, 1, 6)), isNull);
  });

  test('grade deadline progress follows the two fixed grading periods', () {
    final timeline = SchoolTimeline(
      schoolYearStart: DateTime(2025, 9),
      holidays: const <SchoolHoliday>[],
      gradeDeadlines: <GradeDeadline>[
        GradeDeadline(name: '1. Notenschluss', date: DateTime(2026, 1, 20)),
        GradeDeadline(name: '2. Notenschluss', date: DateTime(2026, 5, 29)),
      ],
    );

    final beforeSchoolStart =
        timeline.gradeDeadlineCountdownAt(DateTime(2025, 8, 25))!;
    expect(beforeSchoolStart.periodStart, DateTime(2025, 9, 7));
    expect(beforeSchoolStart.progress, 0);

    final firstSchoolDay =
        timeline.gradeDeadlineCountdownAt(DateTime(2025, 9, 7))!;
    expect(firstSchoolDay.progress, 0);

    final today = timeline.gradeDeadlineCountdownAt(DateTime(2026, 1, 20))!;
    expect(today.remainingDays, 0);
    expect(today.progress, 1);

    final nextPeriod =
        timeline.gradeDeadlineCountdownAt(DateTime(2026, 1, 21))!;
    expect(nextPeriod.deadline.date, DateTime(2026, 5, 29));
    expect(nextPeriod.periodStart, DateTime(2026, 2, 1));
    expect(nextPeriod.progress, 0);

    expect(timeline.gradeDeadlineCountdownAt(DateTime(2026, 5, 30)), isNull);
  });

  test('supplies standard grading dates and keeps overrides per school year',
      () {
    const emptyTimeline = SchoolTimeline(
      schoolYearStart: null,
      holidays: <SchoolHoliday>[],
      gradeDeadlines: <GradeDeadline>[],
    );
    final defaults = emptyTimeline.withGradeDeadlineDefaults(
      DateTime(2026, 8, 29),
    );
    expect(
      defaults.gradeDeadlineCountdownAt(DateTime(2026, 8, 29))!.deadline.date,
      DateTime(2027, 1, 31),
    );

    final timeline = emptyTimeline.withGradeDeadlineDefaults(
      DateTime(2026, 8, 29),
      overrides: <String, DateTime>{
        gradeDeadlinePreferenceKey(2026, 1): DateTime(2027, 2, 2),
      },
    );

    final first = timeline.gradeDeadlineCountdownAt(DateTime(2026, 8, 29))!;
    expect(first.deadline.date, DateTime(2027, 2, 2));
    expect(first.deadline.preferenceKey, '2026:1');

    final second = timeline.gradeDeadlineCountdownAt(DateTime(2027, 2, 3))!;
    expect(second.deadline.date, DateTime(2027, 6, 5));
    expect(second.deadline.preferenceKey, '2026:2');
  });

  test('extracts multilingual grading deadline events', () {
    final timeline = SchoolTimeline.fromCalendarData(
      dashboardDays: <Day>[
        buildDay(
          date: UtcDateTime(2026, 5, 29),
          homework: <Homework>[
            buildHomework(
              title: 'Chiusura valutazioni',
              subtitle: 'Ultimo giorno per le valutazioni',
              type: HomeworkType.observation,
            ),
          ],
        ),
      ],
      calendarDays: const <CalendarDay>[],
    );

    expect(timeline.gradeDeadlines, hasLength(1));
    expect(timeline.gradeDeadlines.single.date, DateTime(2026, 5, 29));
  });
}
