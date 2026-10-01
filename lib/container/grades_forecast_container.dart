import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_forecast.dart';
import 'package:dr/i18n/app_localizations.dart';
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
        builder: (context, _) => _GradesForecastRow(
          forecast: calculateGradeForecast(
            subjects: state.gradesState.subjects,
            semester: state.gradesState.semester,
            ignoredSubjects: state.settingsState.ignoreForGradesAverage,
          ),
        ),
      ),
    );
  }
}

class _GradesForecastRow extends StatelessWidget {
  const _GradesForecastRow({required this.forecast});
  final GradeForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final value = forecast == null
        ? '—'
        : context.l10n.text('grades.forecast.value',
            args: {'value': _format(forecast!.predictedAverage)});
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(context.l10n.text('grades.forecast'),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: context.l10n.text('grades.forecast.info'),
              onPressed: () => _showExplanation(context),
            ),
            SizedBox(
              width: 112,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child:
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showExplanation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('grades.forecast')),
        content: Text(context.l10n.text('grades.forecast.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.text('ui.close')),
          ),
        ],
      ),
    );
  }

  static String _format(double value) =>
      (value / 100).toStringAsFixed(1).replaceAll('.', ',');
}
