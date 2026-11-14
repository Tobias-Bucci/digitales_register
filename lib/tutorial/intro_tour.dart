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
import 'package:dr/tutorial/design_choice.dart';
import 'package:dr/tutorial/intro_illustrations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One page of the intro: an illustration, a headline and a short text.
class IntroTourPage {
  const IntroTourPage({required this.key, required this.icon});

  /// Suffix of `tutorial.page.<key>.title` and `.body`.
  final String key;

  /// The picture of the welcome page; the other pages draw the app.
  final IconData icon;
}

/// The main areas of the new design, then the choice of the design (#109).
const introTourPages = <IntroTourPage>[
  IntroTourPage(key: 'welcome', icon: Icons.waving_hand_rounded),
  IntroTourPage(key: 'dashboard', icon: Icons.dashboard_rounded),
  IntroTourPage(key: 'navigation', icon: Icons.explore_rounded),
  IntroTourPage(key: 'notifications', icon: Icons.notifications_rounded),
  IntroTourPage(key: 'colors', icon: Icons.palette_rounded),
  IntroTourPage(key: 'settings', icon: Icons.tune_rounded),
  // Always last: the choice between the new and the legacy design (#108).
  IntroTourPage(key: 'design', icon: Icons.auto_awesome_rounded),
];

const _designPage = 'design';

/// The tour as shown: the web app has the new design only (no choice).
final List<IntroTourPage> _tourPages = kIsWeb
    ? introTourPages.where((p) => p.key != _designPage).toList()
    : introTourPages;

/// From this width a page puts its picture beside the text.
const _wideLayout = 720.0;

/// A short, full-screen swipe intro. Pops with `true` when finished and
/// `false` when skipped.
class IntroTour extends StatefulWidget {
  const IntroTour({
    super.key,
    required this.language,
    required this.onLanguageSelected,
    this.legacyDesign = false,
    this.designChoicePending = false,
    this.onDesignChosen,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageSelected;

  /// The design selected on the last page until the user picks another.
  final bool legacyDesign;

  /// Whether the user has never chosen a design. Skipping then leads to the
  /// last page instead of closing, since the choice cannot be skipped.
  final bool designChoicePending;

  /// Called with the chosen value of `legacyDesign` when the intro finishes.
  final ValueChanged<bool>? onDesignChosen;

  static Route<bool> route({
    required AppLanguage language,
    required ValueChanged<AppLanguage> onLanguageSelected,
    bool legacyDesign = false,
    bool designChoicePending = false,
    ValueChanged<bool>? onDesignChosen,
  }) =>
      PageRouteBuilder<bool>(
        settings: const RouteSettings(name: '/intro'),
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => IntroTour(
          language: language,
          onLanguageSelected: onLanguageSelected,
          legacyDesign: legacyDesign,
          designChoicePending: designChoicePending,
          onDesignChosen: onDesignChosen,
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
  final _focusNode = FocusNode(debugLabel: 'intro-tour');
  late AppLanguage _language = widget.language;
  late bool _legacyDesign = widget.legacyDesign;
  int _page = 0;

  bool get _isLast => _page == _tourPages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Enter goes on while nothing inside the tour has the focus. On a button
  /// or a chip it stays theirs.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        FocusManager.instance.primaryFocus != node ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    _next();
    return KeyEventResult.handled;
  }

  void _goTo(int page) {
    if (page < 0 || page >= _tourPages.length) return;
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
      widget.onDesignChosen?.call(_legacyDesign);
      Navigator.of(context).pop(true);
    } else {
      _goTo(_page + 1);
    }
  }

  void _skip() {
    if (widget.designChoicePending && !_isLast) {
      _goTo(_tourPages.length - 1);
    } else {
      Navigator.of(context).pop(false);
    }
  }

  void _selectLanguage(AppLanguage language) {
    setState(() => _language = language);
    widget.onLanguageSelected(language);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final wide = MediaQuery.sizeOf(context).width >= _wideLayout;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_page - 1),
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 960 : 560),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            // Read out again on every page: "Step 2 of 7".
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                l10n.text('tutorial.progress', args: {
                                  'current': '${_page + 1}',
                                  'total': '${_tourPages.length}',
                                }),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                          // Gives way to the progress with large text.
                          Flexible(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: ExcludeSemantics(
                                excluding: _isLast,
                                child: AnimatedOpacity(
                                  opacity: _isLast ? 0 : 1,
                                  duration: fade,
                                  child: TextButton(
                                    onPressed: _isLast ? null : _skip,
                                    // Smaller rather than broken mid-word.
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        l10n.text('tutorial.skip'),
                                        maxLines: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _tourPages.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => _IntroPageView(
                          page: _tourPages[index],
                          accentIndex: index,
                          active: index == _page,
                          footer: index == 0
                              ? _LanguagePicker(
                                  selected: _language,
                                  onSelected: _selectLanguage,
                                  alignStart: wide,
                                )
                              : _tourPages[index].key == _designPage
                                  ? Column(
                                      children: [
                                        DesignChoicePicker(
                                          legacySelected: _legacyDesign,
                                          onChanged: (legacy) => setState(
                                              () => _legacyDesign = legacy),
                                        ),
                                        const SizedBox(height: 16),
                                        DesignChoiceLaterNote(
                                            legacySelected: _legacyDesign),
                                      ],
                                    )
                                  : null,
                        ),
                      ),
                    ),
                    _PageDots(count: _tourPages.length, current: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ExcludeSemantics(
                                excluding: _page == 0,
                                child: AnimatedOpacity(
                                  opacity: _page == 0 ? 0 : 1,
                                  duration: fade,
                                  child: TextButton(
                                    onPressed: _page == 0
                                        ? null
                                        : () => _goTo(_page - 1),
                                    child: Text(l10n.text('tutorial.back')),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 2,
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
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
                                label: Text(l10n.text(_isLast
                                    ? 'tutorial.finish'
                                    : 'tutorial.next')),
                              ),
                            ),
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
    final isDesign = page.key == _designPage;
    // Large text needs the height for itself; the picture gives way.
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideLayout && !isDesign;
        final align = wide ? TextAlign.start : TextAlign.center;
        final text = AnimatedSlide(
          offset: active ? Offset.zero : const Offset(0, 0.15),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: duration,
            child: Column(
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.text('tutorial.page.${page.key}.title'),
                    textAlign: align,
                    style: (wide
                            ? theme.textTheme.headlineMedium
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      height: 1.2,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.text('tutorial.page.${page.key}.body'),
                  textAlign: align,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 24),
                  footer!,
                ],
              ],
            ),
          ),
        );
        // The previews of the designs are the picture of that page.
        Widget? picture(double width, double height) => isDesign
            ? null
            : AnimatedScale(
                scale: active ? 1 : 0.9,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: _illustration(width, height),
              );

        if (wide) {
          final height = (constraints.maxHeight * 0.6).clamp(160.0, 360.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 24),
              child: Row(
                children: [
                  Expanded(
                    flex: 11,
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, box) =>
                            picture(box.maxWidth, height)!,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                  Expanded(flex: 9, child: text),
                ],
              ),
            ),
          );
        }

        final height = (constraints.maxHeight * (largeText ? 0.24 : 0.36))
            .clamp(96.0, 230.0);
        final illustration = picture(constraints.maxWidth - 2 * 24, height);
        return SingleChildScrollView(
          // The two design cards need the width more than the margin.
          padding: EdgeInsets.symmetric(
              horizontal: isDesign ? 16 : 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (illustration != null) ...[
                  illustration,
                  SizedBox(height: largeText ? 16 : 28),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: text,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _illustration(double width, double height) {
    final drawing = switch (page.key) {
      'dashboard' => const DashboardIllustration(),
      'navigation' => const NavigationIllustration(),
      'notifications' => const NotificationsIllustration(),
      'colors' => const SubjectColorsIllustration(),
      'settings' => const SettingsIllustration(),
      _ => null,
    };
    if (drawing == null) {
      return _IntroIllustration(
        icon: page.icon,
        size: height,
        accentIndex: accentIndex,
      );
    }
    return IntroStage(width: width, height: height, child: drawing);
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
  const _LanguagePicker({
    required this.selected,
    required this.onSelected,
    this.alignStart = false,
  });

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  /// Under text that starts at the side, as in wide windows.
  final bool alignStart;

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
        alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
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
