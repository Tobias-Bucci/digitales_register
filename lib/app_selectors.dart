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
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:tuple/tuple.dart';

class AppSelectors {
  final _dashboardDaysSelector = _DashboardDaysSelector();
  final _allSubjectsAverageSelector = _AllSubjectsAverageSelector();
  final _hasGradesDataSelector = _HasGradesDataSelector();
  final _chartSelector = _GradesChartSelector();
  final _absenceStatsSelector = _AbsenceStatsSelector();

  BuiltList<Day> dashboardDays(AppState state) =>
      _dashboardDaysSelector.select(state);

  String allSubjectsAverage(AppState state) =>
      _allSubjectsAverageSelector.select(state);

  bool hasGradesData(AppState state) => _hasGradesDataSelector.select(state);

  Map<SubjectGrades, SubjectTheme> chartGraphs(AppState state) =>
      _chartSelector.select(state);

  AbsenceStatsViewModel absenceStatistics(AbsencesState state) =>
      _absenceStatsSelector.select(state);
}

final AppSelectors appSelectors = AppSelectors();

class AbsenceStatsViewModel {
  final AbsenceStatistic statistic;
  final BuiltList<AbsenceMonthlyHistoryValue> monthlyHistory;

  const AbsenceStatsViewModel({
    required this.statistic,
    required this.monthlyHistory,
  });

  bool get hasHistoricalData => monthlyHistory.isNotEmpty;

  bool get spansMultipleYears =>
      monthlyHistory.map((entry) => entry.month.year).toSet().length > 1;
}

class AbsenceMonthlyHistoryValue {
  final UtcDateTime month;
  final double lessons;

  const AbsenceMonthlyHistoryValue({
    required this.month,
    required this.lessons,
  });
}

const _typesToTitles = <HomeworkType, List<String>>{
  HomeworkType.grade: ["Bewertung"],
  HomeworkType.gradeGroup: ["Testarbeit", "Schularbeit", "Prüfung", "Test"],
  HomeworkType.homework: ["Erinnerung"],
  HomeworkType.lessonHomework: ["Hausaufgabe"],
  HomeworkType.observation: ["Beobachtung"],
};

class SubjectGrades {
  final Map<UtcDateTime, Tuple2<int, String>> grades;
  final String name;

  SubjectGrades(this.grades, this.name);
}

bool _isBlacklisted(Homework homework, BuiltList<HomeworkType> blacklist) {
  if (blacklist.contains(homework.type)) {
    return true;
  }

  return blacklist.any(
    (blacklisted) => _typesToTitles[blacklisted]!.any(
      (blacklistedTitle) => homework.title.contains(blacklistedTitle),
    ),
  );
}

class _DashboardDaysSelector {
  DashboardState? _dashboardState;
  BuiltList<HomeworkType>? _blacklist;
  BuiltList<Day>? _lastResult;

  BuiltList<Day> select(AppState state) {
    if (identical(state.dashboardState, _dashboardState) &&
        identical(state.dashboardState.blacklist, _blacklist) &&
        _lastResult != null) {
      return _lastResult!;
    }

    final unorderedDays = state.dashboardState.allDays
            ?.where((day) => day.future == state.dashboardState.future)
            .map(
              (day) => day.rebuild(
                (b) => b
                  ..deletedHomework.replace(
                    day.deletedHomework.where(
                      (hw) =>
                          !_isBlacklisted(hw, state.dashboardState.blacklist!),
                    ),
                  )
                  ..homework.replace(
                    day.homework.where(
                      (hw) =>
                          !_isBlacklisted(hw, state.dashboardState.blacklist!),
                    ),
                  ),
              ),
            )
            .toList() ??
        const <Day>[];

    final result = BuiltList<Day>(
      !state.dashboardState.future ? unorderedDays.reversed : unorderedDays,
    );
    _dashboardState = state.dashboardState;
    _blacklist = state.dashboardState.blacklist;
    _lastResult = result;
    return result;
  }
}

class _AllSubjectsAverageSelector {
  BuiltList<Subject>? _subjects;
  BuiltList<String>? _ignoredSubjects;
  Semester? _semester;
  String? _lastResult;

  String select(AppState state) {
    if (identical(state.gradesState.subjects, _subjects) &&
        identical(
            state.settingsState.ignoreForGradesAverage, _ignoredSubjects) &&
        identical(state.gradesState.semester, _semester) &&
        _lastResult != null) {
      return _lastResult!;
    }

    var sum = 0;
    var count = 0;
    for (final subject in state.gradesState.subjects) {
      final average = subject.average(state.gradesState.semester);
      if (average != null &&
          !state.settingsState.ignoreForGradesAverage.any(
            (element) => element.toLowerCase() == subject.name.toLowerCase(),
          )) {
        sum += average;
        count++;
      }
    }

    final result =
        count == 0 ? "/" : gradeAverageFormat.format(sum / count / 100);
    _subjects = state.gradesState.subjects;
    _ignoredSubjects = state.settingsState.ignoreForGradesAverage;
    _semester = state.gradesState.semester;
    _lastResult = result;
    return result;
  }
}

class _HasGradesDataSelector {
  BuiltList<Subject>? _subjects;
  Semester? _semester;
  bool? _lastResult;

  bool select(AppState state) {
    if (identical(state.gradesState.subjects, _subjects) &&
        identical(state.gradesState.semester, _semester) &&
        _lastResult != null) {
      return _lastResult!;
    }
    final result = state.gradesState.subjects.any(
      (s) => state.gradesState.semester != Semester.all
          ? s.gradesAll.containsKey(state.gradesState.semester)
          : s.gradesAll.isNotEmpty,
    );
    _subjects = state.gradesState.subjects;
    _semester = state.gradesState.semester;
    _lastResult = result;
    return result;
  }
}

class _GradesChartSelector {
  BuiltList<Subject>? _subjects;
  BuiltMap<String, SubjectTheme>? _subjectThemes;
  Semester? _semester;
  Map<SubjectGrades, SubjectTheme>? _lastResult;

  Map<SubjectGrades, SubjectTheme> select(AppState state) {
    if (identical(state.gradesState.subjects, _subjects) &&
        identical(state.settingsState.subjectThemes, _subjectThemes) &&
        identical(state.gradesState.semester, _semester) &&
        _lastResult != null) {
      return _lastResult!;
    }

    final result = <SubjectGrades, SubjectTheme>{};
    for (final subject in state.gradesState.subjects) {
      final grades = state.gradesState.semester == Semester.all
          ? (subject.gradesAll.values.fold<List<GradeAll>>(
              <GradeAll>[],
              (a, b) => <GradeAll>[...a, ...b],
            )..sort((a, b) => a.date.compareTo(b.date)))
          : subject.gradesAll[state.gradesState.semester]?.toList() ??
              <GradeAll>[];
      grades.removeWhere((grade) => grade.cancelled || grade.grade == null);
      result[SubjectGrades(
        {
          for (final grade in grades)
            grade.date: Tuple2(grade.grade!, grade.type),
        },
        subject.name,
      )] = state.settingsState.subjectThemes[subject.name]!;
    }

    _subjects = state.gradesState.subjects;
    _subjectThemes = state.settingsState.subjectThemes;
    _semester = state.gradesState.semester;
    _lastResult = result;
    return result;
  }
}

class _AbsenceStatsSelector {
  AbsencesState? _state;
  AbsenceStatsViewModel? _lastResult;

  AbsenceStatsViewModel select(AbsencesState state) {
    if (identical(state, _state) && _lastResult != null) {
      return _lastResult!;
    }

    final historyByMonth = <UtcDateTime, double>{};
    for (final group in state.absences) {
      for (final absence in group.absences) {
        final month = UtcDateTime(absence.date.year, absence.date.month);
        historyByMonth.update(
          month,
          (current) => current + _lessonEquivalent(absence),
          ifAbsent: () => _lessonEquivalent(absence),
        );
      }
    }

    final sortedMonths = historyByMonth.keys.toList()..sort();
    final result = AbsenceStatsViewModel(
      statistic: state.statistic ?? AbsenceStatistic(),
      monthlyHistory: BuiltList<AbsenceMonthlyHistoryValue>(
        sortedMonths.map(
          (month) => AbsenceMonthlyHistoryValue(
            month: month,
            lessons: historyByMonth[month]!,
          ),
        ),
      ),
    );

    _state = state;
    _lastResult = result;
    return result;
  }

  double _lessonEquivalent(Absence absence) {
    if (absence.minutes == 50) {
      return 1;
    }
    return (absence.minutesCameTooLate + absence.minutesLeftTooEarly) / 50;
  }
}
