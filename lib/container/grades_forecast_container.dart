import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_forecast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class GradesForecastContainer extends StatelessWidget {
  const GradesForecastContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => AnimatedBuilder(
        animation: appClock,
        builder: (context, _) {
          final forecast = calculateGradeForecast(
            subjects: state.gradesState.subjects,
            semester: state.gradesState.semester,
            ignoredSubjects: state.settingsState.ignoreForGradesAverage,
          );
          return _GradesForecastCard(forecast: forecast);
        },
      ),
    );
  }
}

class _GradesForecastCard extends StatelessWidget {
  const _GradesForecastCard({required this.forecast});
  final GradeForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = forecast == null
        ? const Text(
            'Für eine zuverlässige Prognose werden noch weitere Noten benötigt.')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _line(context, 'Aktueller Schnitt',
                  _format(forecast!.currentAverage)),
              _line(context, 'Prognose Schuljahresende',
                  'ca. ${_format(forecast!.predictedAverage)}'),
              _line(context, 'Trend', _trendLabel(forecast!)),
              const SizedBox(height: 4),
              Text(
                'Statistische Einschätzung – zukünftige Noten können den tatsächlichen Schnitt verändern.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schnitt-Prognose', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }

  static Widget _line(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ]),
      );

  static String _format(double value) =>
      (value / 100).toStringAsFixed(1).replaceAll('.', ',');

  static String _trendLabel(GradeForecast forecast) {
    final direction = switch (forecast.trend) {
      GradeForecastTrend.rising => 'Steigend',
      GradeForecastTrend.falling => 'Fallend',
      GradeForecastTrend.stable => 'Stabil',
    };
    final change = forecast.changePerMonth / 100;
    if (forecast.trend == GradeForecastTrend.stable) return direction;
    return '$direction (${change >= 0 ? '+' : ''}${change.toStringAsFixed(1).replaceAll('.', ',')} / Monat)';
  }
}
