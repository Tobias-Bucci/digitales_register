// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:dr/app_state.dart';
import 'package:dr/export/export_csv.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_service.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class ExportPage extends StatefulWidget {
  const ExportPage(
      {super.key,
      required this.state,
      this.initialCategory,
      this.service = const ExportService()});
  final AppState state;
  final ExportCategory? initialCategory;
  final ExportService service;
  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  final _selected = <ExportCategory>{};
  final _entryIds = <ExportCategory, Set<String>>{};
  ExportFormat _format = ExportFormat.pdf;
  Semester _semester = Semester.all;
  int? _year;
  String? _subject;
  DateTimeRange? _range;
  bool _busy = false;
  String? _status;
  bool _error = false;
  late AppState _snapshot;
  late Map<ExportCategory, List<ExportRecord>> _records;

  @override
  void initState() {
    super.initState();
    _cacheRecords();
    if (widget.initialCategory != null) _selected.add(widget.initialCategory!);
    if (widget.initialCategory == ExportCategory.grades) {
      _semester = widget.state.gradesState.semester;
    }
  }

  @override
  void didUpdateWidget(covariant ExportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.state;
    final current = widget.state;
    if (previous.gradesState != current.gradesState ||
        previous.messagesState != current.messagesState ||
        previous.calendarState != current.calendarState ||
        previous.absencesState != current.absencesState ||
        previous.certificateState != current.certificateState) {
      // Basic grades have no server IDs. Never reuse index-based selections
      // after a refresh inserted or removed a grade.
      _entryIds.clear();
      _year = null;
      _subject = null;
      _range = null;
      _cacheRecords();
    } else {
      _snapshot = current;
    }
  }

  void _cacheRecords() {
    _snapshot = widget.state;
    final source = ExportDataSource(_snapshot);
    _records = {for (final c in ExportCategory.values) c: source.records(c)};
  }

  bool _hasSubject(ExportCategory c) => [
        ExportCategory.grades,
        ExportCategory.timetable,
        ExportCategory.exams,
        ExportCategory.tasks,
        ExportCategory.lessons
      ].contains(c);

  ExportFilter _filter(ExportCategory c, {bool includeIds = true}) =>
      c == ExportCategory.certificates
          ? const ExportFilter()
          : ExportFilter(
              schoolYear: _year,
              semester: _semester,
              subject: _hasSubject(c) ? _subject : null,
              from: _range?.start,
              until: _range?.end,
              ids: includeIds ? _entryIds[c] : null);

  List<ExportRecord> _matching(ExportCategory c, {bool includeIds = true}) {
    final f = _filter(c, includeIds: includeIds);
    return _records[c]!
        .where((r) => f.accepts(r.date, subjectName: r.subject, id: r.id))
        .where((r) =>
            c != ExportCategory.grades ||
            _semester == Semester.all ||
            r.fields['semester'] == '${_semester.n}')
        .toList();
  }

  void _change(VoidCallback change) => setState(() {
        change();
        _entryIds.clear();
        _status = null;
      });

  Future<void> _chooseDates() async {
    final dates = _selected
        .expand((c) => _records[c]!)
        .map((r) => r.date)
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (dates.isEmpty) return;
    final chosen = await showDateRangePicker(
        context: context,
        firstDate:
            DateTime(dates.first.year, dates.first.month, dates.first.day),
        lastDate: DateTime(dates.last.year, dates.last.month, dates.last.day),
        initialDateRange: _range);
    if (chosen != null && mounted) _change(() => _range = chosen);
  }

  Future<void> _chooseEntries(ExportCategory category) async {
    final rows = _matching(category, includeIds: false);
    final selected = {
      ...(_entryIds[category] ?? rows.map((r) => r.id).toSet())
    };
    final l10n = context.l10n;
    final result = await showDialog<Set<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(l10n.text('export.category.${category.name}')),
                  content: SizedBox(
                      width: 600,
                      height: 420,
                      child: Column(children: [
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          TextButton(
                              onPressed: () => update(
                                  () => selected.addAll(rows.map((r) => r.id))),
                              child: Text(l10n.text('export.all'))),
                          TextButton(
                              onPressed: () => update(selected.clear),
                              child: Text(l10n.text('export.none')))
                        ]),
                        Expanded(
                            child: ListView.builder(
                                itemCount: rows.length,
                                itemBuilder: (context, index) {
                                  final r = rows[index];
                                  return CheckboxListTile(
                                      value: selected.contains(r.id),
                                      title: Text(
                                          r.title.isEmpty
                                              ? l10n.text(
                                                  'export.category.${category.name}')
                                              : r.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                          [
                                            if (r.date != null)
                                              DateFormat.yMMMd(
                                                      l10n.locale.languageCode)
                                                  .format(r.date!),
                                            if (r.subject != null &&
                                                r.subject != r.title)
                                              r.subject!,
                                            if (category ==
                                                ExportCategory.grades)
                                              '${localizedField('grade', r.fields['grade'] ?? '', l10n)} · ${r.fields['type']} · ${r.fields['weight']} %',
                                            if (r.body.isNotEmpty) r.body,
                                          ].join('\n'),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis),
                                      onChanged: (value) => update(() => value!
                                          ? selected.add(r.id)
                                          : selected.remove(r.id)));
                                })),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.text('export.cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, selected),
                        child: Text(l10n.text('export.apply')))
                  ],
                )));
    if (result != null && mounted) {
      setState(() {
        _entryIds[category] = result;
        _status = null;
      });
    }
  }

  Future<void> _export() async {
    final l10n = context.l10n;
    final source = ExportDataSource(_snapshot);
    final owner = (
      _snapshot.url,
      _snapshot.loginState.username,
      _snapshot.loginState.loggedIn
    );
    // Freeze one account's data and options before asynchronous generation.
    final sections = [
      for (final c in ExportCategory.values.where(_selected.contains))
        source.section(c, _filter(c))
    ];
    final locale = l10n.locale.languageCode;
    final scope = [
      if (_year == null) l10n.text('export.allYears'),
      if (_year != null)
        '${l10n.text('export.schoolYear')}: $_year-${_year! + 1}',
      if (_range != null)
        '${DateFormat.yMMMd(locale).format(_range!.start)} - ${DateFormat.yMMMd(locale).format(_range!.end)}',
      if (_subject != null) '${l10n.text('export.field.subject')}: $_subject',
    ].join('\n');
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final file = await widget.service.create(
          sections: sections,
          format: _format,
          l10n: l10n,
          scope: scope,
          schoolYear: _year);
      if (!mounted ||
          owner !=
              (
                widget.state.url,
                widget.state.loginState.username,
                widget.state.loginState.loggedIn
              )) {
        return;
      }
      final saved = await widget.service.save(file, l10n.text('export.save'));
      if (!mounted) return;
      setState(() {
        _error = false;
        _status = l10n.text(saved ? 'export.success' : 'export.cancelled');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _status = l10n.text(error is ExportEmptyException
            ? 'export.empty'
            : error is ExportTooLargeException
                ? 'export.tooLarge'
                : 'export.failed');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String t(String key) => l10n.text('export.$key');
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dated = _selected.any((c) => c != ExportCategory.certificates);
    final years = {
      for (final c in _selected)
        for (final r in _records[c]!)
          if (r.date != null) exportSchoolYear(r.date!)
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final subjects = {
      for (final c in _selected.where(_hasSubject))
        for (final r in _records[c]!)
          if (r.subject != null) r.subject!
    }.toList()
      ..sort();
    final count = _selected.fold<int>(0, (sum, c) => sum + _matching(c).length);
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: ResponsiveAppBar(title: Text(t('title'))),
          body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      children: [
                        Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(24)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.file_download_outlined,
                                      size: 32,
                                      color: colors.onPrimaryContainer),
                                  const SizedBox(height: 12),
                                  Text(t('headline'),
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                              color:
                                                  colors.onPrimaryContainer)),
                                  const SizedBox(height: 8),
                                  Text(t('intro'),
                                      style: TextStyle(
                                          color: colors.onPrimaryContainer)),
                                ])),
                        const SizedBox(height: 16),
                        _section(context, t('categories'), [
                          for (final c in ExportCategory.values)
                            CheckboxListTile(
                                secondary: Icon(_icon(c)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                title: Text(t('category.${c.name}')),
                                subtitle: Text(
                                    '${t('description.${c.name}')} · ${_records[c]!.length}'),
                                value: _selected.contains(c),
                                onChanged: _busy
                                    ? null
                                    : (value) => _change(() {
                                          value!
                                              ? _selected.add(c)
                                              : _selected.remove(c);
                                          _year = null;
                                          _subject = null;
                                          _range = null;
                                        })),
                        ]),
                        const SizedBox(height: 16),
                        if (_selected.isNotEmpty) ...[
                          _section(context, t('options'), [
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SegmentedButton<ExportFormat>(
                                          segments: [
                                            ButtonSegment(
                                                value: ExportFormat.pdf,
                                                icon: const Icon(Icons
                                                    .picture_as_pdf_outlined),
                                                label: Text(t('pdf'))),
                                            ButtonSegment(
                                                value: ExportFormat.csv,
                                                icon: const Icon(
                                                    Icons.table_chart_outlined),
                                                label: Text(t('csv'))),
                                          ],
                                          selected: {
                                            _format
                                          },
                                          onSelectionChanged: _busy
                                              ? null
                                              : (value) => _change(() =>
                                                  _format = value.single)),
                                      const SizedBox(height: 12),
                                      Text(t(_format == ExportFormat.csv &&
                                              _selected.length > 1
                                          ? 'zipHint'
                                          : 'formatHint')),
                                      if (dated) ...[
                                        const SizedBox(height: 20),
                                        DropdownButtonFormField<int>(
                                            isExpanded: true,
                                            key: ValueKey(
                                                'year:$_year:${years.join(',')}'),
                                            initialValue: _year,
                                            decoration: InputDecoration(
                                                labelText: t('schoolYear'),
                                                border:
                                                    const OutlineInputBorder()),
                                            items: [
                                              DropdownMenuItem<int>(
                                                  child: Text(t('allYears'))),
                                              for (final y in years)
                                                DropdownMenuItem(
                                                    value: y,
                                                    child: Text('$y-${y + 1}'))
                                            ],
                                            onChanged: _busy
                                                ? null
                                                : (value) => _change(
                                                    () => _year = value)),
                                        const SizedBox(height: 12),
                                        ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                                Icons.date_range_outlined),
                                            title: Text(t('period')),
                                            subtitle: Text(_range == null
                                                ? t('allDates')
                                                : '${DateFormat.yMMMd(l10n.locale.languageCode).format(_range!.start)} - ${DateFormat.yMMMd(l10n.locale.languageCode).format(_range!.end)}'),
                                            onTap: _busy ? null : _chooseDates,
                                            trailing: _range == null
                                                ? const Icon(
                                                    Icons.chevron_right)
                                                : IconButton(
                                                    tooltip: t('reset'),
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _change(() =>
                                                            _range = null),
                                                    icon: const Icon(
                                                        Icons.close))),
                                      ],
                                      if (_selected
                                          .contains(ExportCategory.grades)) ...[
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<Semester>(
                                            isExpanded: true,
                                            initialValue: _semester,
                                            decoration: InputDecoration(
                                                labelText: t('semester'),
                                                border:
                                                    const OutlineInputBorder()),
                                            items: [
                                              for (final s in Semester.values)
                                                DropdownMenuItem(
                                                    value: s,
                                                    child: Text(
                                                        l10n.semesterLabel(s)))
                                            ],
                                            onChanged: _busy
                                                ? null
                                                : (value) => _change(
                                                    () => _semester = value!)),
                                      ],
                                      if (subjects.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                            key: ValueKey(
                                                'subject:$_subject:${subjects.join(',')}'),
                                            initialValue: _subject,
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                                labelText: t('field.subject'),
                                                border:
                                                    const OutlineInputBorder()),
                                            items: [
                                              DropdownMenuItem<String>(
                                                  child:
                                                      Text(t('allSubjects'))),
                                              for (final s in subjects)
                                                DropdownMenuItem(
                                                    value: s,
                                                    child: Text(s,
                                                        overflow: TextOverflow
                                                            .ellipsis))
                                            ],
                                            onChanged: _busy
                                                ? null
                                                : (value) => _change(
                                                    () => _subject = value)),
                                      ],
                                    ])),
                            if (_selected.contains(ExportCategory.certificates))
                              Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(t('certificateNotice'))),
                          ]),
                          const SizedBox(height: 16),
                          _section(context, t('selection'), [
                            for (final c in _selected)
                              ListTile(
                                  leading: Icon(_icon(c)),
                                  title: Text(t('category.${c.name}')),
                                  subtitle: Text(
                                      '${_matching(c).length} ${t('entries')}'),
                                  trailing: c == ExportCategory.certificates
                                      ? null
                                      : const Icon(Icons.tune),
                                  onTap:
                                      _busy || c == ExportCategory.certificates
                                          ? null
                                          : () => _chooseEntries(c)),
                          ]),
                          const SizedBox(height: 16),
                        ],
                        Text(
                            t(widget.state.noInternet
                                ? 'offlineNotice'
                                : 'scopeNotice'),
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 8),
                        Text(t('privacyNotice'),
                            style: theme.textTheme.bodySmall),
                        if (_selected.isNotEmpty && count == 0)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(t('empty'))),
                        if (_status != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(_status!,
                                      style: TextStyle(
                                          color: _error
                                              ? colors.error
                                              : colors.primary)))),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                            onPressed: _busy || count == 0 ? null : _export,
                            style: FilledButton.styleFrom(
                                padding: const EdgeInsets.all(18)),
                            icon: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.save_alt),
                            label: Text(_busy
                                ? t('creating')
                                : '${t('save')} ($count)')),
                      ]))),
        ));
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge)),
            ...children,
            const SizedBox(height: 8),
          ]));

  IconData _icon(ExportCategory c) => switch (c) {
        ExportCategory.certificates => Icons.workspace_premium_outlined,
        ExportCategory.grades => Icons.insights_outlined,
        ExportCategory.messages => Icons.mail_outline,
        ExportCategory.timetable => Icons.calendar_view_week_outlined,
        ExportCategory.exams => Icons.event_note_outlined,
        ExportCategory.tasks => Icons.assignment_outlined,
        ExportCategory.absences => Icons.event_busy_outlined,
        ExportCategory.lessons => Icons.menu_book_outlined,
      };
}
