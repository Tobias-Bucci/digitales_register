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
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// A person thanked on the credits page.
///
/// To add someone, append an entry here and add its `roleKey` and
/// `messageKey` to every locale file.
class CreditEntry {
  const CreditEntry({
    required this.name,
    required this.roleKey,
    required this.messageKey,
  });

  final String name;
  final String roleKey;
  final String messageKey;

  String get initials => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();
}

const credits = <CreditEntry>[
  CreditEntry(
    name: 'Gabriel Albarello',
    roleKey: 'credits.gabrielAlbarello.role',
    messageKey: 'credits.gabrielAlbarello.message',
  ),
];

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key, this.entries = credits});

  final List<CreditEntry> entries;

  Color _accent(int index) =>
      AppPalette.subjectSwatches[index * 5 % AppPalette.subjectSwatches.length];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (ResponsiveNavigationScope.isActive(context)) {
      return GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('credits-app-header'),
          title: l10n.text('credits.title'),
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        ),
        body: GlassListBody(
          listKey: const Key('credits-list'),
          children: [
            const _CreditsHeader(),
            const SizedBox(height: 20),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _CreditCard(entry: entries[i], accent: _accent(i), glass: true),
            ],
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('credits.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _CreditsHeader(),
          const SizedBox(height: 24),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _CreditCard(
              entry: entries[i],
              accent: _accent(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditsHeader extends StatelessWidget {
  const _CreditsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primaryContainer,
          ),
          child: Icon(
            Icons.favorite_rounded,
            size: 42,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            l10n.text('credits.heading'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            l10n.text('credits.intro'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.entry,
    required this.accent,
    this.glass = false,
  });

  final CreditEntry entry;
  final Color accent;

  /// A glass card of the new design rather than a Material card.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final onAccent = glass ? AppPalette.onSubjectColor(accent) : Colors.white;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 26,
                backgroundColor: accent,
                foregroundColor: onAccent,
                child: Text(
                  entry.initials,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: glass
                        ? theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.text(entry.roleKey),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              l10n.text(entry.messageKey),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
    if (glass) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        child: Semantics(container: true, child: content),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: content,
      ),
    );
  }
}
