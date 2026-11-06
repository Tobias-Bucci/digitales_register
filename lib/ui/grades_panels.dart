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

import 'package:dr/grade_forecast.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:flutter/material.dart';

/// The frame of everything the grades page opens: a sheet on phones, a centred
/// panel in wide windows, with a title and what scrolls below it.
class GradesPanel extends StatelessWidget {
  const GradesPanel({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

/// Text that explains a value, for the sheets of the page.
class _PanelText extends StatelessWidget {
  const _PanelText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}

void showCertificateAverageInfo(BuildContext context) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-certificate-panel'),
      title: context.t('grades.certificateAverage'),
      child: _PanelText(context.t('grades.certificateAverageInfo')),
    ),
  );
}

/// The icon of a trend, which goes with its word.
IconData forecastTrendIcon(GradeForecastTrend trend) => switch (trend) {
      GradeForecastTrend.rising => Icons.trending_up_rounded,
      GradeForecastTrend.falling => Icons.trending_down_rounded,
      GradeForecastTrend.stable => Icons.trending_flat_rounded,
    };

String forecastTrendLabel(AppLocalizations l10n, GradeForecastTrend trend) =>
    l10n.text(switch (trend) {
      GradeForecastTrend.rising => 'grades.forecast.rising',
      GradeForecastTrend.falling => 'grades.forecast.falling',
      GradeForecastTrend.stable => 'grades.forecast.stable',
    });

void showForecastPanel(
  BuildContext context, {
  required GradeForecast? forecast,
  required bool colorGrades,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-forecast-panel'),
      title: context.t('grades.forecast'),
      child: _ForecastDetails(forecast: forecast, colorGrades: colorGrades),
    ),
  );
}

class _ForecastDetails extends StatelessWidget {
  const _ForecastDetails({required this.forecast, required this.colorGrades});

  final GradeForecast? forecast;
  final bool colorGrades;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final format = GradesFormat.of(context);
    final forecast = this.forecast;
    final style = theme.textTheme.titleLarge;
    Widget figure(String label, num hundredths, String value) => Expanded(
          child: Semantics(
            label: '$label ${format.spoken(value, hundredths)}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                GradeBadge(
                  text: value,
                  hundredths: hundredths,
                  colorized: colorGrades,
                  style: style,
                ),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (forecast == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(l10n.text('grades.forecast.none')),
          )
        else ...[
          Row(
            children: [
              figure(
                l10n.text('grades.forecast.current'),
                forecast.currentAverage,
                format.estimate(forecast.currentAverage),
              ),
              figure(
                l10n.text('grades.forecast'),
                forecast.predictedAverage,
                l10n.text(
                  'grades.forecast.value',
                  args: {'value': format.estimate(forecast.predictedAverage)},
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                forecastTrendIcon(forecast.trend),
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    forecastTrendLabel(l10n, forecast.trend),
                    l10n.text(
                      'grades.forecast.perMonth',
                      args: {'value': format.change(forecast.changePerMonth)},
                    ),
                    l10n.text(
                      'grades.forecast.basis',
                      args: {
                        'grades': '${forecast.gradeCount}',
                        'days': '${forecast.distinctDates}',
                      },
                    ),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _PanelText(l10n.text('grades.forecast.body')),
      ],
    );
  }
}

void showGradesHistoryPanel(
  BuildContext context, {
  required GradeHistoryComparison? comparison,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-history-panel'),
      title: context.t('grades.history.title'),
      child: _HistoryDetails(comparison: comparison),
    ),
  );
}

class _HistoryDetails extends StatelessWidget {
  const _HistoryDetails({required this.comparison});

  final GradeHistoryComparison? comparison;

  String _summary(AppLocalizations l10n, GradesFormat format, double change) {
    if (change.abs() < 0.005) return l10n.text('grades.history.unchanged');
    return l10n.text(
      change > 0 ? 'grades.history.better' : 'grades.history.worse',
      args: {'value': format.estimate(change.abs())},
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final data = comparison;
    if (data == null) return _PanelText(l10n.text('grades.history.empty'));
    final change = data.change;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.semesterLabel(data.previousSemester)} → '
          '${l10n.semesterLabel(data.currentSemester)}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          change == null
              ? l10n.text('grades.history.incomplete')
              : _summary(l10n, format, change),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (data.subjects.isEmpty)
          _PanelText(l10n.text('grades.history.noSubjects'))
        else
          for (final subject in data.subjects)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.translateSubjectName(subject.subject),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l10n.text('grades.history.values', args: {
                            'previous': format.estimate(subject.previous),
                            'current': format.estimate(subject.current),
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    format.change(subject.change),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color:
                          subject.change >= 0 ? scheme.success : scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
