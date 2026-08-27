import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class GradesHistoryContainer extends StatelessWidget {
  const GradesHistoryContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => AnimatedBuilder(
        animation: appClock,
        builder: (context, _) => IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Noten-Historie',
          onPressed: () => _showHistory(context, state),
        ),
      ),
    );
  }

  static void _showHistory(BuildContext context, AppState state) {
    final comparison = compareGradeSemesters(
      subjects: state.gradesState.subjects,
      currentSemester: Semester.second,
      previousSemester: Semester.first,
      ignoredSubjects: state.settingsState.ignoreForGradesAverage,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _HistoryDialog(comparison: comparison),
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.comparison});
  final GradeHistoryComparison? comparison;

  @override
  Widget build(BuildContext context) {
    final data = comparison;
    return AlertDialog(
      title: const Text('Noten-Historie'),
      content: SizedBox(
        width: 520,
        child: data == null
            ? const Text(
                'Für einen Vergleich sind noch keine historischen Noten vorhanden.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${data.previousSemester.name} → ${data.currentSemester.name}',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    if (data.change == null)
                      const Text(
                          'Für beide Zeiträume liegt noch kein vollständiger Durchschnitt vor.')
                    else
                      Text(_changeText(data.change!),
                          style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (data.subjects.isEmpty)
                      const Text(
                          'Es gibt noch kein Fach, das in beiden Zeiträumen vorhanden ist.')
                    else
                      ...data.subjects.map((subject) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(subject.subject),
                            subtitle: Text(
                              'Früher: ${_format(subject.previous)}  ·  Aktuell: ${_format(subject.current)}',
                            ),
                            trailing: Text(
                              '${subject.change >= 0 ? '+' : ''}${_format(subject.change)}',
                              style: TextStyle(
                                color: subject.change >= 0
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  static String _changeText(double change) {
    if (change.abs() < 0.005) return 'Gesamtschnitt: unverändert';
    return 'Gesamtschnitt: ${change > 0 ? 'besser' : 'schlechter'} um ${_format(change.abs())}';
  }

  static String _format(double value) =>
      (value / 100).toStringAsFixed(1).replaceAll('.', ',');
}
