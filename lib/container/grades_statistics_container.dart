import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/grade_statistics.dart';
import 'package:dr/i18n/app_localizations.dart';
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
              leading: const CircleAvatar(
                  child: Icon(Icons.bar_chart_rounded)),
              title: Text(context.l10n.text('grades.statistics')),
              subtitle: Text(context.l10n.text('grades.statistics.subtitle')),
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
          Expanded(child: Text(context.l10n.text('grades.statistics'))),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: context.l10n.text('grades.statistics.explanation'),
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
                      title: context.l10n.text('grades.statistics.subjects'),
                      child: _SubjectBars(values: stats.subjectAverages),
                    ),
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

  static void _showExplanation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('grades.statistics.how')),
        content: Text(context.l10n.text('grades.statistics.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.text('ui.understood')),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bar_chart_outlined, size: 44),
          const SizedBox(height: 12),
          Text(context.l10n.text('grades.statistics.empty')),
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
