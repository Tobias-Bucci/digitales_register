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

part of '../absences_page.dart';

// The statistics of the absences: status, history and share of lessons.

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
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = <_AbsenceMetricData>[
      if (widget.vm.statistic.counter != null)
        _AbsenceMetricData(
          label: l10n.text('absences.metric.absences'),
          value: widget.vm.statistic.counter.toString(),
          icon: Icons.event_busy_outlined,
          accent: colorScheme.primary,
        ),
      if (widget.vm.statistic.notJustified != null)
        _AbsenceMetricData(
          label: l10n.text('absences.metric.notJustified'),
          value: widget.vm.statistic.notJustified.toString(),
          icon: Icons.error_outline,
          accent: colorScheme.error,
        ),
      if (widget.vm.statistic.delayed != null)
        _AbsenceMetricData(
          label: l10n.text('absences.metric.delays'),
          value: widget.vm.statistic.delayed.toString(),
          icon: Icons.schedule_outlined,
          accent: colorScheme.tertiary,
        ),
      if (widget.vm.statistic.percentage != null)
        _AbsenceMetricData(
          label: l10n.text('absences.metric.absenceRate'),
          value: '${widget.vm.statistic.percentage} %',
          icon: Icons.pie_chart_outline,
          accent: colorScheme.secondary,
          actionLabel: _showPieChart
              ? l10n.text('absences.chart.hide')
              : l10n.text('absences.chart.pie'),
          onAction: _canShowPieChart
              ? () => setState(() => _showPieChart = !_showPieChart)
              : null,
        ),
      if (widget.vm.statistic.counterForSchool != null)
        _AbsenceMetricData(
          label: l10n.text('absences.metric.forSchool'),
          value: widget.vm.statistic.counterForSchool.toString(),
          icon: Icons.school_outlined,
          accent: colorScheme.tertiary,
        ),
    ];

    final statuses = <_AbsenceStatusData>[
      if (widget.vm.statistic.justified != null)
        _AbsenceStatusData(
          label: l10n.text('absences.status.justified'),
          value: widget.vm.statistic.justified!,
          color: colorScheme.primary,
        ),
      if (widget.vm.statistic.notJustified != null)
        _AbsenceStatusData(
          label: l10n.text('absences.status.notJustified'),
          value: widget.vm.statistic.notJustified!,
          color: colorScheme.error,
        ),
      if (widget.vm.statistic.counterForSchool != null)
        _AbsenceStatusData(
          label: l10n.text('absences.status.school'),
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
                      l10n.text('absences.statistics'),
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
                  alignment: Alignment.topCenter,
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
    final l10n = context.l10n;
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
              l10n.text('absences.status'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (statuses.isEmpty)
              Text(
                l10n.text('absences.status.none'),
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
                  l10n.text('absences.status.noneValues'),
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
    final l10n = context.l10n;
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
              l10n.text('absences.history'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.text('absences.history.subtitle'),
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
                        l10n.text('absences.history.none'),
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
                l10n.text(
                  'absences.history.total',
                  args: {'value': _formatLessons(totalLessons)},
                ),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percentage =
        double.tryParse(vm.statistic.percentage!.replaceAll(',', '.')) ?? 0;
    final absent = percentage.clamp(0, 100).toDouble();
    final present = 100.0 - absent;
    final data = [
      _PieSliceData(
        label: l10n.text('absences.pie.absent'),
        value: absent,
        color: theme.colorScheme.secondary,
      ),
      _PieSliceData(
        label: l10n.text('absences.pie.present'),
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
              l10n.text('absences.pie.title'),
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
