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

import 'package:dr/app_state.dart';
import 'package:dr/container/grades_page_new_container.dart';
import 'package:dr/container/sorted_grades_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:flutter/material.dart';

/// What the page can do, which is the same as what Legacy can do.
@immutable
class GradesPageCallbacks {
  const GradesPageCallbacks({
    required this.changeSemester,
    required this.showGradesSettings,
    required this.showGradesChart,
    required this.showGradeCalculator,
    required this.setSortByType,
    required this.setShowCancelled,
    required this.setColorGrades,
    required this.retry,
    required this.viewSubjectDetail,
  });

  final ValueChanged<Semester> changeSemester;
  final VoidCallback showGradesSettings, showGradesChart, showGradeCalculator;
  final ValueChanged<bool> setSortByType, setShowCancelled, setColorGrades;
  final VoidCallback retry;
  final ValueChanged<Subject> viewSubjectDetail;
}

/// The grades page of the new design. Legacy keeps `GradesPage`.
class GradesPageNew extends StatelessWidget {
  const GradesPageNew({super.key, required this.vm, required this.callbacks});

  final NewGradesViewModel vm;
  final GradesPageCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: DashboardBackdrop(
        child: ListView(children: [SortedGradesContainer()]),
      ),
    );
  }
}
