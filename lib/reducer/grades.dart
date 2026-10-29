// Copyright (C) 2021 Michael Debertol
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
import 'package:built_redux/built_redux.dart';
import 'package:collection/collection.dart' show IterableExtension;

import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/star_rating.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';

final gradesReducerBuilder = NestedReducerBuilder<AppState, AppStateBuilder,
    GradesState, GradesStateBuilder>(
  (s) => s.gradesState,
  (b) => b.gradesState,
)
  ..add(GradesActionsNames.load, _loading)
  ..add(GradesActionsNames.loaded, _loaded)
  ..add(GradesActionsNames.loadFailed, _loadFailed)
  ..add(GradesActionsNames.cancelledDescriptionLoaded,
      _cancelledDescriptionLoaded)
  ..add(GradesActionsNames.setSemester, _setSemester)
  ..add(LoginActionsNames.automaticallyReloggedIn, _afterAutoRelogin)
  ..add(GradesActionsNames.detailsLoaded, _detailsLoaded)
  ..add(AppActionsNames.setConfig, _setConfig);

void _loading(
    GradesState state, Action<Semester> action, GradesStateBuilder builder) {
  builder.loading = true;
}

void _loaded(GradesState state, Action<SubjectsLoadedPayload> action,
    GradesStateBuilder builder) {
  _updateSubjects(state.subjects, builder.subjects,
      getMap(action.payload.data)!, action.payload.semester);
  builder
    ..serverSemester.replace(action.payload.semester)
    ..loading = false;
}

void _loadFailed(
    GradesState state, Action<void> action, GradesStateBuilder builder) {
  builder.loading = false;
}

void _updateSubjects(BuiltList<Subject> previousSubjects,
    ListBuilder<Subject> subjectsBuilder, Map data, Semester semester) {
  final newSubjects = List<Map<String, dynamic>>.from(
    getList(data["subjects"])!,
  );
  final loadedSchoolYear = _latestSchoolYear(
    newSubjects.expand(
      (subject) => getList(subject["grades"])!
          .map((dynamic g) => getString(getMap(g)!["date"]))
          .whereType<String>()
          .map(UtcDateTime.tryParse)
          .whereType<UtcDateTime>(),
    ),
  );
  var oldSubjects = previousSubjects;
  if (loadedSchoolYear != null &&
      _containsEarlierSchoolYear(oldSubjects, semester, loadedSchoolYear)) {
    // The snapshot proves that a new school year has started: data kept for
    // the other semester belongs to the previous year and must not be merged
    // into the new one.
    oldSubjects = BuiltList<Subject>();
    subjectsBuilder.clear();
  }
  final removedIds = oldSubjects.map((s) => s.id).toSet();
  for (final subject in newSubjects) {
    final nestedSubject = getMap(subject["subject"])!;
    final id = getInt(nestedSubject["id"]);
    removedIds.remove(id);
    final subjectIdx = oldSubjects.indexWhere((s) => s.id == id);
    if (subjectIdx != -1) {
      // just update the grades
      subjectsBuilder[subjectIdx] = subjectsBuilder[subjectIdx].rebuild(
        (b) => b
          ..gradesAll[semester] = BuiltList(
            getList(subject["grades"])!.map<GradeAll>(
              (dynamic g) => tryParse(getMap(g)!, _parseGradeAll),
            ),
          )
          ..absences[semester] = getInt(subject["absences"]) ?? 0
          ..lastFetchedBasic[semester] = UtcDateTime.now(),
      );
    } else {
      subjectsBuilder.add(
        Subject(
          (b) => b
            ..id = getInt(nestedSubject["id"])
            ..name = getString(nestedSubject["name"])
            ..gradesAll = MapBuilder(
              {
                semester: BuiltList<GradeAll>(
                  getList(subject["grades"])!.map<GradeAll>(
                    (dynamic g) => tryParse(getMap(g)!, _parseGradeAll),
                  ),
                ),
              },
            )
            ..absences = MapBuilder(
              {
                semester: getInt(subject["absences"]) ?? 0,
              },
            ),
        ),
      );
    }
  }
  // The snapshot only lists the subjects of [semester]. A subject missing
  // from it is no longer attended in this semester, but it may still belong
  // to the other one, so only its membership in [semester] is dropped. The
  // subject itself disappears once it belongs to no semester at all.
  for (final id in removedIds) {
    final index = subjectsBuilder.build().indexWhere((s) => s.id == id);
    if (index == -1) continue;
    final remaining = _withoutSemester(subjectsBuilder[index], semester);
    if (remaining.gradesAll.isEmpty) {
      subjectsBuilder.removeAt(index);
    } else {
      subjectsBuilder[index] = remaining;
    }
  }
}

Subject _withoutSemester(Subject subject, Semester semester) {
  return subject.rebuild(
    (b) {
      b
        ..gradesAll.remove(semester)
        ..grades.remove(semester)
        ..observations.remove(semester)
        ..absences.remove(semester);
      if (subject.lastFetchedBasic != null) {
        b.lastFetchedBasic.remove(semester);
      }
      if (subject.lastFetchedDetailed != null) {
        b.lastFetchedDetailed.remove(semester);
      }
    },
  );
}

/// The school year (identified by the calendar year it starts in) a date
/// belongs to. School years start in September; August is counted towards
/// the upcoming year.
int _schoolYearOf(UtcDateTime date) =>
    date.month >= DateTime.august ? date.year : date.year - 1;

int? _latestSchoolYear(Iterable<UtcDateTime> dates) {
  int? latest;
  for (final date in dates) {
    final year = _schoolYearOf(date);
    if (latest == null || year > latest) latest = year;
  }
  return latest;
}

bool _containsEarlierSchoolYear(
    BuiltList<Subject> subjects, Semester loaded, int schoolYear) {
  for (final subject in subjects) {
    for (final entry in subject.gradesAll.entries) {
      if (entry.key == loaded) continue;
      if (entry.value.any((g) => _schoolYearOf(g.date) < schoolYear)) {
        return true;
      }
    }
  }
  return false;
}

void _detailsLoaded(GradesState state,
    Action<SubjectDetailLoadedPayload> action, GradesStateBuilder builder) {
  final data = getMap(action.payload.data);
  builder.subjects.map(
    (s) => s.id == action.payload.subject.id
        ? s.rebuild(
            (b) => b
              ..grades[action.payload.semester] = BuiltList(
                getList(data!["grades"])!.map<GradeDetail>(
                  (dynamic g) => tryParse(getMap(g)!, _parseGrade).rebuild(
                    (d) => d
                      // we will also try to load the [cancelledDescription]
                      // again, but for now keep the old one
                      ..cancelledDescription = b.grades[action.payload.semester]
                          ?.firstWhereOrNull(
                            (gd) => gd.id == d.id,
                          )
                          ?.cancelledDescription,
                  ),
                ),
              )
              ..observations[action.payload.semester] = BuiltList(
                getList(data["observations"])!.map<Observation>(
                  (dynamic o) => tryParse(getMap(o)!, _parseObservation),
                ),
              )
              ..lastFetchedDetailed[action.payload.semester] =
                  UtcDateTime.now(),
          )
        : s,
  );
}

void _cancelledDescriptionLoaded(
    GradesState state,
    Action<GradeCancelledDescriptionLoadedPayload> action,
    GradesStateBuilder builder) {
  builder.subjects.map(
    (s) => s.grades[action.payload.semester]?.contains(action.payload.grade) ==
            true
        ? s.rebuild(
            (b) => b
              ..grades[action.payload.semester] =
                  b.grades[action.payload.semester]!.rebuild(
                (b) => b
                  ..map(
                    (g) => g == action.payload.grade
                        ? _addCancelledDescription(g, action.payload.data)
                        : g,
                  ),
              ),
          )
        : s,
  );
}

Observation _parseObservation(Map data) {
  return Observation(
    (b) => b
      ..typeName = getString(data["typeName"])
      ..cancelled = data["cancelled"] != 0
      ..created = getString(data["created"])
      ..note = getString(data["note"])
      ..date = UtcDateTime.parse(getString(data["date"])!),
  );
}

GradeAll _parseGradeAll(Map data) {
  return GradeAll(
    (b) => b
      ..grade = parseBackendGradeHundredths(getString(data["grade"]))
      ..weightPercentage = getInt(data["weight"])
      ..date = UtcDateTime.parse(getString(data["date"])!)
      ..cancelled = data["cancelled"] != 0
      ..type = getString(data["type"]),
  );
}

GradeDetail _parseGrade(Map data) {
  return GradeDetail(
    (b) => b
      ..grade = parseBackendGradeHundredths(getString(data["grade"]))
      ..date = UtcDateTime.parse(getString(data["date"])!)
      ..weightPercentage = getInt(data["weight"])
      ..cancelled = getBool(data["cancelled"])
      ..type = getString(data["typeName"])
      ..created = getString(data["created"])
      ..name = getString(data["name"])
      ..description = getString(data["description"])
      ..id = getInt(data["id"])
      ..competences = ListBuilder(
        parseCompetenceList(data["competences"]).map<Competence>(
          (c) => _parseCompetence(parseCompetenceMap(c)),
        ),
      ),
  );
}

GradeDetail _addCancelledDescription(GradeDetail grade, dynamic data) {
  return grade.rebuild(
    (b) => b..cancelledDescription = getString(data["cancelledDescription"]),
  );
}

Competence _parseCompetence(Map data) {
  return Competence((b) => b
    ..typeName = data["typeName"] is String ? data["typeName"] as String : "—"
    ..grade = parseStarCount(data["grade"]));
}

void _setSemester(
    GradesState state, Action<Semester> action, GradesStateBuilder builder) {
  builder.semester.replace(action.payload);
}

void _afterAutoRelogin(
    GradesState state, Action<void> action, GradesStateBuilder builder) {
  builder.serverSemester = null;
}

void _setConfig(
    GradesState state, Action<Config> action, GradesStateBuilder builder) {
  if (action.payload.currentSemesterMaybe == 1) {
    builder.semester.replace(Semester.first);
  }
  if (action.payload.currentSemesterMaybe == 2) {
    builder.semester.replace(Semester.second);
  }
}
