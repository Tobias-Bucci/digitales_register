import 'package:dr/actions/app_actions.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_history.dart';
import 'package:dr/i18n/app_localizations.dart';
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
          tooltip: context.l10n.text('tutorial.step.gradeHistory.title'),
          onPressed: () => _showHistory(context, state),
        ),
      ),
    );
  }

  static void _showHistory(BuildContext context, AppState state) {
    AnalyticsService.product
        .event('tab_changed', {'feature': 'grades', 'tab_id': 'history'});
    AnalyticsService.product.event(
        'feature_action', {'feature': 'grades', 'action': 'change_view'});
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
      title: Text(context.l10n.text('tutorial.step.gradeHistory.title')),
      content: SizedBox(
        width: 520,
        child: data == null
            ? Text(context.l10n.text('grades.history.empty'))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${context.l10n.semesterLabel(data.previousSemester)} → ${context.l10n.semesterLabel(data.currentSemester)}',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    if (data.change == null)
                      Text(context.l10n.text('grades.history.incomplete'))
                    else
                      Text(_changeText(context, data.change!),
                          style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (data.subjects.isEmpty)
                      Text(context.l10n.text('grades.history.noSubjects'))
                    else
                      ...data.subjects.map((subject) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(subject.subject),
                            subtitle: Text(
                              context.l10n.text('grades.history.values', args: {
                                'previous': _format(subject.previous),
                                'current': _format(subject.current)
                              }),
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
          child: Text(context.l10n.text('ui.close')),
        ),
      ],
    );
  }

  static String _changeText(BuildContext context, double change) {
    if (change.abs() < 0.005) {
      return context.l10n.text('grades.history.unchanged');
    }
    return context.l10n.text(
        change > 0 ? 'grades.history.better' : 'grades.history.worse',
        args: {'value': _format(change.abs())});
  }

  static String _format(double value) =>
      (value / 100).toStringAsFixed(1).replaceAll('.', ',');
}
