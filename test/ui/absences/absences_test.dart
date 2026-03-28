import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('renders absence groups and reasons', (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.absencesState
          ..canEdit = true
          ..statistic = AbsenceStatisticBuilder()
          ..absences = ListBuilder<AbsenceGroup>(<AbsenceGroup>[
            AbsenceGroup(
              (b) => b
                ..reason = 'Laura ist noch immer nicht ganz fit'
                ..justified = AbsenceJustified.justified
                ..hours = 2
                ..minutes = 0
                ..absences = ListBuilder<Absence>(<Absence>[
                  Absence(
                    (b) => b
                      ..date = UtcDateTime(2021, 2, 2)
                      ..hour = 3
                      ..minutes = 50
                      ..minutesCameTooLate = 0
                      ..minutesLeftTooEarly = 0,
                  ),
                  Absence(
                    (b) => b
                      ..date = UtcDateTime(2021, 2, 2)
                      ..hour = 4
                      ..minutes = 50
                      ..minutesCameTooLate = 0
                      ..minutesLeftTooEarly = 0,
                  ),
                ]),
            ),
          ]),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );
    await settleFor(tester);

    expect(find.text('Laura ist noch immer nicht ganz fit'), findsOneWidget);
    expect(find.byType(AbsenceGroupWidget), findsOneWidget);
    expect(find.textContaining('entschuldigt'), findsOneWidget);
  });

  testWidgets('shows empty state when there are no absences', (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.absencesState
          ..absences = ListBuilder<AbsenceGroup>()
          ..statistic = AbsenceStatisticBuilder(),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: AbsencesPageContainer(),
    );

    expect(find.text('Noch keine Absenzen'), findsOneWidget);
  });
}
