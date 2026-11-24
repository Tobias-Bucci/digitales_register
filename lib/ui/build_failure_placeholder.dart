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

import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Installs [BuildFailurePlaceholder] in place of Flutter's error widget
/// outside debug builds.
///
/// A release build would otherwise show a blank grey box where a widget failed
/// to build (#168). Debug builds keep the red error screen with the details.
/// [FlutterError.onError] still reports the failure.
void installBuildFailurePlaceholder({bool debugMode = kDebugMode}) {
  if (debugMode) return;
  ErrorWidget.builder = (_) => const BuildFailurePlaceholder();
}

/// A short, calm hint where one part of a page could not be built.
///
/// It must work wherever a widget can fail: without a [Material] ancestor,
/// without localizations and with unbounded constraints.
class BuildFailurePlaceholder extends StatelessWidget {
  const BuildFailurePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final message =
        l10n?.text('error.display') ?? 'This content cannot be displayed.';
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          label: message,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 20, color: color),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    message,
                    style: TextStyle(color: color, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
