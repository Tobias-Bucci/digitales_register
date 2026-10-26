import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_date.dart';
import 'package:dr/container/dashboard_register_cards.dart';
import 'package:dr/container/dashboard_study_plan.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/ui/dashboard_customize_dialog.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';

class DashboardCustomizeButton extends StatelessWidget {
  const DashboardCustomizeButton({super.key});

  @override
  Widget build(BuildContext context) => StoreConnection<AppState, AppActions,
          (BuiltList<String>, BuiltMap<String, int>)>(
        connect: (state) => (
          state.settingsState.dashboardItems,
          state.settingsState.dashboardItemSpans
        ),
        builder: (context, configuration, actions) => IconButton(
          tooltip: context.t('dashboard.customize.title'),
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => DashboardCustomizeDialog(
                items: configuration.$1,
                spans: configuration.$2.toMap(),
                onSave: actions.settingsActions.setDashboardConfiguration.call),
          ),
        ),
      );
}

/// Reads the same settings and absence data as the existing app screens.
class DashboardOverview extends StatelessWidget {
  const DashboardOverview(
      {super.key,
      required this.timeline,
      this.onOpenCalendarAt,
      this.onEditGradeDeadline,
      this.footer});
  final SchoolTimeline timeline;
  final Widget? footer;
  final Future<void> Function(DateTime)? onOpenCalendarAt;
  final Future<void> Function(GradeDeadline)? onEditGradeDeadline;

  @override
  Widget build(BuildContext context) => StoreConnection<
          AppState,
          AppActions,
          (
            BuiltList<String>,
            AbsencesState,
            bool,
            bool,
            bool,
            BuiltMap<String, int>
          )>(
        connect: (state) => (
          state.settingsState.dashboardItems,
          state.absencesState,
          state.noInternet,
          state.dashboardState.loading || state.loginState.loading,
          state.loginState.loggedIn,
          state.settingsState.dashboardItemSpans,
        ),
        builder: (context, vm, actions) => AnimatedBuilder(
            animation: TutorialService.of(context),
            builder: (context, _) {
              final tour = TutorialService.of(context);
              final configured = resolveDashboardItems(vm.$1);
              final items = [
                ...configured,
                if (tour.active &&
                    tour.step.key == 'deadlines' &&
                    !configured.contains(DashboardItem.gradingDeadline))
                  DashboardItem.gradingDeadline,
              ];
              final overview = SchoolCountdownOverview(
                timeline: timeline,
                items: items,
                spans: vm.$6.toMap(),
                loading: vm.$4,
                onOpenCalendarAt: onOpenCalendarAt,
                onEditGradeDeadline: onEditGradeDeadline,
                additionalCards: {
                  DashboardItem.gradeAverage: const DashboardGradeCard(),
                  DashboardItem.recentGrade:
                      const DashboardGradeCard(recent: true),
                  DashboardItem.nextAssessment:
                      const DashboardNextAssessmentCard(),
                  DashboardItem.studyPlan: const DashboardStudyPlanCard(),
                  DashboardItem.absences: DashboardAbsencesCard(
                    state: vm.$2,
                    noInternet: vm.$3,
                    load: vm.$5 ? actions.absencesActions.load.call : null,
                    open: actions.routingActions.showAbsences.call,
                  ),
                },
              );
              final controls = footer;
              if (controls == null) return overview;
              return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (items.isNotEmpty) ...[
                      overview,
                      const SizedBox(height: 10)
                    ],
                    controls,
                  ]);
            }),
      );
}

class DashboardAbsencesCard extends StatefulWidget {
  const DashboardAbsencesCard(
      {super.key,
      required this.state,
      this.noInternet = false,
      this.load,
      this.open});
  final AbsencesState state;
  final bool noInternet;
  final Future<void> Function()? load;
  final Future<void> Function()? open;

  @override
  State<DashboardAbsencesCard> createState() => _DashboardAbsencesCardState();
}

class _DashboardAbsencesCardState extends State<DashboardAbsencesCard> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DashboardAbsencesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.noInternet && !widget.noInternet) ||
        (oldWidget.load == null && widget.load != null)) {
      _load();
    }
  }

  void _load() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.noInternet && !widget.state.loading) {
        final load = widget.load;
        if (load != null) unawaited(load());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final serverStatistic = state.statistic;
    // Use the page's lesson-level classification when entries are available.
    // Retain the server counters for cached responses containing only
    // statistics.
    final hasEntries = state.absences.any((group) => group.absences.isNotEmpty);
    final statistic = hasEntries
        ? appSelectors.absenceStatistics(state).statistic
        : serverStatistic;
    final title = context.t('absences.title');
    if (state.loading && serverStatistic == null && state.absences.isEmpty) {
      return DashboardLoadingCard(title: title);
    }
    final hasData = serverStatistic != null ||
        state.lastFetched != null ||
        state.absences.isNotEmpty;
    // The server total keeps its meaning; missing values are not converted to
    // an invented zero.
    final counter = serverStatistic?.counter;
    final isEmpty = counter == 0 && state.futureAbsences.isEmpty;
    return DashboardSummaryCard(
      icon: Icons.event_busy_outlined,
      title: title,
      primaryText: '',
      primaryContent: _AbsencesSummary(
        counterText: counter == null
            ? context.t(hasData
                ? 'absences.status.noneValues'
                : 'dashboard.absences.noData')
            : context.t('dashboard.customize.absenceCount',
                args: {'count': '$counter'}),
        statistic: statistic,
        rate: _parseRate(serverStatistic?.percentage),
        empty: isEmpty,
      ),
      secondaryText: widget.noInternet
          ? context.t('dashboard.customize.offline')
          : state.loadFailed
              ? context.t('dashboard.customize.unavailable')
              : _statusText(context, statistic, counter),
      onTap: state.loadFailed && !widget.noInternet ? widget.load : widget.open,
    );
  }

  String _statusText(
      BuildContext context, AbsenceStatistic? statistic, int? counter) {
    final state = widget.state;
    if (counter == 0 && state.futureAbsences.isEmpty) {
      return context.t('dashboard.absences.emptyBody');
    }
    final today = calendarDate(appClock.now);
    final upcoming = state.futureAbsences
        .where((absence) => !calendarDate(absence.endDate).isBefore(today))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (upcoming.isNotEmpty) {
      final next = upcoming.first;
      final date = _formatShortDate(context, next.startDate);
      final reason = next.reason?.trim();
      return context.t('dashboard.absences.upcoming', args: {
        'date': reason == null || reason.isEmpty ? date : '$date · $reason',
      });
    }
    DateTime? lastDate;
    for (final group in state.absences) {
      final date = group.date;
      if (date != null && (lastDate == null || date.isAfter(lastDate))) {
        lastDate = date;
      }
    }
    if (lastDate != null) {
      return context.t('dashboard.absences.last',
          args: {'date': _formatShortDate(context, lastDate)});
    }
    if (statistic?.notJustified == 0) {
      return context.t('dashboard.absences.allJustified');
    }
    if (counter != null && statistic?.notJustified == null) {
      return context.t('absences.status.none');
    }
    return context.t('dashboard.absences.tapToOpen');
  }
}

double? _parseRate(String? percentage) {
  if (percentage == null) return null;
  final value = double.tryParse(percentage.replaceAll(',', '.').trim());
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

String _formatShortDate(BuildContext context, DateTime date) =>
    DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag())
        .format(date);

/// The absences card body: total, absence rate and per-status counters.
class _AbsencesSummary extends StatelessWidget {
  const _AbsencesSummary({
    required this.counterText,
    required this.statistic,
    required this.rate,
    required this.empty,
  });

  final String counterText;
  final AbsenceStatistic? statistic;
  final double? rate;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notJustified = statistic?.notJustified;
    final delayed = statistic?.delayed;
    final forSchool = statistic?.counterForSchool;
    final rate = this.rate;
    final chips = <Widget>[
      if (notJustified != null && (notJustified > 0 || !empty))
        _AbsenceChip(
          icon: notJustified > 0
              ? Icons.error_outline
              : Icons.check_circle_outline,
          text: context.t('dashboard.customize.unjustifiedCount',
              args: {'count': '$notJustified'}),
          foreground: notJustified > 0
              ? scheme.onErrorContainer
              : scheme.onSuccessContainer,
          background: notJustified > 0
              ? scheme.errorContainer
              : scheme.successContainer,
        ),
      if (delayed != null && delayed > 0)
        _AbsenceChip(
          icon: Icons.schedule_outlined,
          text: context
              .t('dashboard.absences.delayCount', args: {'count': '$delayed'}),
          foreground: scheme.onTertiaryContainer,
          background: scheme.tertiaryContainer,
        ),
      if (forSchool != null && forSchool > 0)
        _AbsenceChip(
          icon: Icons.school_outlined,
          text: context.t('dashboard.absences.schoolCount',
              args: {'count': '$forSchool'}),
          foreground: scheme.onSecondaryContainer,
          background: scheme.secondaryContainer,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (empty) ...[
              Icon(Icons.verified_outlined, size: 22, color: scheme.success),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                counterText,
                softWrap: true,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (rate != null) ...[
          const SizedBox(height: 6),
          Semantics(
            label: context.t('absences.metric.absenceRate'),
            value: '${_formatRate(context, rate)} %',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        // Rates of 25 % and more fill the bar; it is a hint,
                        // not a precise chart.
                        value: (rate / 25).clamp(0.0, 1.0),
                        color: rate >= 15 ? scheme.error : scheme.primary,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.t('dashboard.absences.rate',
                          args: {'percent': _formatRate(context, rate)}),
                      softWrap: true,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  static String _formatRate(BuildContext context, double rate) {
    final digits = rate < 10 ? 1 : 0;
    final text = rate.toStringAsFixed(digits);
    return Localizations.localeOf(context).languageCode == 'en'
        ? text
        : text.replaceAll('.', ',');
  }
}

class _AbsenceChip extends StatelessWidget {
  const _AbsenceChip({
    required this.icon,
    required this.text,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                softWrap: true,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
