import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/calendar_week.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('shows a substitute badge in the calendar week view',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) {
          b.settingsState
            ..languageCode = 'de'
            ..subjectThemes = MapBuilder<String, SubjectTheme>({
              'Fach1': SubjectTheme(
                (b) => b
                  ..color = Colors.red.toARGB32()
                  ..thick = 2,
              ),
            });
        },
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: CalendarWeek(
        vm: CalendarWeekViewModel(
          (b) => b
            ..days = ListBuilder<CalendarDay>([
              buildCalendarDay(
                date: UtcDateTime(2026, 4, 17),
                hours: [
                  buildCalendarHour(
                    subject: 'Fach1',
                    isDetectedSubstitute: true,
                  ),
                ],
              ),
            ])
            ..subjectNicks = MapBuilder<String, String>()
            ..noInternet = false
            ..selection = null
            ..colorBackground = false
            ..subjectThemes = MapBuilder<String, SubjectTheme>({
              'Fach1': SubjectTheme(
                (b) => b
                  ..color = Colors.red.toARGB32()
                  ..thick = 2,
              ),
            }),
        ),
        favoriteSubject: null,
      ),
    );
    await settleFor(tester);

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox).last);
    final decoration = decoratedBox.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.right, isNot(BorderSide.none));
  });
}
