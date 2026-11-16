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
import 'package:dr/school_notification_service.dart';
import 'package:flutter/material.dart';

/// Hidden page (long-press "Background and diagnostics" in the settings) that
/// shows whether background checks still run: the last check, its result and
/// the last checks of every account. It holds no school data.
class SchoolNotificationDebugPage extends StatefulWidget {
  const SchoolNotificationDebugPage({super.key, required this.service});
  final SchoolNotificationService service;

  @override
  State<SchoolNotificationDebugPage> createState() =>
      _SchoolNotificationDebugPageState();
}

class _SchoolNotificationDebugPageState
    extends State<SchoolNotificationDebugPage> {
  List<Map<String, dynamic>>? _log;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<Map<String, dynamic>> log;
    try {
      await widget.service.reload();
      log = await widget.service.checkLog();
    } catch (_) {
      log = const [];
    }
    if (mounted) setState(() => _log = log);
  }

  String _time(BuildContext context, Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}')?.toLocal();
    if (parsed == null) {
      return context.l10n.text('schoolNotifications.diagnostics.never');
    }
    final material = MaterialLocalizations.of(context);
    return '${material.formatCompactDate(parsed)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(parsed), alwaysUse24HourFormat: true)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = widget.service;
    final diagnostics = service.diagnostics;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: Text(label, style: style)),
            const SizedBox(width: 12),
            Expanded(
                flex: 3,
                child: SelectableText(value,
                    style: style?.copyWith(fontFamily: 'monospace'))),
          ]),
        );
    final log = _log;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('schoolNotifications.debug.title')),
        actions: [
          IconButton(
            tooltip: l10n.text('schoolNotifications.debug.refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _log = null);
              unawaited(_load());
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
              title: Text(l10n.text('schoolNotifications.debug.lastCheck'))),
          row(l10n.text('schoolNotifications.diagnostics.started'),
              _time(context, diagnostics['lastBackgroundStartedAt'])),
          row(l10n.text('schoolNotifications.diagnostics.success'),
              _time(context, diagnostics['lastBackgroundSuccessAt'])),
          row(l10n.text('schoolNotifications.diagnostics.event'),
              _time(context, diagnostics['lastDetectedAt'])),
          row(l10n.text('schoolNotifications.diagnostics.requested'),
              _time(context, diagnostics['lastNotificationRequestedAt'])),
          row(l10n.text('schoolNotifications.debug.result'),
              '${diagnostics['backgroundResult'] ?? '–'}'),
          row(l10n.text('schoolNotifications.debug.failures'),
              '${diagnostics['consecutiveFailures'] ?? 0}'),
          const Divider(),
          ListTile(
              title: Text(l10n.text('schoolNotifications.debug.platform'))),
          for (final entry in service.platformStatus.entries)
            row(entry.key, '${entry.value}'),
          row('details', '${service.preferences.details}'),
          row('categories',
              'grades=${service.preferences.grades} messages=${service.preferences.messages} homework=${service.preferences.homework} other=${service.preferences.other}'),
          const Divider(),
          ListTile(title: Text(l10n.text('schoolNotifications.debug.log'))),
          if (log == null)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()))
          else if (log.isEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l10n.text('schoolNotifications.debug.empty'),
                    style: style))
          else
            for (final entry in log)
              row(_time(context, entry['at']),
                  '${entry['account']} ${entry['result']} alerts=${entry['alerts']}'),
        ],
      ),
    );
  }
}
