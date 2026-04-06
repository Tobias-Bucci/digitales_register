import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
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
        ..colorBorders = false
        ..colorTestsInRed = false
        ..subjectThemes = MapBuilder<String, SubjectTheme>()
        ..showNotifications = false
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
      ),
    );
    await settleFor(tester);

    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 600));

    expect(refreshCalls, 1);
  });
}
