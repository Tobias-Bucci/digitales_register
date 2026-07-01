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
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class HomeworkSummaryPage extends StatefulWidget {
  const HomeworkSummaryPage({
    super.key,
    this.loader,
    this.cachedLoader = loadCachedHomeworkSummaryHtmlPayload,
    this.refreshLoader = refreshHomeworkSummaryHtmlPayload,
    this.translationPrefix = 'homeworkSummary',
    this.icon = Icons.assignment_outlined,
  });

  final Future<String?> Function()? loader;
  final Future<PagePayloadSnapshot<String>?> Function() cachedLoader;
  final Future<PagePayloadSnapshot<String>?> Function() refreshLoader;
  final String translationPrefix;
  final IconData icon;

  @override
  State<HomeworkSummaryPage> createState() => _HomeworkSummaryPageState();
}

class _HomeworkSummaryPageState extends State<HomeworkSummaryPage> {
  HomeworkSummaryDocument? _document;
  DateTime? _lastFetched;
  String? _fingerprint;
  Object? _loadError;
  bool _loading = true;
  Future<void>? _pendingRefresh;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant HomeworkSummaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader ||
        oldWidget.cachedLoader != widget.cachedLoader ||
        oldWidget.refreshLoader != widget.refreshLoader ||
        oldWidget.translationPrefix != widget.translationPrefix) {
      _pendingRefresh = null;
      _document = null;
      _lastFetched = null;
      _fingerprint = null;
      _loadError = null;
      _loading = true;
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final directLoader = widget.loader;
    if (directLoader != null) {
      await _loadDirect(directLoader);
      return;
    }

    final cached = await widget.cachedLoader();
    if (!mounted) {
      return;
    }
    if (cached != null) {
      _applySnapshot(cached);
      setState(() {
        _loading = false;
        _loadError = null;
      });
      unawaited(_refresh(silent: true));
    } else {
      await _refresh();
    }
  }

  Future<void> _loadDirect(Future<String?> Function() loader) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await loader();
      if (!mounted) {
        return;
      }
      if (response == null) {
        throw const HomeworkSummaryLoadException();
      }
      setState(() {
        _document = HomeworkSummaryDocument.parse(response);
        _lastFetched = DateTime.now();
        _fingerprint = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    final directLoader = widget.loader;
    if (directLoader != null) {
      await _loadDirect(directLoader);
      return;
    }

    final pending = _pendingRefresh;
    if (pending != null) {
      await pending;
      return;
    }
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    final future = _refreshFromRemote(silent: silent);
    _pendingRefresh = future;
    try {
      await future;
    } finally {
      if (identical(_pendingRefresh, future)) {
        _pendingRefresh = null;
      }
    }
  }

  Future<void> _refreshFromRemote({required bool silent}) async {
    try {
      final snapshot = await widget.refreshLoader();
      if (!mounted) {
        return;
      }
      if (snapshot == null) {
        throw const HomeworkSummaryLoadException();
      }
      final changed = _fingerprint != snapshot.fingerprint || _document == null;
      setState(() {
        if (changed) {
          _applySnapshot(snapshot);
        } else {
          _lastFetched = snapshot.fetchedAt;
          _fingerprint = snapshot.fingerprint;
        }
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_document == null || !silent) {
        setState(() {
          _loadError = error;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _applySnapshot(PagePayloadSnapshot<String> snapshot) {
    _document = HomeworkSummaryDocument.parse(snapshot.payload);
    _lastFetched = snapshot.fetchedAt;
    _fingerprint = snapshot.fingerprint;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon),
            const SizedBox(width: 8),
            Text(l10n.text('${widget.translationPrefix}.title')),
          ],
        ),
      ),
      body: Stack(
        children: [
          _buildBody(),
          AnimatedLinearProgressIndicator(show: _loading),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final document = _document;
    if (document != null) {
      return _HomeworkSummaryContent(
        translationPrefix: widget.translationPrefix,
        document: document,
        lastFetched: _lastFetched,
        onRefresh: _refresh,
      );
    }
    if (isOffline()) {
      return const NoInternet();
    }
    final error = _loadError;
    if (error != null) {
      return _HomeworkSummaryError(
        translationPrefix: widget.translationPrefix,
        error: error.toString(),
        onRetry: _refresh,
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

class HomeworkSummaryLoadException implements Exception {
  const HomeworkSummaryLoadException();

  @override
  String toString() => 'Homework summary request returned no data.';
}

class _HomeworkSummaryContent extends StatelessWidget {
  const _HomeworkSummaryContent({
    required this.translationPrefix,
    required this.document,
    required this.lastFetched,
    required this.onRefresh,
  });

  final String translationPrefix;
  final HomeworkSummaryDocument document;
  final DateTime? lastFetched;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasEntries = document.weeks.any((week) => week.entries.isNotEmpty);
    final totalEntries = document.weeks.fold<int>(
      0,
      (sum, week) => sum + week.entries.length,
    );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              _HomeworkSummaryHeader(
                translationPrefix: translationPrefix,
                title: document.title,
                totalEntries: totalEntries,
                lastFetched: lastFetched,
              ),
              if (!hasEntries)
                _EmptyHomeworkSummary(
                  message: l10n.text('$translationPrefix.empty'),
                ),
              for (final week in document.weeks)
                _HomeworkWeekCard(
                  translationPrefix: translationPrefix,
                  week: week,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeworkSummaryHeader extends StatelessWidget {
  const _HomeworkSummaryHeader({
    required this.translationPrefix,
    required this.title,
    required this.totalEntries,
    required this.lastFetched,
  });

  final String translationPrefix;
  final String title;
  final int totalEntries;
  final DateTime? lastFetched;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty
                          ? l10n.text('$translationPrefix.title')
                          : title,
                      style: theme.textTheme.headlineSmall,
                    ),
                    if (lastFetched != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        l10n.text(
                          '$translationPrefix.lastFetched',
                          args: {
                            'time': DateFormat.Hm(
                              l10n.locale.toLanguageTag(),
                            ).format(lastFetched!),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    l10n.text(
                      totalEntries == 1
                          ? '$translationPrefix.entryCount.one'
                          : '$translationPrefix.entryCount.other',
                      args: {'count': totalEntries.toString()},
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeworkWeekCard extends StatelessWidget {
  const _HomeworkWeekCard({
    required this.translationPrefix,
    required this.week,
  });

  final String translationPrefix;
  final HomeworkSummaryWeek week;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    week.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  l10n.text(
                    week.entries.length == 1
                        ? '$translationPrefix.entryCount.one'
                        : '$translationPrefix.entryCount.other',
                    args: {'count': week.entries.length.toString()},
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (week.entries.isEmpty)
              _EmptyWeekRow(text: l10n.text('$translationPrefix.emptyWeek'))
            else
              for (var index = 0; index < week.entries.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                _HomeworkEntryTile(entry: week.entries[index]),
              ],
          ],
        ),
      ),
    );
  }
}

class _EmptyWeekRow extends StatelessWidget {
  const _EmptyWeekRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeworkEntryTile extends StatelessWidget {
  const _HomeworkEntryTile({required this.entry});

  final HomeworkSummaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = entry.primaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final meta = _EntryMeta(entry: entry);
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                meta,
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(title, style: theme.textTheme.bodyLarge),
                ],
                if (entry.extraCells.isNotEmpty)
                  _ExtraCellsRow(cells: entry.extraCells),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 108, child: meta),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      SelectableText(title, style: theme.textTheme.bodyLarge),
                    if (entry.extraCells.isNotEmpty)
                      _ExtraCellsRow(cells: entry.extraCells),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EntryMeta extends StatelessWidget {
  const _EntryMeta({required this.entry});

  final HomeworkSummaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.dateText.isNotEmpty)
          Text(
            entry.dateText,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.primary,
            ),
          ),
        if (entry.subjectText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            entry.subjectText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (entry.typeText.isNotEmpty) ...[
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                entry.typeText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ExtraCellsRow extends StatelessWidget {
  const _ExtraCellsRow({required this.cells});

  final List<HomeworkSummaryCell> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          for (final cell in cells)
            Text(
              '${cell.header}: ${cell.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeworkSummaryError extends StatelessWidget {
  const _HomeworkSummaryError({
    required this.translationPrefix,
    required this.error,
    required this.onRetry,
  });

  final String translationPrefix;
  final String error;
  final Future<void> Function() onRetry;

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
              l10n.text('$translationPrefix.loadFailed'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.text('$translationPrefix.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeworkSummary extends StatelessWidget {
  const _EmptyHomeworkSummary({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}

class HomeworkSummaryDocument {
  const HomeworkSummaryDocument({
    required this.title,
    required this.weeks,
  });

  final String title;
  final List<HomeworkSummaryWeek> weeks;

  factory HomeworkSummaryDocument.parse(String source) {
    final document = html_parser.parse(source);
    final summary = document.querySelector('#classSummary .summary') ??
        document.querySelector('.summary') ??
        document.body;
    if (summary == null) {
      return const HomeworkSummaryDocument(title: '', weeks: []);
    }

    final title = _cleanText(summary.querySelector('h1')?.text);
    final weeks = <HomeworkSummaryWeek>[];
    String? currentWeekTitle;
    List<String> currentHeaders = const <String>[];

    for (final child in summary.children) {
      if (child.localName == 'h3') {
        currentWeekTitle = _cleanText(child.text);
      } else if (child.localName == 'table') {
        final table = _parseTable(child, currentHeaders);
        currentHeaders = table.headers;
        weeks.add(
          HomeworkSummaryWeek(
            title: currentWeekTitle ?? '',
            headers: table.headers,
            entries: table.entries,
          ),
        );
        currentWeekTitle = null;
      }
    }

    return HomeworkSummaryDocument(title: title, weeks: weeks);
  }
}

class HomeworkSummaryWeek {
  const HomeworkSummaryWeek({
    required this.title,
    required this.headers,
    required this.entries,
  });

  final String title;
  final List<String> headers;
  final List<HomeworkSummaryEntry> entries;
}

class HomeworkSummaryEntry {
  const HomeworkSummaryEntry({
    required this.headers,
    required this.cells,
  });

  final List<String> headers;
  final List<String> cells;

  String get dateText => _cellAt(0);

  String get subjectText => _cellAt(1);

  String get typeText => _cellAt(2);

  String get secondaryText {
    return [subjectText, typeText]
        .where((value) => value.isNotEmpty)
        .join(' - ');
  }

  String get primaryText =>
      _cellAt(3).isNotEmpty ? _cellAt(3) : cells.lastOrNull ?? '';

  List<HomeworkSummaryCell> get extraCells {
    final result = <HomeworkSummaryCell>[];
    for (var index = 4; index < cells.length; index++) {
      final value = _cellAt(index);
      if (value.isEmpty) {
        continue;
      }
      result.add(
        HomeworkSummaryCell(
          header: index < headers.length && headers[index].isNotEmpty
              ? headers[index]
              : '#${index + 1}',
          value: value,
        ),
      );
    }
    return result;
  }

  String _cellAt(int index) => index < cells.length ? cells[index] : '';
}

class HomeworkSummaryCell {
  const HomeworkSummaryCell({
    required this.header,
    required this.value,
  });

  final String header;
  final String value;
}

class _ParsedHomeworkTable {
  const _ParsedHomeworkTable({
    required this.headers,
    required this.entries,
  });

  final List<String> headers;
  final List<HomeworkSummaryEntry> entries;
}

_ParsedHomeworkTable _parseTable(
    dom.Element table, List<String> fallbackHeaders) {
  final headers = table
      .querySelectorAll('thead th')
      .map((element) => _cleanText(element.text))
      .where((text) => text.isNotEmpty)
      .toList();
  final effectiveHeaders = headers.isEmpty ? fallbackHeaders : headers;
  final rows = table
      .querySelectorAll('tr')
      .where((row) => row.querySelector('td') != null)
      .toList();
  final entries = rows.map((row) {
    final cells = row
        .querySelectorAll('td')
        .map((element) => _cleanText(element.text))
        .toList();
    return HomeworkSummaryEntry(headers: effectiveHeaders, cells: cells);
  }).toList();
  return _ParsedHomeworkTable(headers: effectiveHeaders, entries: entries);
}

String _cleanText(String? input) {
  return (input ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

extension _ListLastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
