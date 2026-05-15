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

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:dr/i18n/app_localizations.dart';

class DebugPageContainer extends StatelessWidget {
  const DebugPageContainer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const DebugPageWidget();
  }
}

class DebugPageWidget extends StatelessWidget {
  const DebugPageWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Menu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton(
            onPressed: () async {
              final l10n = AppLocalizations.of(context);
              
              // Simuliere das Popup
              bool? shouldUpdate = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l10n.text('update.title')),
                  content: Text(l10n.text('update.content')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l10n.text('update.later')),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l10n.text('update.now')),
                    ),
                  ],
                ),
              );

              // Führe danach den nativen Request zum Testen durch,
              // unabhängig davon, ob es auf UpdateNotAvailable steht
              if (shouldUpdate == true) {
                try {
                  final info = await InAppUpdate.checkForUpdate();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Status: ${info.updateAvailability}')),
                  );
                  if (info.updateAvailability == UpdateAvailability.updateAvailable) {
                    await InAppUpdate.performImmediateUpdate();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nativer PlayStore Update-Check ergab: Kein Update verfügbar.')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Nativer Error: $e')),
                  );
                }
              }
            },
            child: const Text("Update Popup erzwingen / triggern"),
          ),
        ],
      ),
    );
  }
}
