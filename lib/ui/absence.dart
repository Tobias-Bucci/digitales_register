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

import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AbsenceGroupWidget extends StatelessWidget {
  final AbsencesViewModel vm;

  const AbsenceGroupWidget({super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    const divider = Row(
      children: [
        Spacer(),
        Flexible(
          flex: 48,
          child: Divider(
            height: 8,
          ),
        ),
        Spacer(),
      ],
    );

    return Card(
      shape: RoundedRectangleBorder(
        side: vm.justified == AbsenceJustified.notYetJustified ||
                vm.justified == AbsenceJustified.notJustified
            ? const BorderSide(color: Colors.red)
            : const BorderSide(color: Colors.green, width: 0),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            if (vm.reason != null) ...[
              Text(vm.reason!, style: bodyStyle),
              divider,
            ],
            if (vm.note != null) ...[
              Text(vm.note!, style: bodyStyle),
              divider,
            ],
            Text(
              vm.fromTo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              vm.duration,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            divider,
            Text(
              vm.justifiedString,
              style: bodyStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class FutureAbsenceWidget extends StatelessWidget {
  final FutureAbsence absence;
  final VoidCallback? onRemove;
  const FutureAbsenceWidget({
    super.key,
    required this.absence,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    var fromTo = "";
    if (absence.startDate == absence.endDate) {
      fromTo +=
          "${DateFormat("EE d.M.yyyy", localeTag).format(absence.startDate)}, ";
      if (absence.startHour == absence.endHour) {
        fromTo += "${absence.startHour}. h";
      } else {
        fromTo += "${absence.startHour}. - ${absence.endHour}. h";
      }
    } else {
      fromTo +=
          "${DateFormat("EE d.M.yyyy", localeTag).format(absence.startDate)} ${absence.startHour}. h - ${DateFormat("EE d.M.yyyy", localeTag).format(absence.endDate)} ${absence.endHour}. h ";
    }
    final justifiedString = l10n.absenceJustificationLabel(absence.justified);

    const divider = Row(
      children: [
        Spacer(),
        Flexible(
          flex: 48,
          child: Divider(
            height: 8,
          ),
        ),
        Spacer(),
      ],
    );

    return Card(
      shape: RoundedRectangleBorder(
        side: absence.justified == AbsenceJustified.notYetJustified ||
                absence.justified == AbsenceJustified.notJustified
            ? const BorderSide(color: Colors.red)
            : const BorderSide(color: Colors.green, width: 0),
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.transparent,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: onRemove != null && absence.id != null ? 30 : 0,
                right: onRemove != null && absence.id != null ? 30 : 0,
              ),
              child: Column(
                children: <Widget>[
                  if (absence.note != null) ...[
                    Text(absence.note!, style: bodyStyle),
                    divider,
                  ],
                  if (absence.reason != null) ...[
                    Text(absence.reason!, style: bodyStyle),
                    divider,
                  ],
                  Text(
                    fromTo,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  divider,
                  if (absence.reasonTimestamp != null &&
                      absence.reasonSignature != null)
                    Text(
                      l10n.formatAbsenceSignature(
                        absence.reasonTimestamp!,
                        absence.reasonSignature!,
                      ),
                      style: bodyStyle,
                      textAlign: TextAlign.center,
                    ),
                  divider,
                  Text(justifiedString, style: bodyStyle),
                ],
              ),
            ),
            if (onRemove != null && absence.id != null)
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: l10n.text('absences.future.delete'),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
