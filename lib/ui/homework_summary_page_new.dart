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

import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/homework_summary_page.dart';
import 'package:dr/ui/linkified_text.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The gap between the weeks of the list.
const _weekGap = 8.0;

/// The homework summary of the new design. `HomeworkSummaryPage` keeps
/// loading, refreshing and the cache, and passes what it has to this view.
class HomeworkSummaryPageNew extends StatelessWidget {
  const HomeworkSummaryPageNew({
    super.key,
    required this.translationPrefix,
    required this.document,
    required this.lastFetched,
    required this.loadError,
    required this.loading,
    required this.offline,
    required this.onRefresh,
  });

  /// Where the texts of the page are, `homeworkSummary` by default.
  final String translationPrefix;

  /// Null until the first summary arrived.
  final HomeworkSummaryDocument? document;
  final DateTime? lastFetched;
  final Object? loadError;
  final bool loading, offline;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GlassPage(
      loading: loading,
      header: GlassPageHeader(
        surfaceKey: const Key('homework-summary-app-header'),
        titleKey: const Key('homework-summary-header-title'),
        title: l10n.text('$translationPrefix.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        actions: [
          HeaderDiscButton(
            key: const Key('homework-summary-refresh'),
            tooltip: l10n.text('appNotifications.refresh'),
            icon: Icons.refresh_rounded,
            onPressed: () => unawaited(onRefresh()),
          ),
        ],
      ),
      body: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final top = MediaQuery.paddingOf(context).top;
    Widget refreshable(Widget child) => RefreshIndicator(
          edgeOffset: top,
          onRefresh: onRefresh,
          child: child,
        );
    final document = this.document;
    if (document == null) {
      if (offline) {
        return GlassStateCard(
          key: const Key('homework-summary-offline'),
          icon: Icons.wifi_off_rounded,
          title: l10n.text('offline.title'),
          body: l10n.text('offline.body'),
          actionLabel: l10n.text('common.retry'),
          onAction: () => unawaited(onRefresh()),
        );
      }
      final error = loadError;
      if (error != null) {
        return GlassStateCard(
          key: const Key('homework-summary-error'),
          icon: Icons.error_outline_rounded,
          title: l10n.text('$translationPrefix.loadFailed'),
          body: error.toString(),
          actionLabel: l10n.text('$translationPrefix.retry'),
          onAction: () => unawaited(onRefresh()),
        );
      }
      // The bar below the header shows that the summary is on its way.
      return const SizedBox.expand(key: Key('homework-summary-loading'));
    }
    if (!document.weeks.any((week) => week.entries.isNotEmpty)) {
      return refreshable(GlassStateCard(
        key: const Key('homework-summary-empty'),
        icon: Icons.assignment_turned_in_outlined,
        title: l10n.text('$translationPrefix.empty'),
        body: '',
      ));
    }
    final total =
        document.weeks.fold<int>(0, (sum, week) => sum + week.entries.length);
    final lastFetched = this.lastFetched;
    final rows = <Widget>[
      if (offline && lastFetched != null)
        GlassOfflineHint(
          key: const Key('homework-summary-last-fetched'),
          message: l10n.text(
            'grades.offlineMode',
            args: {
              'time': l10n.formatTimeAgo(
                UtcDateTime.makeUtc(lastFetched.toLocal()),
              ),
            },
          ),
          onRetry: () => unawaited(onRefresh()),
        ),
      _Summary(
        translationPrefix: translationPrefix,
        title: document.title,
        count: total,
        lastFetched: lastFetched,
      ),
    ];
    final weeks = document.weeks;
    final count = rows.length + weeks.length;
    return refreshable(GlassListBody.builder(
      listKey: const Key('homework-summary-list'),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index < rows.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: rows[index],
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : _weekGap),
          child: _Week(
            translationPrefix: translationPrefix,
            week: weeks[index - rows.length],
          ),
        );
      },
    ));
  }
}

/// The title of the summary, how many entries it has and when it was loaded,
/// quietly above the list.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.translationPrefix,
    required this.title,
    required this.count,
    required this.lastFetched,
  });

  final String translationPrefix, title;
  final int count;
  final DateTime? lastFetched;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lastFetched = this.lastFetched;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        [
          if (title.isNotEmpty) title,
          l10n.text(
            count == 1
                ? '$translationPrefix.entryCount.one'
                : '$translationPrefix.entryCount.other',
            args: {'count': count.toString()},
          ),
          if (lastFetched != null)
            l10n.text(
              '$translationPrefix.lastFetched',
              args: {
                'time': DateFormat.Hm(l10n.locale.toLanguageTag())
                    .format(lastFetched),
              },
            ),
        ].join(' · '),
        key: const Key('homework-summary-summary'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A week: its title as a heading, then its entries in one card.
class _Week extends StatelessWidget {
  const _Week({required this.translationPrefix, required this.week});

  final String translationPrefix;
  final HomeworkSummaryWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassSectionHeading(title: week.title, count: week.entries.length),
        GlassCard(
          padding: EdgeInsets.zero,
          child: week.entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.text('$translationPrefix.emptyWeek'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, entry) in week.entries.indexed) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          indent: 12,
                          endIndent: 12,
                          color: scheme.outlineVariant,
                        ),
                      _EntryRow(entry: entry),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// An entry: its subject, its day and kind, what is to be done, and the
/// further columns of the table.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final HomeworkSummaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final title = entry.primaryText;
    final type = entry.typeText;
    return Padding(
      key: const Key('homework-summary-entry'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.subjectText.isNotEmpty)
                      Text(
                        entry.subjectText,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (entry.dateText.isNotEmpty)
                      Text(entry.dateText, style: muted),
                  ],
                ),
              ),
              if (type.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  // A long kind does not push the subject out.
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const StadiumBorder(),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text(
                        type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            LinkifiedText(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ],
          if (entry.extraCells.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                for (final cell in entry.extraCells)
                  Text('${cell.header}: ${cell.value}', style: muted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
