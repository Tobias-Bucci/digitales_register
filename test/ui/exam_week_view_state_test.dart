import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/exam_calendar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/exam_study_plan.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    appClock.setDemoMode(true);
  });
  tearDown(resetTestState);

  testWidgets('week view reopens details with the latest saved state',
      (tester) async {
    final store = createStore(
      initialState: AppState((b) => b
        ..settingsState.languageCode = 'en'
        ..dashboardState.allDays.replace([
          buildDay(date: UtcDateTime(2025, 10, 11), homework: [
            buildHomework(
              id: 7,
              type: HomeworkType.gradeGroup,
              title: 'Synthetic test',
              label: 'Synthetic math',
            ),
          ]),
        ])),
    );
    const id = 'assessment-7';
    final tile = find.byKey(const Key('week-exam-$id'));

    Future<void> openDetail() async {
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    TextField notes() => tester.widget<TextField>(find.byType(TextField));
    CheckboxListTile firstPhase() =>
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile).first);

    await pumpApp(tester, store: store, home: const ExamCalendarContainer());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exam-calendar-week-view')));
    await tester.pumpAndSettle();

    // First edit: note and progress of the first study phase.
    await openDetail();
    await tester.enterText(find.byType(TextField), 'First note');
    await tester.ensureVisible(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(store.state.settingsState.assessmentStudyNotes[id], 'First note');
    final completed = completedPhaseIds(store.state, id);
    expect(completed, isNotEmpty);
    await back();

    // Reopening shows the saved values instead of the pre-edit snapshot.
    await openDetail();
    expect(notes().controller!.text, 'First note');
    expect(firstPhase().value, isTrue);

    // A second edit builds on the saved note and cannot restore old data.
    await tester.enterText(find.byType(TextField), 'Second note');
    await tester.pump();
    await back();
    expect(store.state.settingsState.assessmentStudyNotes[id], 'Second note');
    await openDetail();
    expect(notes().controller!.text, 'Second note');
    expect(completedPhaseIds(store.state, id), completed);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await store.dispose();
  });
}
