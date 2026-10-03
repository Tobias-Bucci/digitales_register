import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() {
    resetTestState();
  });

  testWidgets('filter and past buttons remain accessible on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = createStore(
        initialState: AppState(
      (b) => b.settingsState.dashboardItems = ListBuilder<String>(),
    ));

    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: SingleChildScrollView(
            child: DashboardHeader(
          future: true,
          onSwitchFuture: () {},
          favoriteSubjects: const [],
          selectedFavoriteSubject: null,
          onFavoriteSubjectChanged: (_) {},
          showEmptyDays: true,
          onShowEmptyDaysChanged: (_) {},
          subjectThemes: BuiltMap<String, SubjectTheme>(),
          schoolTimeline: const SchoolTimeline(
            holidays: [],
            gradeDeadlines: [],
          ),
          openCalendarAt: (_) async {},
          editGradeDeadline: (_) async {},
        )),
      ),
    );

    final filter = tester.getCenter(find.text('Filter'));
    final past = tester.getCenter(find.text('Vergangenheit'));
    expect(past.dy, greaterThanOrEqualTo(filter.dy));
    expect(
        tester
            .getSize(find.widgetWithText(FilledButton, 'Vergangenheit'))
            .width,
        lessThanOrEqualTo(280));
    expect(tester.getSize(find.byType(DashboardHeader)).height, lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull to refresh reloads dashboard entries', (tester) async {
    var refreshCalls = 0;
    final store = createStore();
    final vm = DaysViewModel(
      (b) => b
        ..future = false
        ..askWhenDelete = true
        ..noInternet = false
        ..loading = false
        ..showAddReminder = true
        ..showNotifications = false
        ..colorBorders = false
        ..colorTestsInRed = false
        ..subjectThemes = MapBuilder<String, SubjectTheme>()
        ..days = ListBuilder<Day>(<Day>[
          buildDay(
            date: UtcDateTime(2050),
            homework: <Homework>[
              buildHomework(
                title: 'Erinnerung',
                subtitle: 'Test',
                type: HomeworkType.homework,
              ),
            ],
          ),
        ])
        ..schoolTimelineDays = ListBuilder<Day>()
        ..schoolTimelineCalendarDays = ListBuilder<CalendarDay>()
        ..favoriteSubjects = ListBuilder<String>(),
    );

    await pumpApp(
      tester,
      store: store,
      home: DaysWidget(
        vm: vm,
        markAsSeenCallback: (_) {},
        markDeletedHomeworkAsSeenCallback: (_) {},
        markAllAsSeenCallback: () {},
        addReminderCallback: (day, reminder) {},
        editReminderCallback: (hw, day, reminder) {},
        removeReminderCallback: (hw, day) {},
        onSwitchFuture: () {},
        toggleDoneCallback: (_, __) {},
        setDoNotAskWhenDeleteCallback: () {},
        refresh: () async {
          refreshCalls++;
        },
        refreshNoInternet: () {},
        onOpenAttachment: (_) {},
        openCalendarAt: (_) async {},
      ),
    );
    await settleFor(tester);

    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 600));

    expect(refreshCalls, 1);
  });
}
