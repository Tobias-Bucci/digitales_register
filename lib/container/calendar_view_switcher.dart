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

import 'dart:math' as math;

import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Merges the exam calendar into the calendar destination of the new design:
/// both pages show this toggle as the title of their app bar and stay on the
/// same destination. The selected segment names the page, so there is no
/// separate title text. It is the `titleWidget` of a `GlassPageHeader`, whose
/// heading gives screen readers the page title once; the segments stay
/// buttons of their own inside of it.
class CalendarViewSwitcher extends StatelessWidget {
  const CalendarViewSwitcher({super.key, required this.exams});

  /// Whether the exam calendar is the page that is open.
  final bool exams;

  /// The switcher does not stretch across wide app bars.
  static const double maxWidth = 360;

  /// Room left for the leading spacing and up to two actions, the most either
  /// page has. Both pages reserve the same room, so the switcher keeps its
  /// size and position when switching between them.
  static const double _reservedWidth = 16 + 16 + 2 * 48;

  @override
  Widget build(BuildContext context) {
    final budget = math.max(
      0.0,
      math.min(
        maxWidth,
        MediaQuery.sizeOf(context).width - _reservedWidth,
      ),
    );
    return StoreConnection<AppState, AppActions, bool>(
      connect: (_) => true,
      builder: (context, _, actions) => LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(budget, constraints.maxWidth),
            ),
            // Narrow phones and large text make the labels smaller instead
            // of cutting them off, like the semester switch of the grades.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: GlassSegmentedControl<bool>(
                key: const Key('calendar-view-switcher'),
                selected: exams,
                segments: [
                  GlassSegment(
                    value: false,
                    label: context.t('calendar.title'),
                    fullLabel: context.t('calendar.title'),
                  ),
                  GlassSegment(
                    value: true,
                    label: context.t('calendar.view.exams'),
                    fullLabel: context.t('calendar.view.exams'),
                  ),
                ],
                onChanged: (showExams) {
                  if (showExams) {
                    showExamCalendarPage();
                  } else {
                    actions.routingActions.showCalendar();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
