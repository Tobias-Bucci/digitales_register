import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('changed dashboard entries keep the previous version', () {
    mockNow = UtcDateTime(2020, 1, 10);

    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(
        (b) => b.dashboardState.allDays.add(
          Day(
            (b) => b
              ..date = UtcDateTime(2020, 1, 5)
              ..lastRequested = UtcDateTime(2020)
              ..homework.add(
                Homework(
                  (b) => b
                    ..checkable = true
                    ..checked = false
                    ..deleteable = false
                    ..deleted = false
                    ..firstSeen = UtcDateTime(2020)
                    ..id = 1
                    ..isChanged = false
                    ..isNew = false
                    ..label = 'Fach'
                    ..lastNotSeen = UtcDateTime(2019, 12, 24)
                    ..subtitle = 'Untertitel'
                    ..title = 'Titel'
                    ..type = HomeworkType.lessonHomework
                    ..warning = false,
                ),
              ),
          ),
        ),
      ),
      AppActions(),
      middleware: middleware(includeErrorMiddleware: false),
    );

    store.actions.dashboardActions.loaded(
      DaysLoadedPayload(
        (b) => b
          ..future = false
          ..markNewOrChangedEntries = true
          ..deduplicateEntries = false
          ..data = <Object>[
            <String, Object?>{
              'items': <Object>[
                <String, Object?>{
                  'id': 1,
                  'type': 'lessonHomework',
                  'title': 'Neuer Titel',
                  'subtitle': 'Neuer Untertitel',
                  'label': 'Fach',
                  'warning': false,
                  'checkable': true,
                  'checked': false,
                  'deleteable': false,
                },
              ],
              'date': '2020-01-05',
            },
          ],
      ),
    );

    expect(
      store.state.dashboardState.allDays!.single.homework.single,
      Homework(
        (b) => b
          ..checkable = true
          ..checked = false
          ..deleteable = false
          ..deleted = false
          ..firstSeen = now
          ..id = 1
          ..isChanged = true
          ..isNew = false
          ..label = 'Fach'
          ..lastNotSeen = UtcDateTime(2020)
          ..subtitle = 'Neuer Untertitel'
          ..title = 'Neuer Titel'
          ..type = HomeworkType.lessonHomework
          ..warning = false
          ..previousVersion = (HomeworkBuilder()
            ..checkable = true
            ..checked = false
            ..deleteable = false
            ..deleted = false
            ..firstSeen = UtcDateTime(2020)
            ..id = 1
            ..isChanged = false
            ..isNew = false
            ..label = 'Fach'
            ..lastNotSeen = UtcDateTime(2019, 12, 24)
            ..subtitle = 'Untertitel'
            ..title = 'Titel'
            ..type = HomeworkType.lessonHomework
            ..warning = false),
      ),
    );
  });
}
