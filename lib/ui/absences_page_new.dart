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

import 'package:charts_flutter/flutter.dart' as charts;
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/absences_page.dart' show showFutureAbsenceSheet;
import 'package:dr/ui/dashboard_app_header.dart' show HeaderDiscButton;
import 'package:dr/ui/dashboard_columns.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The space between two cards of the list.
const _gap = 8.0;

/// The absences page of the new design: the statistics beside (or, on
/// phones, above) the absences, the forms in glass sheets. Legacy keeps
/// `AbsencesPage`, with the same state and callbacks.
class AbsencesPageNew extends StatefulWidget {
  const AbsencesPageNew({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
    required this.onRetry,
  });

  final AbsencesState state;
  final bool noInternet;
  final void Function(Map<String, dynamic>) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;
  final VoidCallback onRetry;

  @override
  State<AbsencesPageNew> createState() => _AbsencesPageNewState();
}

class _AbsencesPageNewState extends State<AbsencesPageNew> {
  /// Whether the charts show on a phone. Beside the list they always do.
  bool _chartsExpanded = false;
  bool _showPie = false;

  AbsencesState get _state => widget.state;

  /// The last request finished with an error rather than still running.
  bool get _loadFailed => _state.loadFailed && !_state.loading;

  Future<void> _addFutureAbsence() async {
    final payload = await showFutureAbsenceSheet(context);
    if (payload != null) widget.onAddFutureAbsence(payload);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    return GlassPage(
      loading: _state.loading ||
          (_state.statistic == null && !widget.noInternet && !_loadFailed),
      header: GlassPageHeader(
        surfaceKey: const Key('absences-app-header'),
        titleKey: const Key('absences-header-title'),
        title: l10n.text('absences.title'),
        floatingMaxWidth: glassHeaderFloatingWidth(width, twoColumns: true),
      ),
      body: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final statistic = _state.statistic;
    if (statistic == null) {
      if (widget.noInternet) {
        return GlassStateCard(
          key: const Key('absences-offline'),
          icon: Icons.wifi_off_rounded,
          title: l10n.text('offline.title'),
          body: l10n.text('offline.body'),
          actionLabel: l10n.text('common.retry'),
          onAction: widget.onRetry,
        );
      }
      if (_loadFailed) {
        return GlassStateCard(
          key: const Key('absences-load-failed'),
          icon: Icons.error_outline_rounded,
          title: l10n.text('absences.loadFailed'),
          body: '',
          actionLabel: l10n.text('absences.retry'),
          onAction: widget.onRetry,
        );
      }
      // The bar below the header shows that they are on their way.
      return const SizedBox.shrink();
    }
    final empty = _state.absences.isEmpty && _state.futureAbsences.isEmpty;
    if (empty && (statistic.counter ?? 0) == 0) return _emptyState(context);

    final wide =
        DashboardColumns.forWindow(MediaQuery.sizeOf(context).width) != null;
    final items = _mainItems(context);
    return GlassColumnsBody.builder(
      listKey: const Key('absences-list'),
      side: Padding(
        padding: const EdgeInsets.only(bottom: _gap),
        child: _statistics(context, wide: wide),
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index](context),
    );
  }

  /// Nothing recorded yet. Recording the first future absence stays possible.
  Widget _emptyState(BuildContext context) {
    final l10n = context.l10n;
    final refreshFailed = _loadFailed && !widget.noInternet;
    final lastFetched = _state.lastFetched;
    final canAdd = _state.canEdit && !widget.noInternet;
    return GlassStateCard(
      key: const Key('absences-empty'),
      icon: Icons.event_available_outlined,
      title: l10n.text('absences.noneYet'),
      body: refreshFailed
          ? l10n.text('absences.refreshFailed')
          : widget.noInternet && lastFetched != null
              ? l10n.text(
                  'grades.offlineMode',
                  args: {'time': l10n.formatTimeAgo(lastFetched)},
                )
              : '',
      actionLabel: refreshFailed
          ? l10n.text('absences.retry')
          : canAdd
              ? l10n.text('absences.addFutureAbsence')
              : null,
      actionIcon: refreshFailed
          ? Icons.refresh_rounded
          : Icons.event_available_outlined,
      onAction: refreshFailed
          ? widget.onRetry
          : canAdd
              ? _addFutureAbsence
              : null,
    );
  }

  /// The column of the statistics: the button for a future absence, the
  /// figures and, beside the list or once opened, the charts.
  Widget _statistics(BuildContext context, {required bool wide}) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final vm = appSelectors.absenceStatistics(_state);
    final charts = wide || _chartsExpanded;
    final canShowPie = double.tryParse(
          vm.statistic.percentage?.replaceAll(',', '.') ?? '',
        ) !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_state.canEdit) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const Key('absences-add-future'),
              style: glassControlStyle(scheme),
              onPressed: widget.noInternet ? null : _addFutureAbsence,
              icon: const Icon(Icons.event_available_outlined, size: 20),
              label: Text(l10n.text('absences.addFutureAbsence')),
            ),
          ),
          const SizedBox(height: 4),
        ],
        GlassSectionHeading(
          titleKey: const Key('absences-statistics-title'),
          title: l10n.text('absences.statistics'),
          trailing: wide
              ? null
              : HeaderDiscButton(
                  key: const Key('absences-charts-toggle'),
                  tooltip: l10n.text('absences.statistics'),
                  icon: _chartsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  onPressed: () =>
                      setState(() => _chartsExpanded = !_chartsExpanded),
                ),
        ),
        _OverviewCard(
          statistic: vm.statistic,
          showPie: _showPie,
          onTogglePie:
              canShowPie ? () => setState(() => _showPie = !_showPie) : null,
        ),
        if (_showPie && canShowPie) ...[
          const SizedBox(height: _gap),
          _PieCard(percentage: vm.statistic.percentage!),
        ],
        if (charts) ...[
          const SizedBox(height: _gap),
          _StatusCard(statistic: vm.statistic),
          const SizedBox(height: _gap),
          _HistoryCard(vm: vm),
        ],
      ],
    );
  }

  /// The rows of the main list, built only when they come into view.
  List<WidgetBuilder> _mainItems(BuildContext context) {
    final l10n = context.l10n;
    final lastFetched = _state.lastFetched;
    final futures = _state.futureAbsences;
    final groups = _state.absences.length;
    Widget spaced(Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: _gap),
          child: child,
        );
    return [
      if (_loadFailed && !widget.noInternet)
        (_) => spaced(_RefreshFailedCard(onRetry: widget.onRetry)),
      if (widget.noInternet && lastFetched != null)
        (_) => spaced(
              GlassOfflineHint(
                key: const Key('absences-last-fetched'),
                message: l10n.text(
                  'grades.offlineMode',
                  args: {'time': l10n.formatTimeAgo(lastFetched)},
                ),
                onRetry: widget.onRetry,
              ),
            ),
      if (futures.isNotEmpty) ...[
        (_) => GlassSectionHeading(
              titleKey: const Key('absences-future-title'),
              title: l10n.text('absences.futureRecorded'),
              count: futures.length,
            ),
        for (final absence in futures)
          (_) => spaced(
                RepaintBoundary(
                  child: FutureAbsenceEntry(
                    key: ValueKey('absences-future-${absence.id}'),
                    absence: absence,
                    onRemove: _state.canEdit &&
                            absence.justified ==
                                AbsenceJustified.notYetJustified
                        ? () => widget.onRemoveFutureAbsence(absence)
                        : null,
                  ),
                ),
              ),
      ],
      if (groups > 0) ...[
        (_) => GlassSectionHeading(
              titleKey: const Key('absences-list-title'),
              title: l10n.text('absences.listTitle'),
              count: groups,
            ),
        for (var group = 0; group < groups; group++)
          (_) => spaced(
                RepaintBoundary(
                  child: AbsenceGroupContainer(
                    key: ValueKey('absences-group-$group'),
                    group: group,
                    builder: (context, vm) => AbsenceEntry(vm: vm),
                  ),
                ),
              ),
      ],
      if (futures.isEmpty && groups == 0)
        (context) => GlassCard(
              key: const Key('absences-none'),
              child: Text(
                l10n.text('absences.noneYet'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
    ];
  }
}

/// The colours and the icon of a status of an absence.
typedef _StatusLook = ({Color container, Color onContainer, IconData icon});

_StatusLook _statusLook(ColorScheme scheme, AbsenceJustified justified) =>
    switch (justified) {
      AbsenceJustified.justified => (
          container: scheme.successContainer,
          onContainer: scheme.onSuccessContainer,
          icon: Icons.verified_outlined,
        ),
      AbsenceJustified.forSchool => (
          container: scheme.infoContainer,
          onContainer: scheme.onInfoContainer,
          icon: Icons.school_outlined,
        ),
      AbsenceJustified.notJustified => (
          container: scheme.errorContainer,
          onContainer: scheme.onErrorContainer,
          icon: Icons.cancel_outlined,
        ),
      _ => (
          container: scheme.warningContainer,
          onContainer: scheme.onWarningContainer,
          icon: Icons.schedule_outlined,
        ),
    };

/// One absence (a group of lessons) of the list: when, how long, why, its
/// status in its colour and, while it can be, the button to justify it.
class AbsenceEntry extends StatelessWidget {
  const AbsenceEntry({super.key, required this.vm});

  final AbsencesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final onJustify = vm.onJustify;
    return _AbsenceCard(
      justified: vm.justified,
      title: vm.fromTo,
      subtitle: vm.duration,
      details: [
        if (vm.reason != null) vm.reason!,
        if (vm.note != null) vm.note!,
      ],
      status: vm.justifiedString,
      action: onJustify == null
          ? null
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const Key('absences-justify'),
                onPressed: () async {
                  final submission =
                      await showAbsenceJustificationSheet(context);
                  if (submission != null) {
                    onJustify(submission.reason, submission.signature);
                  }
                },
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: Text(context.t('absences.justification.action')),
              ),
            ),
    );
  }
}

/// An absence recorded in advance, with the button to delete it while it can
/// be deleted.
class FutureAbsenceEntry extends StatelessWidget {
  const FutureAbsenceEntry({super.key, required this.absence, this.onRemove});

  final FutureAbsence absence;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final onRemove = this.onRemove;
    return _AbsenceCard(
      justified: absence.justified,
      title: formatFutureAbsenceRange(absence, localeTag).trim(),
      details: [
        if (absence.note != null) absence.note!,
        if (absence.reason != null) absence.reason!,
        if (absence.reasonTimestamp != null && absence.reasonSignature != null)
          l10n.formatAbsenceSignature(
            absence.reasonTimestamp!,
            absence.reasonSignature!,
          ),
      ],
      status: l10n.absenceJustificationLabel(absence.justified),
      trailing: onRemove != null && absence.id != null
          ? IconButton(
              key: const Key('absences-future-remove'),
              tooltip: l10n.text('absences.future.delete'),
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            )
          : null,
    );
  }
}

/// The card of an absence: a disc in the colour of its status, the texts,
/// the status as a pill and an optional action below them.
class _AbsenceCard extends StatelessWidget {
  const _AbsenceCard({
    required this.justified,
    required this.title,
    this.subtitle = '',
    this.details = const [],
    required this.status,
    this.action,
    this.trailing,
  });

  final AbsenceJustified justified;
  final String title, subtitle, status;
  final List<String> details;
  final Widget? action, trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = _statusLook(scheme, justified);
    final action = this.action;
    final trailing = this.trailing;
    return GlassCard(
      padding: EdgeInsetsDirectional.fromSTEB(
        12,
        10,
        trailing == null ? 12 : 2,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: look.container,
                shape: const CircleBorder(),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Icon(look.icon, size: 20, color: look.onContainer),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One label for what the card says; its button stays apart.
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      for (final detail in details) ...[
                        const SizedBox(height: 4),
                        Text(detail, style: theme.textTheme.bodySmall),
                      ],
                      const SizedBox(height: 6),
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: look.container,
                          shape: const StadiumBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: Text(
                            status,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: look.onContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// That the last refresh failed and the data is older, with a retry.
class _RefreshFailedCard extends StatelessWidget {
  const _RefreshFailedCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      key: const Key('absences-refresh-failed'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                context.t('absences.refreshFailed'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(context.t('absences.retry')),
          ),
        ],
      ),
    );
  }
}

/// The figures: absences, not justified, delays, for the school, and the
/// absence rate with the button for its pie chart.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.statistic,
    required this.showPie,
    required this.onTogglePie,
  });

  final AbsenceStatistic statistic;
  final bool showPie;
  final VoidCallback? onTogglePie;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notJustified = statistic.notJustified;
    final figures = [
      if (statistic.counter != null)
        _Figure(
          key: const Key('absences-figure-counter'),
          label: l10n.text('absences.metric.absences'),
          value: '${statistic.counter}',
        ),
      if (notJustified != null)
        _Figure(
          key: const Key('absences-figure-not-justified'),
          label: l10n.text('absences.metric.notJustified'),
          value: '$notJustified',
          color: notJustified > 0 ? scheme.error : null,
        ),
      if (statistic.delayed != null)
        _Figure(
          key: const Key('absences-figure-delays'),
          label: l10n.text('absences.metric.delays'),
          value: '${statistic.delayed}',
        ),
      if (statistic.counterForSchool != null)
        _Figure(
          key: const Key('absences-figure-school'),
          label: l10n.text('absences.metric.forSchool'),
          value: '${statistic.counterForSchool}',
        ),
    ];
    final percentage = statistic.percentage;
    final onTogglePie = this.onTogglePie;
    return GlassCard(
      key: const Key('absences-overview'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (figures.isEmpty)
            Text(
              l10n.text('absences.status.none'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Two figures a line, one with very large text.
                final perLine =
                    MediaQuery.textScalerOf(context).scale(10) > 15 ? 1 : 2;
                final width =
                    (constraints.maxWidth - 8 * (perLine - 1)) / perLine;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final figure in figures)
                      SizedBox(width: width, child: figure),
                  ],
                );
              },
            ),
          if (percentage != null) ...[
            const SizedBox(height: 6),
            Divider(height: 8, color: scheme.outlineVariant),
            // The button moves below the rate when both do not fit a line.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.pie_chart_outline_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: MergeSemantics(
                          child: Text.rich(
                            key: const Key('absences-rate'),
                            TextSpan(
                              text:
                                  '${l10n.text('absences.metric.absenceRate')}  ',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                              children: [
                                TextSpan(
                                  text: '$percentage %',
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTogglePie != null)
                  TextButton(
                    key: const Key('absences-pie-toggle'),
                    onPressed: onTogglePie,
                    child: Text(
                      l10n.text(
                        showPie ? 'absences.chart.hide' : 'absences.chart.pie',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One figure of the overview, large, with what it is below it.
class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // With very large text, the number gets smaller instead of
          // breaking the card.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The title row of a chart card.
class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A dot and a text, for the legends of the charts.
class _LegendEntry extends StatelessWidget {
  const _LegendEntry({super.key, required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: color,
            shape: CircleBorder(
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// How the absences split up by status, as a bar and its legend.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.statistic});

  final AbsenceStatistic statistic;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statuses = <(String, int, Color)>[
      if (statistic.justified != null)
        (
          l10n.text('absences.status.justified'),
          statistic.justified!,
          scheme.success,
        ),
      if (statistic.notJustified != null)
        (
          l10n.text('absences.status.notJustified'),
          statistic.notJustified!,
          scheme.error,
        ),
      if (statistic.counterForSchool != null)
        (
          l10n.text('absences.status.school'),
          statistic.counterForSchool!,
          scheme.info,
        ),
    ];
    final total = statuses.fold<int>(0, (sum, status) => sum + status.$2);
    final note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return GlassCard(
      key: const Key('absences-status'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: Icons.donut_small_outlined,
            title: l10n.text('absences.status'),
          ),
          const SizedBox(height: 10),
          if (statuses.isEmpty)
            Text(l10n.text('absences.status.none'), style: note)
          else ...[
            if (total > 0)
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (_, value, color) in statuses)
                          if (value > 0)
                            Expanded(
                              flex: value,
                              child: ColoredBox(color: color),
                            ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Text(l10n.text('absences.status.noneValues'), style: note),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final (label, value, color) in statuses)
                  _LegendEntry(color: color, text: '$label: $value'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

charts.Color _chartsColor(Color color) => charts.Color(
      r: (color.r * 255).round().clamp(0, 255),
      g: (color.g * 255).round().clamp(0, 255),
      b: (color.b * 255).round().clamp(0, 255),
      a: (color.a * 255).round().clamp(0, 255),
    );

/// The missed lessons of each month, as bars in the colour of the absences.
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({required this.vm});

  final AbsenceStatsViewModel vm;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  /// The month tapped in the chart, with its lessons.
  String? _selected;

  static String _formatLessons(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final history = widget.vm.monthlyHistory;
    String month(UtcDateTime date) => DateFormat.MMM(localeTag).format(date);
    final labelColor = _chartsColor(scheme.onSurfaceVariant);
    final gridColor = _chartsColor(scheme.outlineVariant);
    final total = history.fold<double>(0, (sum, entry) => sum + entry.lessons);
    final selected = _selected;
    final note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return GlassCard(
      key: const Key('absences-history'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: Icons.bar_chart_rounded,
            title: l10n.text('absences.history'),
            subtitle: l10n.text('absences.history.subtitle'),
          ),
          const SizedBox(height: 8),
          if (!widget.vm.hasHistoricalData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.text('absences.history.none'),
                textAlign: TextAlign.center,
                style: note,
              ),
            )
          else ...[
            SizedBox(
              height: 180,
              child: RepaintBoundary(
                child: charts.BarChart(
                  [
                    charts.Series<AbsenceMonthlyHistoryValue, String>(
                      id: 'HistoricalAbsences',
                      data: history.toList(),
                      domainFn: (entry, _) => month(entry.month),
                      measureFn: (entry, _) => entry.lessons,
                      colorFn: (_, __) => _chartsColor(scheme.notice),
                    ),
                  ],
                  animate: false,
                  behaviors: [charts.SelectNearest<String>()],
                  selectionModels: [
                    charts.SelectionModelConfig<String>(
                      changedListener: (model) {
                        final datum = model.selectedDatum;
                        setState(() {
                          if (datum.isEmpty) {
                            _selected = null;
                          } else {
                            final value =
                                datum.first.datum as AbsenceMonthlyHistoryValue;
                            _selected = '${month(value.month)}: '
                                '${_formatLessons(value.lessons)}';
                          }
                        });
                      },
                    ),
                  ],
                  layoutConfig: charts.LayoutConfig(
                    topMarginSpec: charts.MarginSpec.fixedPixel(8),
                    rightMarginSpec: charts.MarginSpec.fixedPixel(8),
                    bottomMarginSpec: charts.MarginSpec.fixedPixel(
                      history.length > 6 ? 36 : 20,
                    ),
                    leftMarginSpec: charts.MarginSpec.fixedPixel(28),
                  ),
                  defaultRenderer: charts.BarRendererConfig<String>(
                    maxBarWidthPx: 28,
                    cornerStrategy: const charts.ConstCornerStrategy(6),
                  ),
                  primaryMeasureAxis: charts.NumericAxisSpec(
                    renderSpec: charts.GridlineRendererSpec(
                      labelStyle: charts.TextStyleSpec(
                        fontSize: 10,
                        color: labelColor,
                      ),
                      lineStyle: charts.LineStyleSpec(
                        color: gridColor,
                        thickness: 1,
                      ),
                    ),
                  ),
                  domainAxis: charts.OrdinalAxisSpec(
                    renderSpec: charts.SmallTickRendererSpec(
                      labelStyle: charts.TextStyleSpec(
                        fontSize: 10,
                        color: labelColor,
                      ),
                      lineStyle: charts.LineStyleSpec(
                        thickness: 0,
                        color: gridColor,
                      ),
                      labelRotation: history.length > 6 ? 45 : 0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (selected != null)
                  _LegendEntry(
                    key: const Key('absences-history-selection'),
                    color: scheme.notice,
                    text: selected,
                  ),
                Text(
                  l10n.text(
                    'absences.history.total',
                    args: {'value': _formatLessons(total)},
                  ),
                  style: note,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The absence rate against the time present, as a ring and its legend.
class _PieCard extends StatelessWidget {
  const _PieCard({required this.percentage});

  /// As the state holds it, 2.5 or 2,5.
  final String percentage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final absent = (double.tryParse(percentage.replaceAll(',', '.')) ?? 0)
        .clamp(0, 100)
        .toDouble();
    final slices = [
      (l10n.text('absences.pie.absent'), absent, scheme.notice),
      (
        l10n.text('absences.pie.present'),
        100.0 - absent,
        scheme.surfaceContainerHighest,
      ),
    ];
    return GlassCard(
      key: const Key('absences-pie'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            icon: Icons.pie_chart_outline_rounded,
            title: l10n.text('absences.pie.title'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: charts.PieChart<String>(
                  [
                    charts.Series<(String, double, Color), String>(
                      id: 'AbsencePercentage',
                      data: slices,
                      domainFn: (slice, _) => slice.$1,
                      measureFn: (slice, _) => slice.$2,
                      colorFn: (slice, _) => _chartsColor(slice.$3),
                    ),
                  ],
                  animate: false,
                  defaultRenderer:
                      charts.ArcRendererConfig<String>(arcWidth: 28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final (label, value, color) in slices)
                _LegendEntry(
                  color: color,
                  text: '$label: ${value.toStringAsFixed(1)} %',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
