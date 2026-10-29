import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/days.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

GradeGroupSubmission _submission(int id) => GradeGroupSubmission(
      (b) => b
        ..id = id
        ..gradeGroupId = 2
        ..userId = 3
        ..file = 'file$id'
        ..originalName = 'version$id.pdf'
        ..typeName = 'file'
        ..timestamp = UtcDateTime(2026, 3, 20),
    );

Homework _version(int submissionId, {Homework? previous}) => buildHomework(
      id: 7,
      type: HomeworkType.gradeGroup,
      label: 'Mathe',
      submissions: [_submission(submissionId)],
    ).rebuild((b) => b..previousVersion = previous?.toBuilder());

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  testWidgets('Versions opens attachments of current and prior versions',
      (tester) async {
    final opened = <int>[];
    final controller = AutoScrollController();
    addTearDown(controller.dispose);
    final item = _version(3, previous: _version(2, previous: _version(1)));
    final store = createStore(
      initialState: AppState((b) => b..settingsState.languageCode = 'en'),
    );

    await pumpApp(
      tester,
      store: store,
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: ItemWidget(
            item: item,
            allSubjects: BuiltList<String>(['Mathe']),
            askWhenDelete: false,
            noInternet: false,
            colorBorder: false,
            subjectThemes: BuiltMap<String, SubjectTheme>(),
            colorTestsInRed: false,
            onOpenAttachment: (ggs) => opened.add(ggs.id),
            index: 0,
            controller: controller,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Versions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final dialog = find.byType(Dialog);
    for (final id in [3, 2, 1]) {
      final open = find.descendant(
        of: find.ancestor(
          of: find.text('version$id.pdf').last,
          matching: find.byType(AttachmentWidget),
        ),
        matching: find.widgetWithText(TextButton, 'Open'),
      );
      expect(find.descendant(of: dialog, matching: open), findsOneWidget);
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
    }
    expect(opened, [3, 2, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachments without an opener are listed but not openable',
      (tester) async {
    await pumpApp(
      tester,
      store: createStore(
        initialState: AppState((b) => b..settingsState.languageCode = 'en'),
      ),
      home: Scaffold(
        body: AttachmentWidget(
          ggs: _submission(1),
          noInternet: false,
          openCallback: null,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('version1.pdf'), findsOneWidget);
    final open =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Open'));
    expect(open.onPressed, isNull);
  });
}
