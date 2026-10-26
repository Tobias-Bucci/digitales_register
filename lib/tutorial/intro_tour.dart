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

import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One page of the intro: an icon illustration, a headline and a short text.
class IntroTourPage {
  const IntroTourPage({required this.key, required this.icon});

  /// Suffix of `tutorial.page.<key>.title` and `.body`.
  final String key;
  final IconData icon;
}

const introTourPages = <IntroTourPage>[
  IntroTourPage(key: 'welcome', icon: Icons.waving_hand_rounded),
  IntroTourPage(key: 'dashboard', icon: Icons.dashboard_customize_rounded),
  IntroTourPage(key: 'grades', icon: Icons.insights_rounded),
  IntroTourPage(key: 'calendar', icon: Icons.calendar_month_rounded),
  IntroTourPage(key: 'settings', icon: Icons.tune_rounded),
];

/// A short, full-screen swipe intro. Pops with `true` when finished and
/// `false` when skipped.
class IntroTour extends StatefulWidget {
  const IntroTour({
    super.key,
    required this.language,
    required this.onLanguageSelected,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageSelected;

  static Route<bool> route({
    required AppLanguage language,
    required ValueChanged<AppLanguage> onLanguageSelected,
  }) =>
      PageRouteBuilder<bool>(
        settings: const RouteSettings(name: '/intro'),
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => IntroTour(
          language: language,
          onLanguageSelected: onLanguageSelected,
        ),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  State<IntroTour> createState() => _IntroTourState();
}

class _IntroTourState extends State<IntroTour> {
  final _controller = PageController();
  late AppLanguage _language = widget.language;
  int _page = 0;

  bool get _isLast => _page == introTourPages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= introTourPages.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
    } else {
      unawaited(_controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ));
    }
  }

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop(true);
    } else {
      _goTo(_page + 1);
    }
  }

  void _skip() => Navigator.of(context).pop(false);

  void _selectLanguage(AppLanguage language) {
    setState(() => _language = language);
    widget.onLanguageSelected(language);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_page - 1),
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.text('tutorial.progress', args: {
                                'current': '${_page + 1}',
                                'total': '${introTourPages.length}',
                              }),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _isLast ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            child: TextButton(
                              onPressed: _isLast ? null : _skip,
                              child: Text(l10n.text('tutorial.skip')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: introTourPages.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => _IntroPageView(
                          page: introTourPages[index],
                          accentIndex: index,
                          active: index == _page,
                          footer: index == 0
                              ? _LanguagePicker(
                                  selected: _language,
                                  onSelected: _selectLanguage,
                                )
                              : null,
                        ),
                      ),
                    ),
                    _PageDots(count: introTourPages.length, current: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: AnimatedOpacity(
                                opacity: _page == 0 ? 0 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: TextButton(
                                  onPressed: _page == 0
                                      ? null
                                      : () => _goTo(_page - 1),
                                  child: Text(l10n.text('tutorial.back')),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const Key('intro-next'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(112, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _next,
                            iconAlignment: IconAlignment.end,
                            icon: Icon(_isLast
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded),
                            label: Text(l10n.text(
                                _isLast ? 'tutorial.finish' : 'tutorial.next')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPageView extends StatelessWidget {
  const _IntroPageView({
    required this.page,
    required this.accentIndex,
    required this.active,
    this.footer,
  });

  final IntroTourPage page;
  final int accentIndex;
  final bool active;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 420);
    return LayoutBuilder(
      builder: (context, constraints) {
        final illustrationSize =
            (constraints.maxHeight * 0.38).clamp(120.0, 240.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: active ? 1 : 0.85,
                  duration: duration,
                  curve: Curves.easeOutBack,
                  child: _IntroIllustration(
                    icon: page.icon,
                    size: illustrationSize,
                    accentIndex: accentIndex,
                  ),
                ),
                SizedBox(height: illustrationSize * 0.18),
                AnimatedSlide(
                  offset: active ? Offset.zero : const Offset(0, 0.15),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: duration,
                    child: Column(
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.text('tutorial.page.${page.key}.title'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.text('tutorial.page.${page.key}.body'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        if (footer != null) ...[
                          const SizedBox(height: 24),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Layered palette shapes around a large icon; no image assets needed.
class _IntroIllustration extends StatelessWidget {
  const _IntroIllustration({
    required this.icon,
    required this.size,
    required this.accentIndex,
  });

  final IconData icon;
  final double size;
  final int accentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accents = [
      (scheme.primary, scheme.primaryContainer, scheme.onPrimaryContainer),
      (
        scheme.secondary,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer
      ),
      (scheme.tertiary, scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final (accent, container, onContainer) =
        accents[accentIndex % accents.length];
    final (second, secondContainer, _) =
        accents[(accentIndex + 1) % accents.length];
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    container,
                    container.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Positioned(
              top: size * 0.08,
              right: size * 0.1,
              child: _Dot(size: size * 0.16, color: secondContainer),
            ),
            Positioned(
              bottom: size * 0.14,
              left: size * 0.08,
              child: _Dot(size: size * 0.09, color: second),
            ),
            Positioned(
              top: size * 0.26,
              left: size * 0.12,
              child: _Dot(size: size * 0.05, color: accent),
            ),
            Transform.rotate(
              angle: -0.08,
              child: Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: BoxDecoration(
                  color: container,
                  borderRadius: BorderRadius.circular(size * 0.14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: size * 0.12,
                      offset: Offset(0, size * 0.04),
                    ),
                  ],
                ),
                child: Icon(icon, size: size * 0.26, color: onContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == current ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.selected, required this.onSelected});

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  static String _name(AppLanguage language) => switch (language) {
        AppLanguage.de => 'Deutsch',
        AppLanguage.it => 'Italiano',
        AppLanguage.lld => 'Ladin',
        AppLanguage.en => 'English',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.l10n.text('tutorial.language.label'),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final language in AppLanguage.values)
            ChoiceChip(
              label: Text(_name(language)),
              selected: language == selected,
              onSelected: (_) => onSelected(language),
            ),
        ],
      ),
    );
  }
}
