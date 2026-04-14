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
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/absence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';

class AbsenceGroupContainer extends StatelessWidget {
  final int group;

  const AbsenceGroupContainer({
    super.key,
    required this.group,
  });
  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, _AbsenceGroupViewModel>(
      builder: (context, vm, actions) {
        final l10n = context.l10n;
        final localeTag = Localizations.localeOf(context).toLanguageTag();
        final absenceGroup = vm.group;
        final first = absenceGroup.absences.last; //<--- flip is intentional
        final last = absenceGroup.absences.first; //<---
        var fromTo = "";
        if (first.date == last.date) {
          fromTo +=
              "${DateFormat("EE d.M.yyyy", localeTag).format(first.date)}, ";
          if (first == last) {
            fromTo += l10n.text(
              'absences.range.singleHour',
              args: {'hour': first.hour.toString()},
            );
          } else {
            fromTo += l10n.text(
              'absences.range.hourSpan',
              args: {
                'startHour': first.hour.toString(),
                'endHour': last.hour.toString(),
              },
            );
          }
        } else {
          fromTo += l10n.text(
            'absences.range.multiDay',
            args: {
              'startDate':
                  DateFormat("EE d.M.yyyy", localeTag).format(first.date),
              'startHour': first.hour.toString(),
              'endDate': DateFormat("EE d.M.yyyy", localeTag).format(last.date),
              'endHour': last.hour.toString(),
            },
          );
        }

        final durationParts = <String>[];
        if (absenceGroup.hours != 0) {
          durationParts.add(
            l10n.text(
              'absences.duration.lessons',
              args: {'value': absenceGroup.hours.toString()},
            ),
          );
        }
        if (absenceGroup.minutes != 0) {
          durationParts.add(
            l10n.text(
              'absences.duration.minutes',
              args: {'value': absenceGroup.minutes.toString()},
            ),
          );
        }

        final justifiedString = switch (absenceGroup.justified) {
          AbsenceJustified.justified => absenceGroup.reasonSignature != null &&
                  absenceGroup.reasonTimestamp != null
              ? l10n.text(
                  'absences.justification.recordedBy',
                  args: {
                    'timestamp': DateFormat(
                      "EEE d.M.yyyy HH:mm",
                      localeTag,
                    ).format(absenceGroup.reasonTimestamp!),
                    'signature': absenceGroup.reasonSignature!,
                  },
                )
              : l10n.text('absences.status.justified'),
          AbsenceJustified.forSchool =>
            l10n.text('absences.justification.schoolJustified'),
          AbsenceJustified.notJustified =>
            l10n.text('absences.status.notJustified'),
          _ => l10n.text('absences.justification.notYet'),
        };

        return AbsenceGroupWidget(
          vm: AbsencesViewModel(
            fromTo: fromTo,
            duration: durationParts.join(', '),
            justifiedString: justifiedString,
            reason: absenceGroup.reason,
            justified: absenceGroup.justified,
            note: absenceGroup.note,
            onJustify: vm.canJustify
                ? (reason, signature) {
                    actions.absencesActions.justifyAbsence(
                      <String, dynamic>{
                        'absenceGroup': absenceGroup,
                        'reason': reason,
                        'signature': signature,
                      },
                    );
                  }
                : null,
          ),
        );
      },
      connect: (state) {
        final absenceGroup = state.absencesState.absences[group];
        final canJustify = state.absencesState.canEdit &&
            absenceGroup.justified == AbsenceJustified.notYetJustified &&
            absenceGroup.reason == null &&
            absenceGroup.reasonSignature == null &&
            absenceGroup.reasonTimestamp == null &&
            absenceGroup.reasonUser == null;
        return _AbsenceGroupViewModel(
          group: absenceGroup,
          canJustify: canJustify,
        );
      },
    );
  }
}

class AbsencesViewModel {
  final String fromTo;
  final String duration;
  final String justifiedString;
  final String? reason;
  final String? note;
  final AbsenceJustified justified;
  final void Function(String reason, String signature)? onJustify;

  const AbsencesViewModel({
    required this.fromTo,
    required this.duration,
    required this.justifiedString,
    required this.reason,
    required this.justified,
    required this.note,
    required this.onJustify,
  });
}

class _AbsenceGroupViewModel {
  final AbsenceGroup group;
  final bool canJustify;

  const _AbsenceGroupViewModel({
    required this.group,
    required this.canJustify,
  });
}
