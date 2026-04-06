// Copyright (C) 2021 Michael Debertol
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
import 'package:built_value/built_value.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/grades_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Builder;
import 'package:flutter_built_redux/flutter_built_redux.dart';

part 'grades_page_container.g.dart';

class GradesPageContainer extends StatelessWidget {
  const GradesPageContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, GradesPageViewModel>(
      builder: (context, vm, actions) {
        return GradesPage(
          vm: vm,
          changeSemester: actions.gradesActions.setSemester.call,
          showGradesSettings:
              actions.routingActions.showEditGradesAverageSettings.call,
        );
      },
      connect: (state) {
        return GradesPageViewModel.from(state, AppLocalizations.of(context));
      },
    );
  }
}

abstract class GradesPageViewModel
    implements Built<GradesPageViewModel, GradesPageViewModelBuilder> {
  Semester get showSemester;

  String get allSubjectsAverage;
  String? get lastFetchedMessage;
  bool get loading;
  bool get showGradesDiagram;
  bool get showAllSubjectsAverage;
  bool get hasData;
  bool get noInternet;

  factory GradesPageViewModel(
          [void Function(GradesPageViewModelBuilder)? updates]) =
      _$GradesPageViewModel;
  GradesPageViewModel._();

  factory GradesPageViewModel.from(
    AppState state,
    AppLocalizations localizations,
  ) {
    return GradesPageViewModel(
      (b) => b
        ..showSemester = state.gradesState.semester.toBuilder()
        ..loading = state.gradesState.loading
        ..allSubjectsAverage = appSelectors.allSubjectsAverage(state)
        ..hasData = appSelectors.hasGradesData(state)
        ..noInternet = state.noInternet
        ..showGradesDiagram = state.settingsState.showGradesDiagram
        ..showAllSubjectsAverage = state.settingsState.showAllSubjectsAverage
        ..lastFetchedMessage = _lastFetchedMessage(state, localizations),
    );
  }
}

String? _lastFetchedMessage(AppState state, AppLocalizations localizations) {
  if (state.gradesState.subjects.isEmpty) {
    return null;
  }
  final timeAgoString = formatTimeAgoPerSemester(
    localizations: localizations,
    noInternet: state.noInternet,
    lastFetched: state.gradesState.subjects.first.lastFetchedBasic,
    semester: state.gradesState.semester,
  );
  if (timeAgoString == null) {
    return null;
  }
  return localizations.text(
    'grades.offlineMode',
    args: {'time': timeAgoString},
  );
}

String? formatTimeAgoPerSemester({
  required AppLocalizations localizations,
  required bool noInternet,
  required BuiltMap<Semester, UtcDateTime>? lastFetched,
  required Semester semester,
}) {
  if (lastFetched == null || !noInternet) {
    return null;
  }
  final String lastFetchedFormatted;
  if (semester == Semester.all) {
    final first = lastFetched[Semester.first];
    final second = lastFetched[Semester.second];
    if (first == null || second == null) {
      return null;
    }
    final firstFormatted = localizations.formatTimeAgo(first);
    final secondFormatted = localizations.formatTimeAgo(second);
    if (firstFormatted != secondFormatted) {
      return localizations.text(
        'grades.lastFetched.multiple',
        args: {
          'first': firstFormatted,
          'firstSemester': localizations.semesterLabel(Semester.first),
          'second': secondFormatted,
          'secondSemester': localizations.semesterLabel(Semester.second),
        },
      );
    }
    lastFetchedFormatted = firstFormatted;
  } else {
    final last = lastFetched[semester];
    if (last == null) {
      return null;
    }
    lastFetchedFormatted = localizations.formatTimeAgo(last);
  }
  return localizations.text(
    'grades.lastFetched.single',
    args: {'time': lastFetchedFormatted},
  );
}
