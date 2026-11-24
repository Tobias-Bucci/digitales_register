// Copyright (C) 2021 Michael Debertol
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
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/glass_surface.dart' show showGlassSheet;
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

part 'absences/absence_statistics.dart';
part 'absences/future_absence_dialog.dart';

class AbsencesPage extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final void Function(Map<String, dynamic>) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;
  final VoidCallback onRetry;

  const AbsencesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Text(context.t('absences.title')),
      ),
      body: LastFetchedOverlay(
        lastFetched: state.lastFetched,
        noInternet: noInternet,
        child: AbsencesBody(
          state: state,
          noInternet: noInternet,
          onAddFutureAbsence: onAddFutureAbsence,
          onRemoveFutureAbsence: onRemoveFutureAbsence,
          onRetry: onRetry,
        ),
      ),
    );
  }
}

class AbsencesBody extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final void Function(Map<String, dynamic>) onAddFutureAbsence;
  final void Function(FutureAbsence) onRemoveFutureAbsence;
  final VoidCallback? onRetry;

  const AbsencesBody({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onAddFutureAbsence,
    required this.onRemoveFutureAbsence,
    this.onRetry,
  });

  /// The last request finished with an error rather than still running.
  bool get _loadFailed => state.loadFailed && !state.loading;

  @override
  Widget build(BuildContext context) {
    final statsVm =
        state.statistic != null ? appSelectors.absenceStatistics(state) : null;
    // The creation action and statistics do not depend on existing entries:
    // without them nobody could record a first future absence.
    return state.statistic != null
        ? ListView(
            children: <Widget>[
              // Earlier data stays visible, but a failed refresh must not
              // pass for current data.
              if (_loadFailed && !noInternet)
                _AbsencesRefreshFailedBanner(onRetry: onRetry),
              if (state.canEdit)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: noInternet
                          ? null
                          : () async {
                              final payload =
                                  await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (_) =>
                                    const _FutureAbsenceDialogContainer(),
                              );
                              if (payload != null) {
                                onAddFutureAbsence(payload);
                              }
                            },
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(context.t('absences.addFutureAbsence')),
                    ),
                  ),
                ),
              AbsencesStatisticWidget(vm: statsVm!),
              const Divider(height: 0),
              if (state.absences.isEmpty && state.futureAbsences.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.t('absences.noneYet'),
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              if (state.futureAbsences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0).copyWith(top: 16),
                  child: Text(
                    context.t('absences.futureRecorded'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              for (final futureAbsence in state.futureAbsences)
                FutureAbsenceWidget(
                  absence: futureAbsence,
                  onRemove: state.canEdit &&
                          futureAbsence.justified ==
                              AbsenceJustified.notYetJustified
                      ? () => onRemoveFutureAbsence(futureAbsence)
                      : null,
                ),
              if (state.absences.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0).copyWith(top: 16),
                  child: Text(
                    context.t('absences.listTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ...List.generate(
                state.absences.length,
                (n) => AbsenceGroupContainer(group: n),
              ),
            ],
          )
        : noInternet
            ? const NoInternet()
            : _loadFailed
                ? _AbsencesLoadFailed(onRetry: onRetry)
                : const Center(
                    child: CircularProgressIndicator(),
                  );
  }
}

class _AbsencesLoadFailed extends StatelessWidget {
  const _AbsencesLoadFailed({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('absences.loadFailed'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.text('absences.retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AbsencesRefreshFailedBanner extends StatelessWidget {
  const _AbsencesRefreshFailedBanner({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.t('absences.refreshFailed'),
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.t('absences.retry')),
            ),
        ],
      ),
    );
  }
}
