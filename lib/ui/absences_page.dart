// Copyright (C) 2021 Michael Debertol
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
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class AbsencesPage extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final void Function(Map<String, dynamic>) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;

  const AbsencesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Absenzen"),
      ),
      body: LastFetchedOverlay(
        lastFetched: state.lastFetched,
        noInternet: noInternet,
        child: AbsencesBody(
          state: state,
          noInternet: noInternet,
          onAddFutureAbsence: onAddFutureAbsence,
          onRemoveFutureAbsence: onRemoveFutureAbsence,
        ),
      ),
    );
  }
}

class AbsencesBody extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final void Function(Map<String, dynamic>) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;

  const AbsencesBody({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
  });

  @override
  Widget build(BuildContext context) {
    return state.statistic != null
        ? state.absences.isEmpty && state.futureAbsences.isEmpty
            ? Center(
                child: Text(
                  "Noch keine Absenzen",
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(children: <Widget>[
                if (state.canEdit)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: noInternet
                            ? null
                            : () async {
                                final payload =
                                    await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (_) => const _FutureAbsenceDialog(),
                                );
                                if (payload != null) {
                                  onAddFutureAbsence(payload);
                                }
                              },
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Voraus-Absenz'),
                      ),
                    ),
                  ),
                AbsencesStatisticWidget(
                  stat: state.statistic!,
                ),
                const Divider(height: 0),
                if (state.futureAbsences.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0).copyWith(top: 16),
                    child: Text(
                      "Im Voraus eingetragene Absenzen",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                for (final futureAbsence in state.futureAbsences)
                  FutureAbsenceWidget(
                    absence: futureAbsence,
                    onRemove: state.canEdit &&
                            futureAbsence.justified ==
                                AbsenceJustified.notYetJustified
                        ? () => onRemoveFutureAbsence(futureAbsence)
                        : null,
                  ),
                if (state.absences.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0).copyWith(top: 16),
                    child: Text(
                      "Absenzen",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ...List.generate(
                  state.absences.length,
                  (n) => AbsenceGroupContainer(
                    group: n,
                  ),
                ),
              ])
        : noInternet
            ? const NoInternet()
            : const Center(
                child: CircularProgressIndicator(),
              );
  }
}

class _FutureAbsenceDialog extends StatefulWidget {
  const _FutureAbsenceDialog();

  @override
  State<_FutureAbsenceDialog> createState() => _FutureAbsenceDialogState();
}

class _FutureAbsenceDialogState extends State<_FutureAbsenceDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  int _startTime = 1;
  int _endTime = 1;

  bool get _validInput =>
      _reasonController.text.trim().isNotEmpty &&
      _signatureController.text.trim().isNotEmpty;

  bool get _validRange {
    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      _startTime,
    );
    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      _endTime,
    );
    return !start.isAfter(end);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: const Text('Voraus-Absenz eintragen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Begründung *',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signatureController,
              decoration: const InputDecoration(
                labelText: 'Bestätigung (Name) *',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Startdatum'),
              subtitle: Text(DateFormat('dd.MM.yyyy').format(_startDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (picked != null) {
                  setState(() {
                    _startDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      _startDate.hour,
                      _startDate.minute,
                      _startDate.second,
                      _startDate.millisecond,
                      _startDate.microsecond,
                    );
                    if (_endDate.isBefore(_startDate)) {
                      _endDate = _startDate;
                    }
                  });
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enddatum'),
              subtitle: Text(DateFormat('dd.MM.yyyy').format(_endDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: _startDate,
                  lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                );
                if (picked != null) {
                  setState(() {
                    _endDate = DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      _endDate.hour,
                      _endDate.minute,
                      _endDate.second,
                      _endDate.millisecond,
                      _endDate.microsecond,
                    );
                  });
                }
              },
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _startTime,
                    decoration: const InputDecoration(labelText: 'Startstunde'),
                    items: List.generate(
                      20,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _startTime = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _endTime,
                    decoration: const InputDecoration(labelText: 'Endstunde'),
                    items: List.generate(
                      20,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _endTime = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (!_validRange)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Start muss vor oder gleich Ende sein.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _validInput && _validRange
              ? () {
                  final payload = {
                    'futureAbsence': {
                      'startDateObject': _startDate.toUtc().toIso8601String(),
                      'startTime': _startTime,
                      'endDateObject': _endDate.toUtc().toIso8601String(),
                      'endTime': _endTime,
                      'reason': _reasonController.text.trim(),
                      'reason_signature': _signatureController.text.trim(),
                      'startDate': dateFormat.format(_startDate),
                      'endDate': dateFormat.format(_endDate),
                    },
                  };
                  Navigator.of(context).pop(payload);
                }
              : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class AbsencesStatisticWidget extends StatelessWidget {
  final AbsenceStatistic stat;

  const AbsencesStatisticWidget({super.key, required this.stat});

  TextStyle? _valueStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text("Statistik"),
      children: <Widget>[
        if (stat.counter != null)
          ListTile(
            title: const Text("Absenzen"),
            trailing: Text(
              stat.counter.toString(),
              style: _valueStyle(context),
            ),
          ),
        if (stat.counterForSchool != null)
          ListTile(
            title: const Text("Absenzen im Auftrag der Schule"),
            trailing: Text(
              stat.counterForSchool.toString(),
              style: _valueStyle(context),
            ),
          ),
        if (stat.delayed != null)
          ListTile(
            title: const Text("Verspätungen"),
            trailing: Text(
              stat.delayed.toString(),
              style: _valueStyle(context),
            ),
          ),
        if (stat.justified != null)
          ListTile(
            title: const Text("Entschuldigte Absenzen"),
            trailing: Text(
              stat.justified.toString(),
              style: _valueStyle(context),
            ),
          ),
        if (stat.notJustified != null)
          ListTile(
            title: const Text("Nicht entschuldigte Absenzen"),
            trailing: Text(
              stat.notJustified.toString(),
              style: _valueStyle(context),
            ),
          ),
        if (stat.percentage != null)
          ListTile(
            title: const Text("Abwesenheit"),
            trailing: Text(
              "${stat.percentage} %",
              style: _valueStyle(context),
            ),
          ),
      ],
    );
  }
}
