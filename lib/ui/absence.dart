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
            if (vm.onJustify != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final submission =
                      await showDialog<_AbsenceJustificationSubmission>(
                    context: context,
                    builder: (_) => const _AbsenceJustificationDialog(),
                  );
                  if (submission != null) {
                    vm.onJustify!(
                      submission.reason,
                      submission.signature,
                    );
                  }
                },
                icon: const Icon(Icons.verified_outlined),
                label: Text(context.t('absences.justification.action')),
              ),
            ],
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

class _AbsenceJustificationDialog extends StatefulWidget {
  const _AbsenceJustificationDialog();

  @override
  State<_AbsenceJustificationDialog> createState() =>
      _AbsenceJustificationDialogState();
}

class _AbsenceJustificationDialogState
    extends State<_AbsenceJustificationDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();

  bool get _validInput =>
      _reasonController.text.trim().isNotEmpty &&
      _signatureController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reasonController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.text('absences.justification.dialog.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: l10n.text('absences.justification.dialog.reason'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signatureController,
              decoration: InputDecoration(
                labelText: l10n.text('absences.justification.dialog.signature'),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.text('common.cancel')),
        ),
        ElevatedButton(
          onPressed: _validInput
              ? () {
                  Navigator.of(context).pop(
                    _AbsenceJustificationSubmission(
                      reason: _reasonController.text.trim(),
                      signature: _signatureController.text.trim(),
                    ),
                  );
                }
              : null,
          child: Text(l10n.text('button.save')),
        ),
      ],
    );
  }
}

class _AbsenceJustificationSubmission {
  final String reason;
  final String signature;

  const _AbsenceJustificationSubmission({
    required this.reason,
    required this.signature,
  });
}
