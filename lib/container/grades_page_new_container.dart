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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/grades_page_new.dart';
import 'package:flutter/material.dart' hide Builder;
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// What the page of the new design shows: the same view models as Legacy, and
/// whether grades are coloured, which has a different default here. Grades are
/// colourful unless the switch was turned off, as on the banners.
typedef NewGradesViewModel = ({
  GradesPageViewModel page,
  SortedGradesViewModel list,
  bool colorGrades,
});

/// The grades page of the new design, on the state and actions of Legacy.
class NewGradesPageContainer extends StatelessWidget {
  const NewGradesPageContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, NewGradesViewModel>(
      connect: (state) => (
        page: GradesPageViewModel.from(state, AppLocalizations.of(context)),
        list: SortedGradesViewModel.from(state),
        colorGrades: !state.settingsState.gradeColorsTurnedOff,
      ),
      builder: (context, vm, actions) => GradesPageNew(
        vm: vm,
        callbacks: GradesPageCallbacks(
          changeSemester: actions.gradesActions.setSemester.call,
          showGradesSettings:
              actions.routingActions.showEditGradesAverageSettings.call,
          showGradesChart: actions.routingActions.showGradesChart.call,
          showGradeCalculator: actions.routingActions.showGradeCalculator.call,
          setSortByType: actions.settingsActions.gradesTypeSorted.call,
          setShowCancelled: actions.settingsActions.showCancelledGrades.call,
          setColorGrades: actions.settingsActions.colorGrades.call,
          retry: () async {
            await actions.refreshNoInternet();
            await actions.gradesActions.load(vm.page.showSemester);
          },
          viewSubjectDetail: (Subject subject) =>
              actions.gradesActions.loadDetails(
            LoadSubjectDetailsPayload(
              (b) => b
                ..subject = subject.toBuilder()
                ..semester = vm.list.semester.toBuilder(),
            ),
          ),
        ),
      ),
    );
  }
}
