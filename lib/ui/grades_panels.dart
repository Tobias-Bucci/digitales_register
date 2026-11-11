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
import 'package:dr/grade_forecast.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/grade_statistics.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:dr/ui/grades_format.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

/// The frame of everything the grades page opens: a sheet on phones, a centred
/// panel in wide windows, with a title and what scrolls below it.
typedef GradesPanel = GlassPanel;

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

/// A competence with its stars. Whatever the register sends that is no rating
/// is written out, as Legacy does.
class CompetenceLine extends StatelessWidget {
  const CompetenceLine({
    super.key,
    required this.competence,
    required this.scale,
    this.cancelled = false,
  });

  /// A larger scale is written out, so that a school cannot make this any size.
  static const _maxStars = 20;
  static const double _starSize = 14;

  final Competence competence;
  final int? scale;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = l10n.translateSchoolTerm(competence.typeName);
    final value = competence.grade;
    final scale = this.scale;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
    final String spoken;
    final Widget rating;
    if (value == null || value < 0) {
      spoken = '—';
      rating = Text(spoken, style: style);
    } else if (scale == null || scale <= 0) {
      spoken = '$value ★ / ?';
      rating = Text(spoken, style: style);
    } else if (value > scale) {
      spoken = '$value / $scale ?';
      rating = Text(spoken, style: style);
    } else {
      spoken = l10n.text(
        'grades.stars',
        args: {'value': '$value', 'scale': '$scale'},
      );
      rating = scale > _maxStars
          ? Text('$value / $scale ★', style: style)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var star = 0; star < scale; star++)
                  Icon(
                    star < value
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: _starSize,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            );
    }
    return Semantics(
      label: '$name, $spoken',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [Text(name, style: style), rating],
      ),
    );
  }
}

void showGradeDetailsPanel(
  BuildContext context, {
  required GradeDetail grade,
  required bool colorGrades,
  required int? competenceStarsScale,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-grade-panel'),
      title: grade.name.isEmpty
          ? context.l10n.translateSchoolTerm(grade.type)
          : grade.name,
      child: _GradeDetails(
        grade: grade,
        colorGrades: colorGrades,
        competenceStarsScale: competenceStarsScale,
      ),
    ),
  );
}

/// A label and its value, one below the other in the panels of a grade.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SelectableText(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _GradeDetails extends StatelessWidget {
  const _GradeDetails({
    required this.grade,
    required this.colorGrades,
    required this.competenceStarsScale,
  });

  final GradeDetail grade;
  final bool colorGrades;
  final int? competenceStarsScale;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final value = format.grade(grade.gradeFormatted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: l10n.text(
            'grades.spoken.grade',
            args: {'value': format.spoken(value, grade.grade)},
          ),
          excludeSemantics: true,
          child: GradeBadge(
            text: value,
            hundredths: grade.grade,
            colorized: colorGrades,
            cancelled: grade.cancelled,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Fact(
          l10n.text('grades.details.type'),
          l10n.translateSchoolTerm(grade.type),
        ),
        _Fact(l10n.text('grades.details.date'), format.longDate(grade.date)),
        _Fact(
          l10n.text('grades.details.weight'),
          format.weight(grade.weightPercentage),
        ),
        if (!grade.description.isNullOrEmpty)
          _Fact(l10n.text('grades.details.comment'), grade.description!),
        if (grade.cancelled)
          _Fact(
            l10n.text('grades.spoken.cancelled'),
            grade.cancelledDescription.isNullOrEmpty
                ? '—'
                : grade.cancelledDescription!,
          ),
        if (grade.competences.isNotEmpty) ...[
          Text(
            l10n.text('grades.details.competences'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final competence in grade.competences)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CompetenceLine(
                competence: competence,
                scale: competenceStarsScale,
                cancelled: grade.cancelled,
              ),
            ),
          const SizedBox(height: 4),
        ],
        Text(
          l10n.translateCreatedText(grade.created),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

void showObservationDetailsPanel(
  BuildContext context, {
  required Observation observation,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      final theme = Theme.of(context);
      final format = GradesFormat.of(context);
      return GradesPanel(
        key: const Key('grades-observation-panel'),
        title: l10n.translateSchoolTerm(observation.typeName),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Fact(
              l10n.text('grades.details.date'),
              format.longDate(observation.date),
            ),
            if (!observation.note.isNullOrEmpty)
              _Fact(l10n.text('grades.details.comment'), observation.note),
            Text(
              l10n.translateCreatedText(observation.created),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// How the grades are shown. The switches follow the state while this is open.
void showGradesDisplayPanel(
  BuildContext context, {
  required VoidCallback onShowAverageSettings,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-display-panel'),
      title: context.t('grades.view'),
      child: StoreConnection<AppState, AppActions, (bool, bool, bool)>(
        connect: (state) => (
          state.settingsState.typeSorted,
          state.settingsState.showCancelled,
          !state.settingsState.gradeColorsTurnedOff,
        ),
        builder: (context, vm, actions) {
          final l10n = context.l10n;
          Widget toggle(
            String key,
            String label,
            bool value,
            ValueChanged<bool> onChanged,
          ) =>
              SwitchListTile.adaptive(
                key: Key(key),
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: value,
                onChanged: onChanged,
              );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              toggle(
                'grades-sort-by-type',
                l10n.text('grades.sortByType'),
                vm.$1,
                actions.settingsActions.gradesTypeSorted.call,
              ),
              toggle(
                'grades-show-cancelled',
                l10n.text('grades.showDeleted'),
                vm.$2,
                actions.settingsActions.showCancelledGrades.call,
              ),
              toggle(
                'grades-color-grades',
                l10n.text('grades.colorGrades'),
                vm.$3,
                actions.settingsActions.colorGrades.call,
              ),
              ListTile(
                key: const Key('grades-average-settings'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.text('grades.averageSettings')),
                subtitle: Text(l10n.text('grades.averageSettings.subtitle')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).pop();
                  onShowAverageSettings();
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

void showStatisticsPanel(
  BuildContext context, {
  required GradeStatistics statistics,
  required bool colorGrades,
}) {
  showGlassSheet<void>(
    context: context,
    builder: (context) => GradesPanel(
      key: const Key('grades-statistics-panel'),
      title: context.t('grades.statistics'),
      child: _StatisticsDetails(
        statistics: statistics,
        colorGrades: colorGrades,
      ),
    ),
  );
}

class _StatisticsDetails extends StatelessWidget {
  const _StatisticsDetails({
    required this.statistics,
    required this.colorGrades,
  });

  static const double _barHeight = 8;

  final GradeStatistics statistics;
  final bool colorGrades;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = GradesFormat.of(context);
    final subjects = statistics.subjectAverages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subjects.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(l10n.text('grades.statistics.empty')),
          )
        else ...[
          Text(
            l10n.text('grades.statistics.subjects'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final subject in subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                label: '${l10n.translateSubjectName(subject.name)}, '
                    '${format.spoken(format.average(subject.average), subject.average)}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        l10n.translateSubjectName(subject.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_barHeight / 2),
                        child: LinearProgressIndicator(
                          value: subject.average / 1000,
                          minHeight: _barHeight,
                          color: (colorGrades
                                  ? gradeColor(subject.average)
                                  : null) ??
                              scheme.primary,
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      format.average(subject.average),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
        _PanelText(l10n.text('grades.statistics.body')),
      ],
    );
  }
}
