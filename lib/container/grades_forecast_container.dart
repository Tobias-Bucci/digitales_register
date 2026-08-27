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
    final value =
        forecast == null ? '—' : 'ca. ${_format(forecast!.predictedAverage)}';
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 2),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text('Schnitt-Prognose',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Informationen zur Schnitt-Prognose',
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
        title: const Text('Schnitt-Prognose'),
        content: const Text(
          'Die Prognose ist eine statistische Einschätzung und keine offizielle Zeugnisnote. '
          'Dafür werden deine gültigen, gewichteten Noten dieses Schuljahres chronologisch ausgewertet. '
          'Aus den kumulierten Durchschnittswerten wird ein linearer Trend bis zum Schuljahresende hochgerechnet. '
          'Mindestens vier Noten an drei verschiedenen Tagen sind nötig. Neue Noten können das Ergebnis jederzeit verändern.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  static String _format(double value) =>
      (value / 100).toStringAsFixed(1).replaceAll('.', ',');
}
