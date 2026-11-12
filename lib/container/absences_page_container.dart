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
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absences_page.dart';
import 'package:dr/ui/absences_page_new.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class AbsencesPageContainer extends StatelessWidget {
  const AbsencesPageContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, (AbsencesState, bool)>(
      builder: (context, vm, actions) {
        void onAddFutureAbsence(Map<String, dynamic> payload) {
          actions.absencesActions.addFutureAbsence(payload);
        }

        void onRemoveFutureAbsence(FutureAbsence absence) {
          actions.absencesActions.removeFutureAbsence(absence);
        }

        // Below the navigation of the new design. The setting decides about
        // that, so this follows a switch of the design at once.
        if (ResponsiveNavigationScope.isActive(context)) {
          return AbsencesPageNew(
            state: vm.$1,
            noInternet: vm.$2,
            onAddFutureAbsence: onAddFutureAbsence,
            onRemoveFutureAbsence: onRemoveFutureAbsence,
            onRetry: actions.absencesActions.load.call,
          );
        }
        return AbsencesPage(
          state: vm.$1,
          noInternet: vm.$2,
          onAddFutureAbsence: onAddFutureAbsence,
          onRemoveFutureAbsence: onRemoveFutureAbsence,
          onRetry: actions.absencesActions.load.call,
        );
      },
      connect: (state) {
        return (state.absencesState, state.noInternet);
      },
    );
  }
}
