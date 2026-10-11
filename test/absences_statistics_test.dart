import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() {
    store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState(),
      AppActions(),
    );
  });

  tearDown(() => store.dispose());

  test('four lessons override stale server counts and use each lesson status',
      () {
    store.actions.absencesActions.loaded(_payload([
      _group(1, [
        _lesson(1, status: 2),
        _lesson(2, status: 3),
        _lesson(3),
      ]),
      _group(4, [_lesson(4)]),
    ]));

    final vm = appSelectors.absenceStatistics(store.state.absencesState);
    expect(vm.statistic.counter, 4);
    expect(vm.statistic.justified, 1);
    expect(vm.statistic.notJustified, 2);
    expect(vm.statistic.counterForSchool, 1);
    expect(vm.statistic.delayed, 0);
    expect(vm.statistic.percentage, '2.5');
    expect(
        vm.monthlyHistory.fold<double>(0, (sum, month) => sum + month.lessons),
        4);
  });

  test('shorter refresh removes obsolete groups after justification', () {
    store.actions.absencesActions.loaded(_payload([
      _group(1, [_lesson(1), _lesson(2)]),
      _group(3, [_lesson(3), _lesson(4)]),
      _group(1, [_lesson(5)]),
    ]));
    expect(
        appSelectors
            .absenceStatistics(store.state.absencesState)
            .statistic
            .counter,
        5);

    store.actions.absencesActions.loaded(_payload([
      _group(2, [_lesson(1), _lesson(2), _lesson(3), _lesson(4)]),
    ]));

    final vm = appSelectors.absenceStatistics(store.state.absencesState);
    expect(store.state.absencesState.absences, hasLength(1));
    expect(vm.statistic.counter, 4);
    expect(vm.statistic.justified, 4);
    expect(vm.statistic.notJustified, 0);
    expect(
        vm.monthlyHistory.fold<double>(0, (sum, month) => sum + month.lessons),
        4);
  });

  test('empty refresh clears history and all counters', () {
    store.actions.absencesActions.loaded(_payload([
      _group(1, [_lesson(1)]),
    ]));
    store.actions.absencesActions.loaded(_payload([]));

    final vm = appSelectors.absenceStatistics(store.state.absencesState);
    expect(store.state.absencesState.absences, isEmpty);
    expect(vm.monthlyHistory, isEmpty);
    expect(vm.statistic.counter, 0);
    expect(vm.statistic.justified, 0);
    expect(vm.statistic.notJustified, 0);
    expect(vm.statistic.counterForSchool, 0);
    expect(vm.statistic.delayed, 0);
  });

  test('partial lessons count once and only late arrivals count as delays', () {
    store.actions.absencesActions.loaded(_payload([
      _group(2, [
        _lesson(1, minutes: 10, late: 10),
        _lesson(2, minutes: 15, early: 15),
        _lesson(3, minutes: 25, late: 10, early: 15),
      ]),
    ]));

    final vm = appSelectors.absenceStatistics(store.state.absencesState);
    expect(vm.statistic.counter, 3);
    expect(vm.statistic.justified, 3);
    expect(vm.statistic.delayed, 2);
    expect(
        vm.monthlyHistory.fold<double>(0, (sum, month) => sum + month.lessons),
        closeTo(1, 0.0001));
  });

  test('failed refresh preserves the last valid history and status', () {
    store.actions.absencesActions.loaded(_payload([
      _group(3, [_lesson(1)]),
    ]));
    store.actions.absencesActions.loaded({'absences': []});

    expect(store.state.absencesState.loadFailed, isTrue);
    final vm = appSelectors.absenceStatistics(store.state.absencesState);
    expect(vm.statistic.counter, 1);
    expect(vm.statistic.notJustified, 1);
  });
}

Map<String, Object?> _payload(List<Map<String, Object?>> groups) => {
      'statistics': {
        'counter': 5,
        'justified': 5,
        'notJustified': 0,
        'counterForSchool': 0,
        'delayed': 0,
        'percentage': '2.5',
      },
      'absences': groups,
      'futureAbsences': [
        {
          'startDate': '2026-11-01',
          'endDate': '2026-11-01',
          'startTime': 1,
          'endTime': 5,
          'justified': 1,
        },
      ],
    };

Map<String, Object?> _group(int status, List<Map<String, Object?>> lessons) => {
      'date': '2026-10-01',
      'justified': status,
      'group': lessons,
    };

Map<String, Object?> _lesson(int id,
        {int? status, int minutes = 50, int late = 0, int early = 0}) =>
    {
      'id': id,
      'date': '2026-10-01',
      'hour': id,
      'minutes': minutes,
      'minutes_begin': late,
      'minutes_end': early,
      if (status != null) 'justified': status,
    };
