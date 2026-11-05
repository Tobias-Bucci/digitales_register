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
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// Merges the exam calendar into the calendar destination of the new design:
/// both pages show this toggle and stay on the same destination.
class CalendarViewSwitcher extends StatelessWidget
    implements PreferredSizeWidget {
  const CalendarViewSwitcher({super.key, required this.exams});

  /// Whether the exam calendar is the page that is open.
  final bool exams;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, bool>(
        connect: (_) => true,
        builder: (context, _, actions) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              key: const Key('calendar-view-switcher'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.calendar_view_week_outlined),
                  label: Text(
                    context.t('calendar.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.school_outlined),
                  label: Text(
                    context.t('calendar.view.exams'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {exams},
              onSelectionChanged: (selection) {
                if (selection.first) {
                  showExamCalendarPage();
                } else {
                  actions.routingActions.showCalendar();
                }
              },
            ),
          ),
        ),
      );
}
