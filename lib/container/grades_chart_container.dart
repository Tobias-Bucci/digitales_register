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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/ui/grades_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class GradesChartContainer extends StatelessWidget {
  final bool isFullscreen;

  const GradesChartContainer({super.key, required this.isFullscreen});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions,
        Map<SubjectGrades, SubjectTheme>>(
      connect: appSelectors.chartGraphs,
      builder: (context, vm, actions) {
        return GradesChart(
          graphs: vm,
          isFullscreen: isFullscreen,
          goFullscreen: actions.routingActions.showGradesChart.call,
        );
      },
    );
  }
}
