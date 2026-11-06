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

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/grades_chart_container.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/ui/grades_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// The two averages of the semester and where they are heading.
class GradesOverviewCard extends StatelessWidget {
  const GradesOverviewCard({
    super.key,
    required this.semester,
    required this.average,
    required this.certificateAverage,
    required this.forecast,
    required this.colorGrades,
  });

  final Semester semester;

  /// As the state holds them, 7,64 or /.
  final String average, certificateAverage;
  final GradeForecast? forecast;
  final bool colorGrades;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return GlassCard(
      key: const Key('grades-overview'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.semesterLabel(semester),
            key: const Key('grades-overview-semester'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  key: const Key('grades-average'),
                  label: l10n.text('grades.average'),
                  value: average,
                  colorGrades: colorGrades,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Figure(
                  key: const Key('grades-certificate-average'),
                  label: l10n.text('grades.certificateAverage'),
                  value: certificateAverage,
                  colorGrades: colorGrades,
                  infoTooltip: l10n.text('grades.certificateAverage'),
                  onInfo: () => showCertificateAverageInfo(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _ForecastHint(forecast: forecast, colorGrades: colorGrades),
          ),
        ],
      ),
    );
  }
}

/// One average, large, with what it is below it.
class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.label,
    required this.value,
    required this.colorGrades,
    this.infoTooltip,
    this.onInfo,
  });

  final String label, value;
  final bool colorGrades;
  final String? infoTooltip;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = GradesFormat.of(context);
    final hundredths = parseAverageHundredths(value);
    final text = format.average(hundredths);
    final onInfo = this.onInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both figures stay on a line, with or without their button.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Semantics(
                label: format.spoken(text, hundredths),
                excludeSemantics: true,
                child: GradeBadge(
                  text: text,
                  hundredths: hundredths,
                  colorized: colorGrades,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              if (onInfo != null)
                IconButton(
                  tooltip: infoTooltip,
                  onPressed: onInfo,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The short version of the forecast. A tap opens the whole of it.
class _ForecastHint extends StatelessWidget {
  const _ForecastHint({required this.forecast, required this.colorGrades});

  static const _shape = StadiumBorder();

  final GradeForecast? forecast;
  final bool colorGrades;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final forecast = this.forecast;
    final text = forecast == null
        ? l10n.text('grades.forecast.none')
        : [
            l10n.text(
              'grades.forecast.short',
              args: {
                'value': l10n.text(
                  'grades.forecast.value',
                  args: {'value': format.estimate(forecast.predictedAverage)},
                ),
              },
            ),
            forecastTrendLabel(l10n, forecast.trend),
          ].join(' · ');
    void open() => showForecastPanel(
          context,
          forecast: forecast,
          colorGrades: colorGrades,
        );
    return GlassFocusRing(
      shape: _shape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.36),
        shape: _shape,
        child: Tooltip(
          message: l10n.text('grades.forecast.info'),
          child: InkWell(
            key: const Key('grades-forecast-hint'),
            customBorder: _shape,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            mouseCursor: NewDesignTheme.clickCursor,
            onTap: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      forecast == null
                          ? Icons.hourglass_empty_rounded
                          : forecastTrendIcon(forecast.trend),
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the chart has in it, for the legend below it.
typedef _ChartSubject = ({String name, int color});

/// The grades over time. A tap anywhere on the chart opens it in full screen,
/// where its details and the settings of each line are.
class GradesChartCard extends StatelessWidget {
  const GradesChartCard({
    super.key,
    required this.onOpen,
    this.chartHeight = 128,
  });

  /// How many subjects the legend names. The chart in full screen has them all.
  static const _legendLength = 6;

  final VoidCallback onOpen;
  final double chartHeight;

  @override
  Widget build(BuildContext context) =>
      StoreConnection<AppState, AppActions, BuiltList<_ChartSubject>>(
        connect: (state) => [
          for (final graph in appSelectors.chartGraphs(state).entries)
            if (graph.value.thick != 0 && graph.key.grades.isNotEmpty)
              (name: graph.key.name, color: graph.value.color),
        ].toBuiltList(),
        builder: (context, subjects, actions) =>
            _buildCard(context, subjects.toList()),
      );

  Widget _buildCard(BuildContext context, List<_ChartSubject> subjects) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      key: const Key('grades-chart'),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.text('grades.chart.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('grades-chart-open'),
                tooltip: l10n.text('grades.chart.open'),
                onPressed: onOpen,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
              ),
            ],
          ),
          if (subjects.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l10n.text('grades.chart.empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            SizedBox(
              height: chartHeight,
              child: Semantics(
                button: true,
                label: l10n.text(
                  'grades.chart.summary',
                  args: {'count': '${subjects.length}'},
                ),
                onTap: onOpen,
                excludeSemantics: true,
                child: const MouseRegion(
                  cursor: NewDesignTheme.clickCursor,
                  child: RepaintBoundary(
                    child: GradesChartContainer(isFullscreen: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ChartLegend(subjects: subjects),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.subjects});

  final List<_ChartSubject> subjects;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hidden = subjects.length - GradesChartCard._legendLength;
    return ExcludeSemantics(
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        children: [
          for (final subject in subjects.take(GradesChartCard._legendLength))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Color(subject.color),
                    shape: const CircleBorder(),
                  ),
                  child: const SizedBox.square(dimension: 8),
                ),
                const SizedBox(width: 4),
                Text(l10n.translateSubjectName(subject.name), style: style),
              ],
            ),
          if (hidden > 0) Text('+$hidden', style: style),
        ],
      ),
    );
  }
}
