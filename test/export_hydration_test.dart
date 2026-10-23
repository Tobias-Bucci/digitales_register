import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/actions/absences_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/actions/certificate_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/middleware/middleware.dart' show schoolYearForDate;
import 'package:dr/container/export_container.dart';
import 'package:dr/ui/export_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'export_test.dart' show exportFixture;
import 'support/test_harness.dart';

void main() {
  testWidgets(
      'opening export requests every source once without navigating pages',
      (tester) async {
    final state = exportFixture().rebuild((b) => b
      ..calendarState.prefetchedSchoolYears.add(schoolYearForDate(appClock.now))
      ..config.replace(Config((c) => c
        ..userId = 1
        ..autoLogoutSeconds = 300
        ..fullName = ''
        ..imgSource = ''
        ..isStudentOrParent = true)));
    final requests = <String, int>{};
    final names = {
      GradesActionsNames.load.name,
      MessagesActionsNames.load.name,
      CertificateActionsNames.load.name,
      AbsencesActionsNames.load.name,
      DashboardActionsNames.load.name,
      CalendarActionsNames.load.name
    };
    final store = Store<AppState, AppStateBuilder, AppActions>(
        appReducerBuilder.build(), state, AppActions(),
        middleware: [
          (api) => (next) => (action) async {
                if (names.contains(action.name))
                  requests.update(action.name, (n) => n + 1, ifAbsent: () => 1);
                await next(action);
              }
        ]);
    addTearDown(store.dispose);
    await tester
        .pumpWidget(buildTestApp(store: store, home: const ExportContainer()));
    await tester.runAsync(() async {
      for (var n = 0; n < 30; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpAndSettle();
    expect(requests.values, everyElement(1));
    expect(requests.length, 6, reason: requests.toString());
    expect(tester.widget<ExportPage>(find.byType(ExportPage)).loading, isFalse);
    await store.actions.gradesActions.loadFailed();
    await tester.pumpAndSettle();
    expect(requests.values, everyElement(1),
        reason: 'Redux rebuilds must not restart hydration');
  });
}
