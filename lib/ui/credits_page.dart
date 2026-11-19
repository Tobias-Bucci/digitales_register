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
import 'package:dr/ui/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// The width the thank-you stays readable at in a wide window.
const _thanksMaxWidth = 560.0;

/// A general thank-you to everyone who helped with the app (#152).
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

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
        body: const GlassListBody(
          listKey: Key('credits-list'),
          children: [
            _CreditsHeader(),
            SizedBox(height: 20),
            _CreditsThanks(glass: true),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('credits.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          _CreditsHeader(),
          SizedBox(height: 24),
          _CreditsThanks(),
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
            context.l10n.text('credits.heading'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The thank-you itself, in the card of the current design.
class _CreditsThanks extends StatelessWidget {
  const _CreditsThanks({this.glass = false});

  /// A glass card of the new design rather than a Material card.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      context.l10n.text('credits.intro'),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _thanksMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: glass
              ? GlassCard(child: text)
              : Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: text,
                  ),
                ),
        ),
      ),
    );
  }
}
