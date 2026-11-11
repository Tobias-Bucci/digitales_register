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
import 'package:dr/ui/glass_page.dart';
import 'package:flutter/material.dart';

/// The rarely used pages of the new design, grouped on one page. It is a
/// destination of the navigation, so its header has no back button.
class ExtrasPage extends StatelessWidget {
  const ExtrasPage({
    super.key,
    required this.showClassRegister,
    required this.showHomeworkSummary,
    required this.showCertificate,
    required this.showAbsences,
    required this.showCourseMaterials,
  });

  final VoidCallback showClassRegister,
      showHomeworkSummary,
      showCertificate,
      showAbsences,
      showCourseMaterials;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = [
      _ExtrasEntry(
        key: const Key('extras-class-register'),
        icon: Icons.fact_check_outlined,
        title: l10n.text('sidebar.classRegister'),
        subtitle: l10n.text('extras.classRegister.subtitle'),
        onTap: showClassRegister,
      ),
      _ExtrasEntry(
        key: const Key('extras-homework-summary'),
        icon: Icons.assignment_outlined,
        title: l10n.text('sidebar.homework'),
        subtitle: l10n.text('extras.homework.subtitle'),
        onTap: showHomeworkSummary,
      ),
      _ExtrasEntry(
        key: const Key('extras-certificate'),
        icon: Icons.description_outlined,
        title: l10n.text('sidebar.certificate'),
        subtitle: l10n.text('extras.certificate.subtitle'),
        onTap: showCertificate,
      ),
      _ExtrasEntry(
        key: const Key('extras-absences'),
        icon: Icons.event_busy_outlined,
        title: l10n.text('sidebar.absences'),
        subtitle: l10n.text('extras.absences.subtitle'),
        onTap: showAbsences,
      ),
      _ExtrasEntry(
        key: const Key('extras-course-materials'),
        icon: Icons.folder_copy_outlined,
        title: l10n.text('sidebar.courseMaterials'),
        subtitle: l10n.text('extras.courseMaterials.subtitle'),
        onTap: showCourseMaterials,
      ),
    ];
    return GlassPage(
      header: GlassPageHeader(
        surfaceKey: const Key('extras-app-header'),
        titleKey: const Key('extras-header-title'),
        title: l10n.text('extras.title'),
        floatingMaxWidth:
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
      ),
      body: GlassListBody(
        listKey: const Key('extras-list'),
        children: [
          for (final (index, entry) in entries.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            entry,
          ],
        ],
      ),
    );
  }
}

/// A page of Extras: a glass card that opens it.
class _ExtrasEntry extends StatelessWidget {
  const _ExtrasEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
