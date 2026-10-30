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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/study_data_migration.dart';
import 'package:flutter/material.dart';

/// A line in the settings for as long as older learning notes that belong to
/// no account are kept on the device. It shows numbers only and opens the
/// question what to do with them: assign, keep for later, or discard.
class LegacyStudyDataTile extends StatefulWidget {
  const LegacyStudyDataTile({super.key, required this.actions});

  final AppActions actions;

  @override
  State<LegacyStudyDataTile> createState() => _LegacyStudyDataTileState();
}

class _LegacyStudyDataTileState extends State<LegacyStudyDataTile> {
  late Future<LegacyStudySummary?> _summary = _load();

  Future<LegacyStudySummary?> _load() async {
    try {
      return await studyDataMigration.summary();
    } catch (_) {
      // Unreadable now; the line is shown when it can be read.
      return null;
    }
  }

  void _reload() {
    setState(() {
      _summary = _load();
    });
  }

  @override
  void initState() {
    super.initState();
    legacyStudyDataRevision.addListener(_reload);
  }

  @override
  void dispose() {
    legacyStudyDataRevision.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<LegacyStudySummary?>(
      future: _summary,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(l10n.text('studyData.legacy.setting.title')),
          subtitle: Text(l10n.text('studyData.legacy.setting.subtitle', args: {
            'exams': summary.exams.toString(),
            'notes': summary.notes.toString(),
            'files': summary.files.toString(),
          })),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLegacyStudyDataDialog(widget.actions, summary),
        );
      },
    );
  }
}
