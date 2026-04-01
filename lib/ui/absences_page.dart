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

import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/utc_date_time.dart';
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
    final statsVm =
        state.statistic != null ? appSelectors.absenceStatistics(state) : null;
    return state.statistic != null
        ? state.absences.isEmpty && state.futureAbsences.isEmpty
            ? Center(
                child: Text(
                  "Noch keine Absenzen",
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                children: <Widget>[
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
                                    builder: (_) =>
                                        const _FutureAbsenceDialog(),
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
                  AbsencesStatisticWidget(vm: statsVm!),
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
                    (n) => AbsenceGroupContainer(group: n),
                  ),
                ],
              )
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
                labelText: 'Begruendung *',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _signatureController,
              decoration: const InputDecoration(
                labelText: 'Bestaetigung (Name) *',
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
                    initialValue: _startTime,
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
                    initialValue: _endTime,
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

class AbsencesStatisticWidget extends StatefulWidget {
  final AbsenceStatsViewModel vm;

  const AbsencesStatisticWidget({super.key, required this.vm});

  @override
  State<AbsencesStatisticWidget> createState() =>
      _AbsencesStatisticWidgetState();
}

class _AbsencesStatisticWidgetState extends State<AbsencesStatisticWidget> {
  bool _expanded = false;
  bool _showPieChart = false;
  _HistorySelection? _selectedHistory;

  bool get _canShowPieChart {
    final raw = widget.vm.statistic.percentage?.replaceAll(',', '.');
    return double.tryParse(raw ?? '') != null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = <_AbsenceMetricData>[
      if (widget.vm.statistic.counter != null)
        _AbsenceMetricData(
          label: 'Absenzen',
          value: widget.vm.statistic.counter.toString(),
          icon: Icons.event_busy_outlined,
          accent: colorScheme.primary,
        ),
      if (widget.vm.statistic.notJustified != null)
        _AbsenceMetricData(
          label: 'Nicht entschuldigt',
          value: widget.vm.statistic.notJustified.toString(),
          icon: Icons.error_outline,
          accent: colorScheme.error,
        ),
      if (widget.vm.statistic.delayed != null)
        _AbsenceMetricData(
          label: 'Verspätungen',
          value: widget.vm.statistic.delayed.toString(),
          icon: Icons.schedule_outlined,
          accent: colorScheme.tertiary,
        ),
      if (widget.vm.statistic.percentage != null)
        _AbsenceMetricData(
          label: 'Abwesenheit',
          value: '${widget.vm.statistic.percentage} %',
          icon: Icons.pie_chart_outline,
          accent: colorScheme.secondary,
          actionLabel: _showPieChart ? 'Ausblenden' : 'Kreisdiagramm',
          onAction: _canShowPieChart
              ? () => setState(() => _showPieChart = !_showPieChart)
              : null,
        ),
      if (widget.vm.statistic.counterForSchool != null)
        _AbsenceMetricData(
          label: 'Im Auftrag der Schule',
          value: widget.vm.statistic.counterForSchool.toString(),
          icon: Icons.school_outlined,
          accent: colorScheme.tertiary,
        ),
    ];

    final statuses = <_AbsenceStatusData>[
      if (widget.vm.statistic.justified != null)
        _AbsenceStatusData(
          label: 'Entschuldigt',
          value: widget.vm.statistic.justified!,
          color: colorScheme.primary,
        ),
      if (widget.vm.statistic.notJustified != null)
        _AbsenceStatusData(
          label: 'Nicht entschuldigt',
          value: widget.vm.statistic.notJustified!,
          color: colorScheme.error,
        ),
      if (widget.vm.statistic.counterForSchool != null)
        _AbsenceStatusData(
          label: 'Schule',
          value: widget.vm.statistic.counterForSchool!,
          color: colorScheme.tertiary,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.all(8).copyWith(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Statistik',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0, -0.03),
                end: Offset.zero,
              ).animate(animation);
              return ClipRect(
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _expanded
                ? Padding(
                    key: const ValueKey('expanded-stats'),
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (metrics.isNotEmpty) ...[
                          _AbsenceMetricList(metrics: metrics),
                          const SizedBox(height: 12),
                        ],
                        if (_showPieChart && _canShowPieChart) ...[
                          _AbsencePercentagePieCard(vm: widget.vm),
                          const SizedBox(height: 12),
                        ],
                        _AbsenceStatusCard(statuses: statuses),
                        const SizedBox(height: 12),
                        _AbsenceHistoryCard(
                          vm: widget.vm,
                          selectedHistory: _selectedHistory,
                          onSelectionChanged: (selection) {
                            setState(() => _selectedHistory = selection);
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('collapsed-stats')),
          ),
        ],
      ),
    );
  }
}

class _AbsenceMetricList extends StatelessWidget {
  final List<_AbsenceMetricData> metrics;

  const _AbsenceMetricList({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              _AbsenceMetricRow(metric: metrics[i]),
              if (i != metrics.length - 1)
                Divider(height: 18, color: colorScheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbsenceMetricRow extends StatelessWidget {
  final _AbsenceMetricData metric;

  const _AbsenceMetricRow({required this.metric});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: metric.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(metric.icon, size: 16, color: metric.accent),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        if (metric.onAction != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: metric.onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text(metric.actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _AbsenceStatusCard extends StatelessWidget {
  final List<_AbsenceStatusData> statuses;

  const _AbsenceStatusCard({required this.statuses});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = statuses.fold<int>(0, (sum, status) => sum + status.value);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (statuses.isEmpty)
              Text(
                'Keine Statusdaten verfuegbar.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              if (total > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final status in statuses.where(
                          (status) => status.value > 0,
                        ))
                          Expanded(
                            flex: status.value,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: status.color),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  'Noch keine Statuswerte vorhanden.',
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final status in statuses)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: status.color.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: status.color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${status.label}: ${status.value}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbsenceHistoryCard extends StatelessWidget {
  final AbsenceStatsViewModel vm;
  final _HistorySelection? selectedHistory;
  final ValueChanged<_HistorySelection?> onSelectionChanged;

  const _AbsenceHistoryCard({
    required this.vm,
    required this.selectedHistory,
    required this.onSelectionChanged,
  });

  static charts.Color _toChartsColor(Color color) => charts.Color(
        r: (color.r * 255).round().clamp(0, 255),
        g: (color.g * 255).round().clamp(0, 255),
        b: (color.b * 255).round().clamp(0, 255),
        a: (color.a * 255).round().clamp(0, 255),
      );

  String _monthLabel(Locale locale, UtcDateTime month) {
    return DateFormat.MMM(locale.toLanguageTag()).format(month);
  }

  String _formatLessons(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    final darkMode = theme.brightness == Brightness.dark;
    final labelColor =
        darkMode ? charts.MaterialPalette.white : charts.MaterialPalette.black;
    final gridColor = darkMode
        ? charts.MaterialPalette.gray.shade600
        : charts.MaterialPalette.gray.shade300;
    final totalLessons = vm.monthlyHistory.fold<double>(
      0,
      (sum, entry) => sum + entry.lessons,
    );
    final series = [
      charts.Series<AbsenceMonthlyHistoryValue, String>(
        id: 'HistoricalAbsences',
        data: vm.monthlyHistory.toList(),
        domainFn: (entry, _) => _monthLabel(locale, entry.month),
        measureFn: (entry, _) => entry.lessons,
        colorFn: (_, __) => _toChartsColor(theme.colorScheme.primary),
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verlauf',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Verpasste Unterrichtseinheiten pro Monat',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: vm.hasHistoricalData
                  ? charts.BarChart(
                      series,
                      animate: false,
                      behaviors: [
                        charts.SelectNearest<String>(),
                      ],
                      selectionModels: [
                        charts.SelectionModelConfig<String>(
                          changedListener: (model) {
                            final selected = model.selectedDatum;
                            if (selected.isEmpty) {
                              onSelectionChanged(null);
                              return;
                            }
                            final datum = selected.first.datum
                                as AbsenceMonthlyHistoryValue;
                            onSelectionChanged(
                              _HistorySelection(
                                label: _monthLabel(locale, datum.month),
                                value: _formatLessons(datum.lessons),
                              ),
                            );
                          },
                        ),
                      ],
                      layoutConfig: charts.LayoutConfig(
                        topMarginSpec: charts.MarginSpec.fixedPixel(8),
                        rightMarginSpec: charts.MarginSpec.fixedPixel(8),
                        bottomMarginSpec: charts.MarginSpec.fixedPixel(
                          vm.monthlyHistory.length > 6 ? 36 : 20,
                        ),
                        leftMarginSpec: charts.MarginSpec.fixedPixel(28),
                      ),
                      defaultRenderer: charts.BarRendererConfig<String>(
                        maxBarWidthPx: 28,
                        cornerStrategy: const charts.ConstCornerStrategy(8),
                      ),
                      primaryMeasureAxis: charts.NumericAxisSpec(
                        renderSpec: charts.GridlineRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            fontSize: 10,
                            color: labelColor,
                          ),
                          lineStyle: charts.LineStyleSpec(
                            color: gridColor,
                            thickness: 1,
                          ),
                        ),
                      ),
                      domainAxis: charts.OrdinalAxisSpec(
                        renderSpec: charts.SmallTickRendererSpec(
                          labelStyle: charts.TextStyleSpec(
                            fontSize: 10,
                            color: labelColor,
                          ),
                          lineStyle: charts.LineStyleSpec(
                            thickness: 0,
                            color: gridColor,
                          ),
                          labelRotation: vm.monthlyHistory.length > 6 ? 45 : 0,
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        'Noch keine vergangenen Absenzen',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            if (vm.hasHistoricalData) ...[
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selectedHistory != null
                    ? Container(
                        key: ValueKey(selectedHistory!.label),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${selectedHistory!.label}: ${selectedHistory!.value}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (selectedHistory != null) const SizedBox(height: 8),
              Text(
                'Historische Summe: ${_formatLessons(totalLessons)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbsencePercentagePieCard extends StatelessWidget {
  final AbsenceStatsViewModel vm;

  const _AbsencePercentagePieCard({required this.vm});

  static charts.Color _toChartsColor(Color color) => charts.Color(
        r: (color.r * 255).round().clamp(0, 255),
        g: (color.g * 255).round().clamp(0, 255),
        b: (color.b * 255).round().clamp(0, 255),
        a: (color.a * 255).round().clamp(0, 255),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percentage =
        double.tryParse(vm.statistic.percentage!.replaceAll(',', '.')) ?? 0;
    final absent = percentage.clamp(0, 100).toDouble();
    final present = 100.0 - absent;
    final data = [
      _PieSliceData(
        label: 'Abwesend',
        value: absent,
        color: theme.colorScheme.secondary,
      ),
      _PieSliceData(
        label: 'Anwesend',
        value: present,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Abwesenheit im Verhaeltnis',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: charts.PieChart<String>(
                [
                  charts.Series<_PieSliceData, String>(
                    id: 'AbsencePercentage',
                    data: data,
                    domainFn: (slice, _) => slice.label,
                    measureFn: (slice, _) => slice.value,
                    colorFn: (slice, _) => _toChartsColor(slice.color),
                    labelAccessorFn: (slice, _) =>
                        '${slice.label}: ${slice.value.toStringAsFixed(1)} %',
                  ),
                ],
                animate: false,
                defaultRenderer: charts.ArcRendererConfig<String>(
                  arcWidth: 36,
                  arcRendererDecorators: isDark
                      ? const []
                      : [
                          charts.ArcLabelDecorator<String>(
                            insideLabelStyleSpec: charts.TextStyleSpec(
                              color:
                                  _toChartsColor(theme.colorScheme.onSecondary),
                              fontSize: 11,
                            ),
                            outsideLabelStyleSpec: charts.TextStyleSpec(
                              color:
                                  _toChartsColor(theme.colorScheme.onSurface),
                              fontSize: 11,
                            ),
                          ),
                        ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slice in data)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: slice.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: slice.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${slice.label}: ${slice.value.toStringAsFixed(1)} %',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AbsenceMetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _AbsenceMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });
}

class _AbsenceStatusData {
  final String label;
  final int value;
  final Color color;

  const _AbsenceStatusData({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _HistorySelection {
  final String label;
  final String value;

  const _HistorySelection({
    required this.label,
    required this.value,
  });
}

class _PieSliceData {
  final String label;
  final double value;
  final Color color;

  const _PieSliceData({
    required this.label,
    required this.value,
    required this.color,
  });
}
