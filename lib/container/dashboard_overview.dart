import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/dashboard_items.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/school_timeline.dart';
import 'package:dr/ui/dashboard_customize_dialog.dart';
import 'package:dr/ui/school_countdown_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';

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
        builder: (context, vm, actions) {
          final items = resolveDashboardItems(vm.$1);
          final overview = SchoolCountdownOverview(
            timeline: timeline,
            items: items,
            spans: vm.$6.toMap(),
            loading: vm.$4,
            onOpenCalendarAt: onOpenCalendarAt,
            onEditGradeDeadline: onEditGradeDeadline,
            additionalCards: {
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
                if (items.isNotEmpty) ...[overview, const SizedBox(height: 10)],
                controls,
              ]);
        },
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
    final statistic = state.statistic;
    final title = context.t('absences.title');
    if (state.loading && statistic == null && state.absences.isEmpty) {
      return DashboardLoadingCard(title: title);
    }
    final hasData = statistic != null ||
        state.lastFetched != null ||
        state.absences.isNotEmpty;
    // Keep the statistics page's server-provided counter and its meaning.
    // Missing values are not converted to an invented zero.
    return DashboardSummaryCard(
      icon: Icons.event_busy_outlined,
      title: title,
      primaryText: statistic?.counter == null
          ? context.t(hasData
              ? 'absences.status.noneValues'
              : 'schoolCountdown.missingData')
          : context.t('dashboard.customize.absenceCount',
              args: {'count': '${statistic?.counter}'}),
      secondaryText: widget.noInternet
          ? context.t('dashboard.customize.offline')
          : state.loadFailed
              ? context.t('dashboard.customize.unavailable')
              : statistic?.notJustified == null
                  ? context.t('absences.status.none')
                  : context.t('dashboard.customize.unjustifiedCount',
                      args: {'count': '${statistic?.notJustified}'}),
      onTap: state.loadFailed && !widget.noInternet ? widget.load : widget.open,
    );
  }
}
