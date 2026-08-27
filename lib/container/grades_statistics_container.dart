import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

class GradesStatisticsContainer extends StatelessWidget {
  const GradesStatisticsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) => AnimatedBuilder(
        animation: appClock,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.bar_chart_rounded)),
              title: const Text('Notenstatistik'),
              subtitle: const Text('Vergleich deiner Fach-Durchschnitte'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _show(context, state),
            ),
          ),
        ),
      ),
    );
  }

  static void _show(BuildContext context, AppState state) {
    final stats = calculateGradeStatistics(
      subjects: state.gradesState.subjects,
      semester: state.gradesState.semester,
      ignoredSubjects: state.settingsState.ignoreForGradesAverage,
    );
    showDialog<void>(
      context: context,
      builder: (_) => _StatisticsDialog(stats: stats),
    );
  }
}

class _StatisticsDialog extends StatelessWidget {
  const _StatisticsDialog({required this.stats});
  final GradeStatistics stats;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
      title: Row(
        children: [
          const Expanded(child: Text('Notenstatistik')),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Erklärung',
            onPressed: () => _showExplanation(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: stats.subjectAverages.isEmpty
            ? const _EmptyStatistics()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionCard(
                      icon: Icons.leaderboard_outlined,
                      title: 'Fächervergleich',
                      child: _SubjectBars(values: stats.subjectAverages),
                    ),
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

  static void _showExplanation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('So werden die Statistiken berechnet'),
        content: const Text(
          'Der Fächervergleich zeigt den gewichteten Durchschnitt jedes Fachs im aktuell ausgewählten Semester. '
          'Stornierte, leere sowie Noten nach dem aktuellen Datum werden nicht berücksichtigt. '
          'Im Demo-Modus ist damit auch das simulierte Datum wirksam.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      );
}

class _SubjectBars extends StatelessWidget {
  const _SubjectBars({required this.values});
  final List<SubjectStatistic> values;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                  width: 112,
                  child: Text(value.name, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: value.average / 1000,
                      minHeight: 12,
                      color: _gradeColor(value.average),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 32, child: Text(_format(value.average))),
              ]),
            ),
        ],
      );
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_outlined, size: 44),
          SizedBox(height: 12),
          Text('Noch keine gültigen Noten für Statistiken vorhanden.'),
        ]),
      );
}

Color _gradeColor(double value) {
  if (value >= 800) return Colors.green;
  if (value >= 600) return Colors.amber.shade800;
  return Colors.red;
}

String _format(double value) =>
    (value / 100).toStringAsFixed(1).replaceAll('.', ',');
