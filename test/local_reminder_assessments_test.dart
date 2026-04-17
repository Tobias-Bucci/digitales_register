import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/local_reminder_assessments.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 9));
  });

  tearDown(resetTestState);

  test('parses local classwork reminder command with period and subject', () {
    final parsed = parseLocalReminderAssessment(
      '/cw@5 Italienisch Schularbeit',
      <String>['Italienisch', 'Deutsch'],
    );

    expect(parsed, isNotNull);
    expect(parsed!.type, LocalReminderAssessmentType.classwork);
    expect(parsed.period, 5);
    expect(parsed.subject, 'Italienisch');
    expect(parsed.displayTitle, 'Schularbeit');
    expect(parsed.displaySubtitle, isNull);
  });

  test('keeps self-created assessments without period out of the calendar', () {
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 15,
                title: 'Reminder',
                subtitle: '/exam Italienisch Mündliche Prüfung',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );

    final merged = calendarDayWithLocalReminderAssessments(
      state,
      UtcDateTime(2026, 4, 10),
    );

    expect(merged, isNull);
  });

  test('projects local reminder assessments into the matching calendar hour',
      () {
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 15,
                title: 'Reminder',
                subtitle: '/exam@2 Italienisch Mündliche Prüfung',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Italienisch',
                fromHour: 2,
                toHour: 2,
              ),
            ],
          ),
        });
      },
    );

    final merged = calendarDayWithLocalReminderAssessments(
      state,
      UtcDateTime(2026, 4, 10),
    );

    expect(merged, isNotNull);
    expect(merged!.hours.single.homeworkExams, hasLength(1));
    expect(merged.hours.single.homeworkExams.single.name, 'Mündliche Prüfung');
    expect(
      isLocalReminderAssessmentHomeworkExam(
        merged.hours.single.homeworkExams.single,
      ),
      isTrue,
    );
  });

  test('calendar sync exports local reminder assessments with period',
      () async {
    final l10n = await AppLocalizations.load(AppLanguage.en.locale);
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 15,
                title: 'Reminder',
                subtitle: '/test@3 Italienisch Grammar quiz',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
        b.gradesState.subjects = ListBuilder<Subject>(<Subject>[
          buildSubject(name: 'Italienisch'),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Italienisch',
                fromHour: 3,
                toHour: 3,
              ),
            ],
          ),
        });
      },
    );

    final items = CalendarSyncService.collectDesiredItems(state, l10n);

    expect(items, hasLength(1));
    expect(items.single.title, 'Grammar quiz');
    expect(items.single.description, contains('Test'));
    expect(items.single.description, contains('Italienisch'));
  });

  test('calendar sync skips local reminder assessments without period',
      () async {
    final l10n = await AppLocalizations.load(AppLanguage.en.locale);
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 15,
                title: 'Reminder',
                subtitle: '/test Italienisch Grammar quiz',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );

    final items = CalendarSyncService.collectDesiredItems(state, l10n);

    expect(items, isEmpty);
  });

  test('suggestions append a period marker automatically', () {
    final result = applyLocalReminderAssessmentSuggestion(
      '/te Italienisch Schularbeit',
      const LocalReminderAssessmentSuggestion(
        type: LocalReminderAssessmentType.test,
        command: 'test',
      ),
    );

    expect(result, '/test@ Italienisch Schularbeit');
  });

  test('rejects invalid period syntax for calendar projection', () {
    expect(
      parseLocalReminderAssessment(
          '@test@3 Italienisch', <String>['Italienisch']),
      isNull,
    );
    expect(
      parseLocalReminderAssessment(
          '/test@x Italienisch', <String>['Italienisch']),
      isNull,
    );
    expect(
      parseLocalReminderAssessment(
          '/test@0 Italienisch', <String>['Italienisch']),
      isNull,
    );
    expect(
      parseLocalReminderAssessment(
          '/test@-1 Italienisch', <String>['Italienisch']),
      isNull,
    );
  });

  test('does not project local reminder assessments into missing periods', () {
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 16,
                title: 'Reminder',
                subtitle: '/test@100 Italienisch Grammar quiz',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Italienisch',
                fromHour: 2,
                toHour: 2,
              ),
            ],
          ),
        });
      },
    );

    final merged = calendarDayWithLocalReminderAssessments(
      state,
      UtcDateTime(2026, 4, 10),
    );

    expect(merged, isNotNull);
    expect(merged!.hours.single.homeworkExams, isEmpty);
  });

  test('projects local reminder assessments into an existing double period',
      () {
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 17,
                title: 'Reminder',
                subtitle: '/cw@3 Italienisch Schularbeit',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Italienisch',
                fromHour: 2,
                toHour: 3,
              ),
            ],
          ),
        });
      },
    );

    final merged = calendarDayWithLocalReminderAssessments(
      state,
      UtcDateTime(2026, 4, 10),
    );

    expect(merged, isNotNull);
    expect(merged!.hours.single.fromHour, 2);
    expect(merged.hours.single.toHour, 3);
    expect(merged.hours.single.homeworkExams, hasLength(1));
    expect(merged.hours.single.homeworkExams.single.typeName, 'Schularbeit');
  });

  test('calendar week view model includes local reminder assessments', () {
    final monday = UtcDateTime(2026, 4, 6);
    final date = UtcDateTime(2026, 4, 10);
    final state = AppState(
      (b) {
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: date,
            homework: <Homework>[
              buildHomework(
                id: 18,
                title: 'Reminder',
                subtitle: '/test@2 Italienisch Grammar quiz',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          date: buildCalendarDay(
            date: date,
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Italienisch',
                fromHour: 2,
                toHour: 2,
              ),
            ],
          ),
        });
      },
    );

    final vm = CalendarWeekViewModel.fromStateAndWeek(state, monday);

    expect(vm.days, hasLength(1));
    expect(vm.days.single.hours.single.warning, isTrue);
    expect(vm.days.single.hours.single.homeworkExams, hasLength(1));
  });
}
