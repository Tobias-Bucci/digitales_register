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
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/data.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

void main() {
  const methodChannel = MethodChannel('dr/calendar_sync');

  setUp(() async {
    await bootstrapTestEnvironment();
    isAndroidOverride = () => true;
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 41;
  });

  tearDown(resetTestState);

  test('reconcile imports current future dashboard and calendar items', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return upserts.length;
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Reminder',
                subtitle: 'Bring notebook',
                type: HomeworkType.homework,
              ),
              buildHomework(
                id: 8,
                title: 'Worksheet',
                subtitle: 'Page 12',
                label: 'Mathematics',
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Biology',
                homeworkExams: <HomeworkExam>[
                  buildHomeworkExam(
                    id: 22,
                    name: 'Chapter test',
                    homework: false,
                    typeName: 'Exam',
                    deadline: UtcDateTime(2026, 4, 11, 9),
                  ),
                ],
              ),
            ],
          ),
        });
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upserts, hasLength(3));
    expect(upserts.map((request) => request.title), containsAll(<String>[
      'Erinnerung',
      'Worksheet',
      'Chapter test',
    ]));
    expect(
      upserts.every(
        (request) => request.endMillisUtc - request.startMillisUtc ==
            const Duration(days: 1).inMilliseconds,
      ),
      isTrue,
    );
  });

  test('reconcile also imports existing dashboard schoolwork entries', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return upserts.length;
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 91,
                title: 'Schularbeit',
                subtitle: 'Kapitel 3 und 4',
                label: 'Deutsch',
                type: HomeworkType.gradeGroup,
              ),
            ],
          ),
        ]);
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upserts, hasLength(1));
    expect(upserts.single.title, 'Schularbeit');
    expect(upserts.single.description, contains('Kapitel 3 und 4'));
  });

  test('reconcile deduplicates dashboard schoolwork against matching calendar exams', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return upserts.length;
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 91,
                title: 'Schularbeit',
                subtitle: '1. Schularbeit',
                label: 'Deutsch',
                type: HomeworkType.gradeGroup,
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Deutsch',
                homeworkExams: <HomeworkExam>[
                  buildHomeworkExam(
                    id: 55,
                    name: '1. Schularbeit',
                    homework: false,
                    typeName: 'Schularbeit',
                    deadline: UtcDateTime(2026, 4, 10, 9),
                  ),
                ],
              ),
            ],
          ),
        });
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upserts, hasLength(1));
    expect(upserts.single.title, '1. Schularbeit');
  });

  test('editing a reminder updates the existing tracked event', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 100;
    };

    final initialState = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Reminder',
                subtitle: 'Old text',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );
    final editedState = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Reminder',
                subtitle: 'Updated text',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );

    await CalendarSyncService.reconcile(initialState);
    await CalendarSyncService.reconcile(editedState);

    expect(upserts, hasLength(2));
    expect(upserts.first.eventId, isNull);
    expect(upserts.last.eventId, 100);
    expect(upserts.last.description, contains('Updated text'));
  });

  test('removing a reminder deletes the linked tracked event', () async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 333;
    CalendarSyncService.deleteEventOverride = (eventId) async {
      deletedIds.add(eventId);
    };

    final withReminder = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Reminder',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );
    final withoutReminder = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(date: UtcDateTime(2026, 4, 10)),
        ]);
      },
    );

    await CalendarSyncService.reconcile(withReminder);
    await CalendarSyncService.reconcile(withoutReminder);

    expect(deletedIds, <int>[333]);
  });

  test('reconcile skips calendar homework entries that are already covered by dashboard sync', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return upserts.length;
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Arbeitsblatt',
                subtitle: 'Seite 12',
              ),
            ],
          ),
        ]);
        b.calendarState.days = MapBuilder<UtcDateTime, CalendarDay>({
          UtcDateTime(2026, 4, 10): buildCalendarDay(
            date: UtcDateTime(2026, 4, 10),
            hours: <CalendarHour>[
              buildCalendarHour(
                subject: 'Mathematik',
                homeworkExams: <HomeworkExam>[
                  buildHomeworkExam(
                    id: 22,
                    name: 'Arbeitsblatt',
                    deadline: UtcDateTime(2026, 4, 10, 9),
                  ),
                  buildHomeworkExam(
                    id: 23,
                    name: 'Kapiteltest',
                    homework: false,
                    typeName: 'Pruefung',
                    deadline: UtcDateTime(2026, 4, 11, 9),
                  ),
                ],
              ),
            ],
          ),
        });
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upserts, hasLength(2));
    expect(upserts.map((request) => request.title), <String>[
      'Arbeitsblatt',
      'Kapiteltest',
    ]);
  });

  test('checked dashboard items are removed from calendar sync and restored when unchecked', () async {
    final deletedIds = <int>[];
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return 333;
    };
    CalendarSyncService.deleteEventOverride = (eventId) async {
      deletedIds.add(eventId);
    };

    final activeState = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Worksheet',
              ),
            ],
          ),
        ]);
      },
    );
    final checkedState = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Worksheet',
                checked: true,
              ),
            ],
          ),
        ]);
      },
    );

    await CalendarSyncService.reconcile(activeState);
    await CalendarSyncService.reconcile(checkedState);
    await CalendarSyncService.reconcile(activeState);

    expect(upserts, hasLength(2));
    expect(upserts.first.eventId, isNull);
    expect(upserts.last.eventId, isNull);
    expect(deletedIds, <int>[333]);
  });

  test('disabled sync does not create calendar events', () async {
    var upsertCalls = 0;
    CalendarSyncService.upsertEventOverride = (_) async {
      upsertCalls++;
      return 1;
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = false;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(id: 7, type: HomeworkType.homework),
            ],
          ),
        ]);
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upsertCalls, 0);
  });

  test('deleteTrackedEvents removes stored synced events', () async {
    final deletedIds = <int>[];
    CalendarSyncService.upsertEventOverride = (_) async => 444;
    CalendarSyncService.deleteEventOverride = (eventId) async {
      deletedIds.add(eventId);
    };

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(id: 7, type: HomeworkType.homework),
            ],
          ),
        ]);
      },
    );

    await CalendarSyncService.reconcile(state);
    final success = await CalendarSyncService.deleteTrackedEvents();

    expect(success, isTrue);
    expect(deletedIds, <int>[444]);
  });

  test('reconcile sends expected method channel payloads', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      methodChannel,
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getDefaultCalendarId':
            return 41;
          case 'upsertCalendarEvent':
            return 901;
          case 'deleteCalendarEvent':
            return null;
        }
        return null;
      },
    );

    CalendarSyncService.getDefaultCalendarIdOverride = null;
    CalendarSyncService.upsertEventOverride = null;
    CalendarSyncService.deleteEventOverride = null;

    final state = AppState(
      (b) {
        b.settingsState.calendarSyncEnabled = true;
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Reminder',
                subtitle: 'Read chapter',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );

    await CalendarSyncService.reconcile(state);

    final upsertCall = calls.firstWhere((call) => call.method == 'upsertCalendarEvent');
    final args = Map<String, Object?>.from(upsertCall.arguments as Map);
    expect(args['calendarId'], 41);
    expect(args['title'], 'Erinnerung');
    expect(args['description'], contains('Read chapter'));
    expect(args['description'], contains('[Digitales Register Sync: reminder:7]'));
  });

  test('reconcile localizes calendar entry text to the selected app language', () async {
    final upserts = <CalendarSyncUpsertRequest>[];
    CalendarSyncService.upsertEventOverride = (request) async {
      upserts.add(request);
      return upserts.length;
    };

    final state = AppState(
      (b) {
        b.settingsState
          ..calendarSyncEnabled = true
          ..languageCode = 'en';
        b.dashboardState.allDays = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2026, 4, 10),
            homework: <Homework>[
              buildHomework(
                id: 7,
                title: 'Erinnerung',
                subtitle: 'Hausaufgabe',
                label: 'Deutsch',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ]);
      },
    );

    final success = await CalendarSyncService.reconcile(state);

    expect(success, isTrue);
    expect(upserts, hasLength(1));
    expect(upserts.single.title, 'Reminder');
    expect(upserts.single.description, contains('Homework'));
  });
}
