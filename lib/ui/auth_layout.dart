// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/auth_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// A shared, route-local presentation for sign-in and password recovery:
/// one continuous surface with a single centred column.
///
/// The column assembles top to bottom the first time the route is built,
/// using one [AnimationController]. It never replays on rebuilds, theme or
/// keyboard changes, and never blocks input while it runs.
class AuthLayout extends StatefulWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.showAppBar = false,
    this.allowBack = true,
    this.onEntered,
    this.fitToScreen = false,
    this.collapseHeader = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showAppBar, allowBack;

  /// Called once the entrance has finished (immediately with reduced motion).
  final VoidCallback? onEntered;

  /// Tighten the vertical rhythm (see [AuthSpacing]) so the screen fits a
  /// portrait phone without scrolling, if that is possible at all.
  final bool fitToScreen;

  /// Folds the icon and subtitle away and shrinks the title, giving the
  /// content below more room (e.g. for suggestions above the keyboard).
  final bool collapseHeader;

  /// The title size while the header is collapsed.
  static const collapsedTitle = 22.0;

  static const fieldGap = AuthGap.field();
  static const sectionGap = AuthGap.section();
  static const radius = AuthTokens.radius;

  static bool isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// Forgets the keyboard height remembered for this session.
  @visibleForTesting
  static void debugResetKeyboardMemory() =>
      _AuthLayoutState._rememberedKeyboard = 0;

  /// Platforms with an on-screen keyboard.
  static bool isPhone(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.android;

  static ThemeData themeFor(ThemeData base, [AuthTokens? tokens]) {
    final dark = base.brightness == Brightness.dark;
    final t = tokens ?? (dark ? AuthTokens.dark : AuthTokens.light);
    final colors = base.colorScheme.copyWith(
      primary: t.accent,
      // Material derives the selected switch thumb from this.
      onPrimary: t.switchThumb,
      surface: t.background,
      onSurface: t.primaryText,
      onSurfaceVariant: t.secondaryText,
      surfaceContainerLow: t.groupFill,
      surfaceContainer: t.groupFill,
      surfaceContainerHigh: t.groupFill,
      outline: t.fieldBorder,
      outlineVariant: t.hairline,
      error: t.errorText,
      surfaceTint: Colors.transparent,
    );
    final text = _tighten(base.textTheme.apply(
      bodyColor: t.primaryText,
      displayColor: t.primaryText,
    ));
    WidgetStateProperty<T> states<T>(T Function(Set<WidgetState>) resolve) =>
        WidgetStateProperty.resolveWith(resolve);

    final border =
        AuthFieldBorder(borderSide: BorderSide(color: t.fieldBorder));
    final inputText = text.bodyLarge?.copyWith(fontSize: 17, height: 1.25);
    final apple = isApple(base.platform);
    return base.copyWith(
      colorScheme: colors,
      textTheme: text,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      dividerColor: t.hairline,
      // Same control sizes on every platform; desktop would otherwise
      // shrink fields to 48 px and links below a comfortable target.
      visualDensity: VisualDensity.standard,
      // State layers instead of ink ripples on Apple platforms.
      splashFactory: apple ? NoSplash.splashFactory : base.splashFactory,
      extensions: [...base.extensions.values, t],
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.3),
        selectionHandleColor: t.accent,
      ),
      // Borders and fill are animated per field by [AuthFieldFrame]; these
      // are the resting values for fields without one.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: t.fieldFill,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
        labelStyle: inputText?.copyWith(color: t.secondaryText),
        // Drawn at 75 %, so this ends up at about 13 px.
        floatingLabelStyle: inputText?.copyWith(color: t.secondaryText),
        hintStyle: inputText?.copyWith(color: t.secondaryText),
        errorStyle: text.bodySmall?.copyWith(fontSize: 13, color: t.errorText),
        errorMaxLines: 4,
        helperStyle:
            text.bodySmall?.copyWith(fontSize: 13, color: t.secondaryText),
        helperMaxLines: 2,
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder:
            border.copyWith(borderSide: BorderSide(color: t.accent, width: 2)),
        errorBorder: border.copyWith(borderSide: BorderSide(color: t.error)),
        focusedErrorBorder:
            border.copyWith(borderSide: BorderSide(color: t.error, width: 2)),
        suffixIconColor: t.secondaryText,
        suffixIconConstraints:
            const BoxConstraints(minWidth: 48, minHeight: 48),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(
              Size.fromHeight(AuthTokens.controlHeight)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          shape: const WidgetStatePropertyAll(
              RoundedSuperellipseBorder(borderRadius: AuthTokens.radius)),
          textStyle: WidgetStatePropertyAll(text.titleMedium?.copyWith(
              fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
          backgroundColor: states((s) {
            if (s.contains(WidgetState.disabled)) return t.disabledFill;
            if (s.contains(WidgetState.pressed)) return t.accentFillPressed;
            if (s.contains(WidgetState.hovered)) return t.accentFillHover;
            return t.accentFill;
          }),
          foregroundColor: states((s) =>
              s.contains(WidgetState.disabled) ? t.disabledText : t.onAccent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          // A soft outer ring, like a macOS focus ring.
          side: states((s) => s.contains(WidgetState.focused)
              ? BorderSide(
                  color: t.accent.withValues(alpha: 0.5),
                  width: 3,
                  strokeAlign: BorderSide.strokeAlignOutside)
              : BorderSide.none),
          mouseCursor: states((s) => s.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click),
          animationDuration: AuthMotion.fast,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accentFill,
          foregroundColor: t.onAccent,
          shape:
              const RoundedSuperellipseBorder(borderRadius: AuthTokens.radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(t.link),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: AuthTokens.space1)),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: const WidgetStatePropertyAll(
              RoundedSuperellipseBorder(borderRadius: AuthTokens.radius)),
          // Pressing dims the label ([AuthLink]); only keyboard focus draws
          // a state layer.
          overlayColor: states((s) => s.contains(WidgetState.focused)
              ? t.link.withValues(alpha: 0.12)
              : Colors.transparent),
          textStyle: WidgetStatePropertyAll(text.bodyLarge!
              .copyWith(fontSize: 15, fontWeight: FontWeight.w400)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: t.secondaryText,
          iconSize: 20,
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: dark ? t.groupFill : t.background,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(20))),
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        contentTextStyle:
            text.bodyMedium?.copyWith(color: t.secondaryText, height: 1.4),
      ),
      tooltipTheme: base.tooltipTheme
          .copyWith(waitDuration: const Duration(milliseconds: 600)),
    );
  }

  /// Removes Material's wide tracking: display and headline styles get
  /// -0.4, body and title text -0.2, small labels -0.1.
  static TextTheme _tighten(TextTheme text) {
    TextStyle? track(TextStyle? style, double spacing) =>
        style?.copyWith(letterSpacing: spacing);
    return text.copyWith(
      displayLarge: track(text.displayLarge, -0.4),
      displayMedium: track(text.displayMedium, -0.4),
      displaySmall: track(text.displaySmall, -0.4),
      headlineLarge: track(text.headlineLarge, -0.4),
      headlineMedium: track(text.headlineMedium, -0.4),
      headlineSmall: track(text.headlineSmall, -0.4),
      titleLarge: track(text.titleLarge, -0.2),
      titleMedium: track(text.titleMedium, -0.2),
      titleSmall: track(text.titleSmall, -0.2),
      bodyLarge: track(text.bodyLarge, -0.2),
      bodyMedium: track(text.bodyMedium, -0.2),
      bodySmall: track(text.bodySmall, -0.1),
      labelLarge: track(text.labelLarge, -0.2),
      labelMedium: track(text.labelMedium, -0.1),
      labelSmall: track(text.labelSmall, -0.1),
    );
  }

  @override
  State<AuthLayout> createState() => _AuthLayoutState();
}

class _AuthLayoutState extends State<AuthLayout>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The height the keyboard reached when it last slid in, so a list
  /// opening alongside the keyboard can size itself for it before it has
  /// finished sliding in (rotation or another keyboard update it).
  static double _rememberedKeyboard = 0;

  /// Whether the keyboard inset changed within the last settle window.
  bool _keyboardMoving = false;
  Timer? _keyboardSettled;

  late final AnimationController _entrance;
  final _scroll = _RevealScrollController();
  final _columnKey = GlobalKey();
  final _keyboard = _KeyboardWatch();
  bool _started = false;

  // First-run fit: the spacing tier in use, the screen it was chosen for,
  // whether tiers are still being tried and whether the chosen one fits.
  AuthSpacing _spacing = AuthSpacing.comfortable;
  Object? _fitKey;
  bool _fitting = false, _fits = false, _overflowing = false;

  double? _lastInset;
  FocusNode? _lastFocus;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: AuthMotion.entrance)
      ..addStatusListener(_onEntranceStatus);
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastInset ??= MediaQuery.viewInsetsOf(context).bottom;
    _scroll.reduced = AuthMotion.reduced(context);
    // The entrance plays once per screen, never on later dependency changes.
    if (_started) return;
    _started = true;
    if (AuthMotion.reduced(context)) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (!status.isCompleted) return;
    // After the frame: with reduced motion this fires during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEntered?.call();
    });
  }

  @override
  void didChangeMetrics() {
    // View insets are physical pixels; everything else here is logical.
    final view = View.of(context);
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    if (inset == _lastInset) return;
    // Sliding in: the latest (largest) value is the keyboard's height.
    if (inset > (_lastInset ?? 0)) _rememberedKeyboard = inset;
    _lastInset = inset;
    _keyboard.mark();
    _keyboardMoving = true;
    _keyboardSettled?.cancel();
    _keyboardSettled = Timer(AuthMotion.keyboardSettle, () {
      if (mounted) setState(() => _keyboardMoving = false);
    });
  }

  /// On phones a newly focused (or unfocused) field opens (or closes) the
  /// keyboard a moment later; size animations hold still meanwhile.
  void _onFocusChange() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == _lastFocus) return;
    _lastFocus = focus;
    if (AuthLayout.isPhone(Theme.of(context).platform)) _keyboard.mark();
  }

  /// Chooses the roomiest spacing tier whose measured content fits the
  /// viewport, once per screen size, safe area and text scale. Only for a
  /// portrait first run at normal text size; otherwise (and if even the
  /// tightest allowed tier overflows) the comfortable layout scrolls.
  void _updateFit(MediaQueryData media) {
    final key = (
      media.size,
      media.padding,
      media.textScaler.scale(16),
      widget.fitToScreen,
    );
    // The keyboard never changes the tier.
    if (key == _fitKey || media.viewInsets.bottom > 0) return;
    _fitKey = key;
    _spacing = AuthSpacing.comfortable;
    _fits = _overflowing = false;
    _fitting = widget.fitToScreen &&
        media.size.height > media.size.width &&
        media.textScaler.scale(16) <= 16 * 1.15;
    if (_fitting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkFit());
    }
  }

  void _checkFit() {
    if (!mounted || !_fitting || !_scroll.hasClients) return;
    final column = _columnKey.currentContext?.findRenderObject() as RenderBox?;
    if (column == null || !column.hasSize) return;
    // Real render sizes: the column plus its page padding against the
    // viewport, with a small safety margin.
    final viewport = _scroll.position.viewportDimension;
    final padding = viewport < _AuthScaffold.shortHeight
        ? AuthTokens.space3
        : _spacing.page;
    final overflow =
        column.size.height + 2 * padding - (viewport - AuthSpacing.fitMargin);
    if (overflow <= 0) {
      _fitting = false;
      setState(() => _fits = true);
      return;
    }
    final next = AuthSpacing.tiers.indexOf(_spacing) + 1;
    final ultra =
        AuthSpacing.tiers[next.clamp(0, AuthSpacing.tiers.length - 1)] ==
            AuthSpacing.ultraTight;
    if (next < AuthSpacing.tiers.length &&
        !(ultra && overflow >= AuthSpacing.ultraTightReach)) {
      setState(() => _spacing = AuthSpacing.tiers[next]);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkFit());
    } else {
      // Not even the tightest tier fits: keep the design and scroll.
      _fitting = false;
      setState(() {
        _spacing = AuthSpacing.comfortable;
        _fits = false;
      });
    }
  }

  /// Content that grows later (an error, the address field) unlocks the
  /// page again instead of being clipped.
  void _onScrollMetrics(ScrollMetrics metrics) {
    if (!_fits || MediaQuery.viewInsetsOf(context).bottom > 0) return;
    final overflowing = metrics.maxScrollExtent > 0.5;
    if (overflowing != _overflowing) {
      setState(() => _overflowing = overflowing);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardSettled?.cancel();
    _scroll.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    _updateFit(media);
    final inset = media.viewInsets.bottom;
    final base = Theme.of(context);
    final phone = AuthLayout.isPhone(base.platform);
    final target =
        base.brightness == Brightness.dark ? AuthTokens.dark : AuthTokens.light;
    // A fitting first run cannot be dragged at all (no bounce or glow) while
    // the keyboard is closed; with the keyboard it scrolls as usual.
    final locked = _fits && !_overflowing && inset == 0;
    return _AuthKeyboardScope(
      watch: _keyboard,
      inset: inset,
      // The navigation bar, from the view itself: the app's SafeArea has
      // already removed it from this MediaQuery.
      navigationBar: View.of(context).viewPadding.bottom /
          View.of(context).devicePixelRatio,
      // Only while the keyboard is still moving; once it has settled its
      // real height counts. Before the first keyboard of the session:
      // about 40 % of the screen.
      expected: phone && _keyboardMoving
          ? (_rememberedKeyboard > 0
              ? _rememberedKeyboard
              : media.size.height * 0.4)
          : 0,
      child: AuthSpacingScope(
        spacing: _spacing,
        child: TweenAnimationBuilder<AuthTokens>(
          tween: _AuthTokensTween(end: target),
          duration: AuthMotion.fade(context, AuthMotion.base),
          curve: AuthMotion.standard,
          // Cross-fades every auth colour when the system switches
          // light/dark.
          builder: (context, tokens, child) =>
              Theme(data: AuthLayout.themeFor(base, tokens), child: child!),
          child: _AuthScaffold(
            layout: widget,
            entrance: _entrance,
            scroll: _scroll,
            columnKey: _columnKey,
            locked: locked,
            onScrollMetrics: _onScrollMetrics,
          ),
        ),
      ),
    );
  }
}

/// Animated page scrolls (a focused field being revealed above the keyboard,
/// room for the suggestions) all use the reveal timing instead of each
/// caller's own; jumps, such as following the keyboard frame by frame, stay
/// jumps.
class _RevealScrollController extends ScrollController {
  bool reduced = false;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _RevealScrollPosition(
          controller: this,
          physics: physics,
          context: context,
          oldPosition: oldPosition);
}

class _RevealScrollPosition extends ScrollPositionWithSingleContext {
  _RevealScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _RevealScrollController controller;

  @override
  Future<void> animateTo(double to,
      {required Duration duration, required Curve curve}) {
    if (controller.reduced) {
      jumpTo(to);
      return Future.value();
    }
    return super.animateTo(to,
        duration: AuthMotion.reveal, curve: AuthMotion.decelerate);
  }
}

/// Remembers when the keyboard last started moving.
class _KeyboardWatch {
  Duration? _until;

  static Duration get _now =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  void mark() => _until = _now + AuthMotion.keyboardSettle;

  bool get settling => _until != null && _now < _until!;
}

class _AuthKeyboardScope extends InheritedWidget {
  const _AuthKeyboardScope({
    required this.watch,
    required this.inset,
    required this.navigationBar,
    required this.expected,
    required super.child,
  });

  final _KeyboardWatch watch;

  /// The navigation bar's height at the screen's bottom.
  final double navigationBar;

  /// The keyboard's current height (the real view inset; Scaffold hides it
  /// from its body).
  final double inset;

  /// The keyboard's full height, as far as it is known.
  final double expected;

  @override
  bool updateShouldNotify(_AuthKeyboardScope old) =>
      old.inset != inset ||
      old.expected != expected ||
      old.navigationBar != navigationBar;
}

/// Whether the keyboard is opening or closing right now. Size animations
/// (reveals, field heights) jump instead of running on top of it.
bool authKeyboardSettling(BuildContext context) =>
    context
        .getInheritedWidgetOfExactType<_AuthKeyboardScope>()
        ?.watch
        .settling ??
    false;

/// How much of the screen's bottom (in logical pixels from the screen's
/// bottom edge) is unusable: the keyboard, which covers the navigation bar
/// while it is up, or else the navigation bar. With [expectingKeyboard] the
/// keyboard counts with its full height from the moment it starts opening,
/// so a list does not first size itself for a half-open keyboard. Rebuilds
/// the caller whenever it changes.
double authObstructedBottom(BuildContext context,
    {required bool expectingKeyboard}) {
  final scope =
      context.dependOnInheritedWidgetOfExactType<_AuthKeyboardScope>();
  if (scope == null) {
    final media = MediaQuery.of(context);
    return math.max(media.viewInsets.bottom, media.viewPadding.bottom);
  }
  // The expected height only once a keyboard is actually opening: with a
  // hardware keyboard (or none) no on-screen one ever comes.
  final keyboard = expectingKeyboard && scope.inset > 0
      ? math.max(scope.inset, scope.expected)
      : scope.inset;
  return math.max(keyboard, scope.navigationBar);
}

/// Scrolls the focused field just into view if something (the keyboard)
/// covers it, leaving [AuthTokens.fieldScrollPadding] below it; never more
/// than needed and never to the top. For layout changes the field's own
/// reveal does not see, such as the header unfolding while a field is
/// focused.
void authRevealFocusedField() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null || !focused.mounted) return;
  final frame = focused.findAncestorStateOfType<_AuthFieldFrameState>();
  final box = (frame?.context ?? focused).findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return;
  const padding = AuthTokens.fieldScrollPadding;
  box.showOnScreen(
    rect: Rect.fromLTRB(
        0, -padding.top, box.size.width, box.size.height + padding.bottom),
    duration: AuthMotion.reveal,
    curve: AuthMotion.decelerate,
  );
}

/// Provides the active [AuthSpacing] tier to the column's gaps.
class AuthSpacingScope extends InheritedWidget {
  const AuthSpacingScope(
      {super.key, required this.spacing, required super.child});

  final AuthSpacing spacing;

  static AuthSpacing of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthSpacingScope>()?.spacing ??
      AuthSpacing.comfortable;

  @override
  bool updateShouldNotify(AuthSpacingScope old) => old.spacing != spacing;
}

enum _GapKind { field, section, button, footer, small }

/// A vertical gap of the sign-in column that follows the spacing tier.
class AuthGap extends StatelessWidget {
  const AuthGap.field({super.key}) : _kind = _GapKind.field;
  const AuthGap.section({super.key}) : _kind = _GapKind.section;
  const AuthGap.button({super.key}) : _kind = _GapKind.button;
  const AuthGap.footer({super.key}) : _kind = _GapKind.footer;

  /// A fixed 8 px step, e.g. between a control and its link.
  const AuthGap.small({super.key}) : _kind = _GapKind.small;

  final _GapKind _kind;

  @override
  Widget build(BuildContext context) {
    final spacing = AuthSpacingScope.of(context);
    return SizedBox(
      height: switch (_kind) {
        _GapKind.field => spacing.field,
        _GapKind.section => spacing.section,
        _GapKind.button => spacing.button,
        _GapKind.footer => spacing.footer,
        _GapKind.small => AuthTokens.space1,
      },
    );
  }
}

class _AuthTokensTween extends Tween<AuthTokens> {
  _AuthTokensTween({required AuthTokens end}) : super(end: end);

  @override
  AuthTokens lerp(double t) => begin!.lerp(end, t);
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.layout,
    required this.entrance,
    required this.scroll,
    required this.columnKey,
    required this.locked,
    required this.onScrollMetrics,
  });

  final AuthLayout layout;
  final Animation<double> entrance;
  final ScrollController scroll;
  final GlobalKey columnKey;

  /// The content fits: no dragging, bounce or overscroll glow.
  final bool locked;
  final ValueChanged<ScrollMetrics> onScrollMetrics;

  /// Below this usable height (landscape phones, tiny windows) the header
  /// is always compact.
  static const shortHeight = 560.0;

  // Entrance timeline (ms of [AuthMotion.entrance]): icon, title and
  // subtitle first, then the content 40 ms apart.
  static const _itemLength = 360, _contentStart = 180, _stagger = 40;
  static const _lastStart = 340;

  Widget _slot(Widget child, int startMs, {int lengthMs = _itemLength}) {
    final total = AuthMotion.entrance.inMilliseconds;
    return _EntranceSlot(
      animation: entrance,
      begin: startMs / total,
      end: math.min(1, (startMs + lengthMs) / total),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    final spacing = AuthSpacingScope.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showIcon = !(layout.showAppBar && layout.allowBack);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: layout.showAppBar && layout.allowBack
            ? AppBar(
                backgroundColor: tokens.background,
                foregroundColor: tokens.primaryText,
                scrolledUnderElevation: 0,
                elevation: 0,
                shape: const Border(),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            // Landscape phones and very small windows.
            final short = constraints.maxHeight < shortHeight;
            final collapsed = layout.collapseHeader;
            var slot = 0;
            Widget content(Widget child) {
              // Spacers keep their place in the rhythm but do not animate.
              if (child is AuthGap ||
                  (child is SizedBox && child.child == null)) {
                return child;
              }
              final start =
                  math.min(_contentStart + _stagger * slot++, _lastStart);
              return _slot(child, start);
            }

            return NotificationListener<ScrollMetricsNotification>(
                onNotification: (notification) {
                  // Only the page's own metrics: nested scrollables (the
                  // suggestion list, text fields) report here too.
                  if (notification.depth == 0) {
                    onScrollMetrics(notification.metrics);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  key: const ValueKey('auth-scroll'),
                  controller: scroll,
                  physics: locked ? const NeverScrollableScrollPhysics() : null,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: AnimatedPadding(
                      duration: AuthMotion.move(context, AuthMotion.base),
                      curve: AuthMotion.decelerate,
                      padding: EdgeInsets.symmetric(
                        horizontal: AuthTokens.space3,
                        vertical: collapsed
                            ? AuthTokens.space2
                            : (short ? AuthTokens.space3 : spacing.page),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: AuthTokens.maxContentWidth),
                          child: Material(
                            type: MaterialType.transparency,
                            child: FocusTraversalGroup(
                              child: AutofillGroup(
                                child: Column(
                                  key: columnKey,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showIcon)
                                      _EntranceSlot(
                                        animation: entrance,
                                        begin: 0,
                                        end: 400 / 700,
                                        scaleFrom: 0.92,
                                        offset: 0,
                                        child: _HeaderPart(
                                          visible: !collapsed,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                                bottom: short
                                                    ? AuthTokens.space2
                                                    : spacing.iconGap),
                                            child: Center(
                                                child: AuthAppIcon(
                                                    size: short
                                                        ? 56
                                                        : spacing.icon)),
                                          ),
                                        ),
                                      ),
                                    _slot(
                                      _AuthTitle(
                                        title: layout.title,
                                        size: collapsed
                                            ? AuthLayout.collapsedTitle
                                            : wide && !short
                                                ? 34
                                                : (short ? 28 : spacing.title),
                                      ),
                                      60,
                                    ),
                                    if (layout.subtitle != null)
                                      _slot(
                                        _HeaderPart(
                                          visible: !collapsed,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                top: AuthTokens.space1),
                                            child: _AuthSubtitle(
                                                subtitle: layout.subtitle!,
                                                wide: wide && !short),
                                          ),
                                        ),
                                        120,
                                      ),
                                    _AnimatedGap(
                                        height: collapsed
                                            ? AuthTokens.space2
                                            : spacing.headerGap),
                                    ...layout.children.map(content),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ));
          }),
        ),
      ),
    );
  }
}

/// One step of the entrance: fades in and rises [offset] px (optionally
/// scaling up from [scaleFrom]) between [begin] and [end] of [animation].
/// The child stays interactive and in the semantics tree throughout, and the
/// curved animation is built once rather than on every rebuild.
class _EntranceSlot extends StatefulWidget {
  const _EntranceSlot({
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
    this.scaleFrom,
    this.offset = AuthMotion.entranceOffset,
  });

  final Animation<double> animation;
  final double begin, end;
  final double? scaleFrom;
  final double offset;
  final Widget child;

  @override
  State<_EntranceSlot> createState() => _EntranceSlotState();
}

class _EntranceSlotState extends State<_EntranceSlot> {
  late Animation<double> _progress = _drive();

  Animation<double> _drive() => widget.animation.drive(CurveTween(
      curve: Interval(widget.begin, widget.end, curve: AuthMotion.decelerate)));

  @override
  void didUpdateWidget(_EntranceSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.begin != widget.begin ||
        oldWidget.end != widget.end) {
      _progress = _drive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaleFrom = widget.scaleFrom;
    return FadeTransition(
      opacity: _progress,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) {
          // Always the same widgets, so the child is never remounted.
          final t = _progress.value;
          return Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: Transform.scale(
              scale: scaleFrom == null ? 1 : scaleFrom + (1 - scaleFrom) * t,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _AuthTitle extends StatelessWidget {
  const _AuthTitle({required this.title, required this.size});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    final theme = Theme.of(context);
    // Roboto has no semibold, so 600 would snap to bold there.
    final titleWeight = switch (theme.platform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux =>
        FontWeight.w500,
      _ => FontWeight.w600,
    };
    return Semantics(
      header: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: size),
        duration: AuthMotion.move(context, AuthMotion.base),
        curve: AuthMotion.decelerate,
        builder: (context, size, _) => Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontSize: size,
            fontWeight: titleWeight,
            letterSpacing: -0.4,
            height: 1.15,
            color: tokens.primaryText,
          ),
        ),
      ),
    );
  }
}

/// A header element that folds away (height and opacity) while the header
/// is collapsed. Only ever toggled after the keyboard has settled.
class _HeaderPart extends StatelessWidget {
  const _HeaderPart({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AuthReveal(
        visible: visible,
        fadeDelay: Duration.zero,
        offset: 0,
        ignoreKeyboard: true,
        child: child,
      );
}

/// A vertical gap that eases to a new height.
class _AnimatedGap extends StatelessWidget {
  const _AnimatedGap({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: height),
        duration: AuthMotion.move(context, AuthMotion.base),
        curve: AuthMotion.decelerate,
        builder: (context, height, _) => SizedBox(height: height),
      );
}

class _AuthSubtitle extends StatelessWidget {
  const _AuthSubtitle({required this.subtitle, required this.wide});

  final String subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    return Text(
      subtitle,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: wide ? 17 : 16,
            height: 1.4,
            color: tokens.secondaryText,
          ),
    );
  }
}

/// The app icon in the soft rounded shape used on the sign-in screens.
class AuthAppIcon extends StatelessWidget {
  const AuthAppIcon({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(size * 0.225),
          side: BorderSide(color: tokens.hairline.withValues(alpha: 0.6)),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(size * 0.225),
        child: Image.asset(
          'assets/Icon-App-512x512.png',
          width: size,
          height: size,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// An inline notice. Errors and status updates are announced to screen
/// readers as they appear.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text,
      {super.key, this.isError = false, this.isStatus = false});

  final String text;
  final bool isError, isStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = AuthTokens.of(context);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
        color: isError ? tokens.errorText : tokens.secondaryText);
    return Semantics(
      container: true,
      liveRegion: isError || isStatus,
      child: Container(
        decoration: BoxDecoration(
          color:
              isError ? tokens.error.withValues(alpha: 0.08) : tokens.groupFill,
          borderRadius: AuthTokens.radius,
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: AuthTokens.space2, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : isStatus
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                size: 20,
                color: isError
                    ? tokens.errorText
                    : isStatus
                        ? tokens.accent
                        : tokens.secondaryText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      ),
    );
  }
}

/// Shows and hides [child] by growing its height while it fades in and rises
/// [offset] px, e.g. for messages and progressively disclosed fields.
/// Surrounding content glides instead of jumping. While hiding, the last
/// visible child is kept until the collapse has finished.
class AuthReveal extends StatefulWidget {
  const AuthReveal({
    super.key,
    required this.visible,
    required this.child,
    this.duration = AuthMotion.base,
    this.fadeDelay = const Duration(milliseconds: 60),
    this.offset = AuthMotion.revealOffset,
    this.onHidden,
    this.ignoreKeyboard = false,
  });

  final bool visible;
  final Widget child;
  final Duration duration, fadeDelay;
  final double offset;

  /// Called after a hide has fully collapsed.
  final VoidCallback? onHidden;

  /// Animate even while the keyboard is settling (for changes that are only
  /// made once the keyboard has stopped moving).
  final bool ignoreKeyboard;

  @override
  State<AuthReveal> createState() => _AuthRevealState();
}

class _AuthRevealState extends State<AuthReveal>
    with SingleTickerProviderStateMixin {
  // Created eagerly: a lazy controller would first be built when the reveal
  // turns visible and then start out already complete.
  late final AnimationController _controller;
  late final CurvedAnimation _size;
  late CurvedAnimation _fade;
  Widget? _shown;
  bool _reduced = false, _jumping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: widget.duration, value: widget.visible ? 1 : 0)
      ..addStatusListener(_onStatus);
    _size = CurvedAnimation(
        parent: _controller,
        curve: AuthMotion.decelerate,
        reverseCurve: AuthMotion.accelerate);
    _fade = _fadeCurve();
  }

  CurvedAnimation _fadeCurve() {
    final delay = _reduced
        ? 0.0
        : widget.fadeDelay.inMicroseconds / widget.duration.inMicroseconds;
    return CurvedAnimation(
        parent: _controller,
        curve: Interval(delay.clamp(0, 0.9), 1, curve: AuthMotion.standard));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AuthMotion.reduced(context);
    if (reduced == _reduced) return;
    _reduced = reduced;
    _controller.duration = AuthMotion.fade(context, widget.duration);
    _fade.dispose();
    _fade = _fadeCurve();
  }

  @override
  void didUpdateWidget(AuthReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (!widget.ignoreKeyboard && authKeyboardSettling(context)) {
      // Never resize on top of the keyboard's own animation: jump instead.
      // A jump does not reliably report a status change (a controller
      // created complete believes it last reported "dismissed"), so the
      // hide is finished here rather than in [_onStatus].
      _jumping = true;
      _controller.value = widget.visible ? 1 : 0;
      _jumping = false;
      if (!widget.visible) {
        _shown = null; // about to build anyway
        _notifyHidden();
      }
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (!status.isDismissed || _jumping) return;
    setState(() => _shown = null);
    _notifyHidden();
  }

  void _notifyHidden() {
    final onHidden = widget.onHidden;
    if (onHidden != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onHidden());
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible) _shown = widget.child;
    final shown = _shown;
    if (shown == null) return const SizedBox(width: double.infinity);
    return SizeTransition(
      // With reduced motion the height snaps and only the fade remains.
      sizeFactor: _reduced ? kAlwaysCompleteAnimation : _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        alwaysIncludeSemantics: true,
        child: _reduced || widget.offset == 0
            ? shown
            : AnimatedBuilder(
                animation: _fade,
                child: shown,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, (1 - _fade.value) * widget.offset),
                  child: child,
                ),
              ),
      ),
    );
  }
}

/// Animates a text field's frame: fill and border ease between idle, hover,
/// focus and error instead of swapping, and the field's height glides when
/// an error or helper line appears.
///
/// Flutter's [InputDecorator] would animate border changes itself with a
/// fixed 167 ms curve, so this hands it one border per frame for all states
/// and drives the transition with the auth motion tokens.
class AuthFieldFrame extends StatefulWidget {
  const AuthFieldFrame({
    super.key,
    required this.child,
    this.hasError = false,
    this.enabled = true,
  });

  final Widget child;
  final bool hasError, enabled;

  @override
  State<AuthFieldFrame> createState() => _AuthFieldFrameState();
}

class _AuthFieldFrameState extends State<AuthFieldFrame> {
  bool _focused = false, _hovered = false, _hoverChanged = false;

  @override
  Widget build(BuildContext context) {
    final t = AuthTokens.of(context);
    final focused = _focused && widget.enabled;
    final fill = !widget.enabled
        ? t.fieldFill
        : focused
            ? t.fieldFillFocus
            : _hovered
                ? t.fieldFillHover
                : t.fieldFill;
    final side = widget.hasError
        ? BorderSide(color: t.error, width: focused ? 2 : 1)
        : focused
            ? BorderSide(color: t.accent, width: 2)
            : BorderSide(color: t.fieldBorder);
    final decorationTheme = InputDecorationTheme.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (value) => setState(() {
        _focused = value;
        _hoverChanged = false;
      }),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = _hoverChanged = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _hoverChanged = true;
        }),
        child: TweenAnimationBuilder<_FieldLook>(
          tween: _FieldLookTween(end: _FieldLook(fill, side)),
          duration: AuthMotion.fade(
              context, _hoverChanged ? AuthMotion.instant : AuthMotion.fast),
          curve: AuthMotion.standard,
          builder: (context, look, child) {
            final border = AuthFieldBorder(borderSide: look.side);
            return InputDecorationTheme(
              data: decorationTheme.copyWith(
                fillColor: look.fill,
                border: border,
                enabledBorder: border,
                disabledBorder: border,
                focusedBorder: border,
                errorBorder: border,
                focusedErrorBorder: border,
              ),
              child: child,
            );
          },
          // With reduced motion the height simply changes.
          child: AuthMotion.reduced(context)
              ? widget.child
              : AnimatedSize(
                  // While the keyboard moves the height jumps (a zero
                  // duration trips a layout assertion in AnimatedSize).
                  duration: authKeyboardSettling(context)
                      ? const Duration(microseconds: 1)
                      : AuthMotion.error,
                  curve: AuthMotion.decelerate,
                  alignment: Alignment.topCenter,
                  child: widget.child,
                ),
        ),
      ),
    );
  }
}

@immutable
class _FieldLook {
  const _FieldLook(this.fill, this.side);

  final Color fill;
  final BorderSide side;

  @override
  bool operator ==(Object other) =>
      other is _FieldLook && other.fill == fill && other.side == side;

  @override
  int get hashCode => Object.hash(fill, side);
}

class _FieldLookTween extends Tween<_FieldLook> {
  _FieldLookTween({required _FieldLook end}) : super(end: end);

  @override
  _FieldLook lerp(double t) => _FieldLook(
        Color.lerp(begin!.fill, end!.fill, t)!,
        BorderSide.lerp(begin!.side, end!.side, t),
      );
}

class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.isNewPassword = false,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled, isNewPassword;
  final String? errorText;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction textInputAction;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return AuthFieldFrame(
      hasError: widget.errorText != null,
      enabled: widget.enabled,
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: widget.enabled
            ? [
                if (widget.isNewPassword)
                  AutofillHints.newPassword
                else
                  AutofillHints.password,
              ]
            : null,
        textInputAction: widget.textInputAction,
        scrollPadding: AuthTokens.fieldScrollPadding,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: widget.errorText,
          suffixIcon: IconButton(
            tooltip: context.l10n
                .text(_obscured ? 'login.showPassword' : 'login.hidePassword'),
            onPressed: widget.enabled
                ? () => setState(() => _obscured = !_obscured)
                : null,
            icon: Icon(_obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
          ),
        ),
      ),
    );
  }
}

/// The full-width primary action.
///
/// Its fill and label cross-fade when it becomes enabled ("wakes up") and on
/// hover, it dips to 97 % while pressed, and while [loading] a spinner fades
/// in at the label's place without changing the button's size.
class AuthPrimaryButton extends StatefulWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final String? loadingLabel;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  State<AuthPrimaryButton> createState() => _AuthPrimaryButtonState();
}

class _AuthPrimaryButtonState extends State<AuthPrimaryButton> {
  final _states = WidgetStatesController();
  late bool _wasEnabled = _enabled;
  bool _enabledChanged = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() => _afterBuild(this, () => _enabledChanged = false);

  @override
  void didUpdateWidget(AuthPrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_enabled != _wasEnabled) {
      _wasEnabled = _enabled;
      _enabledChanged = true;
    }
  }

  @override
  void dispose() {
    _states.removeListener(_onStates);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AuthTokens.of(context);
    final states = _states.value;
    final enabled = _enabled;
    final pressed = enabled && states.contains(WidgetState.pressed);
    // One effect per interaction: a press only dips the button, hover only
    // shifts the fill.
    final fill = widget.loading
        ? t.accentFill
        : !enabled
            ? t.disabledFill
            : states.contains(WidgetState.hovered)
                ? t.accentFillHover
                : t.accentFill;
    final label = enabled || widget.loading ? t.onAccent : t.disabledText;
    final reduced = AuthMotion.reduced(context);
    final switchDuration =
        AuthMotion.fade(context, const Duration(milliseconds: 200));
    return RepaintBoundary(
        child: AnimatedScale(
      scale: pressed && !reduced ? AuthMotion.pressScale : 1,
      duration: pressed ? AuthMotion.pressIn : AuthMotion.pressOut,
      curve: pressed ? AuthMotion.pressDown : AuthMotion.pressRelease,
      child: TweenAnimationBuilder<_ButtonLook>(
        tween: _ButtonLookTween(end: _ButtonLook(fill, label)),
        duration: AuthMotion.fade(
            context, _enabledChanged ? AuthMotion.medium : AuthMotion.instant),
        curve: AuthMotion.standard,
        builder: (context, look, child) => ElevatedButton(
          statesController: _states,
          onPressed: enabled ? widget.onPressed : null,
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(look.fill),
            foregroundColor: WidgetStatePropertyAll(look.label),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
          child: child,
        ),
        child: AnimatedSwitcher(
          duration: switchDuration,
          switchInCurve: AuthMotion.decelerate,
          switchOutCurve: AuthMotion.accelerate,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: reduced
                ? child
                : ScaleTransition(
                    scale: Tween(begin: 0.9, end: 1.0).animate(animation),
                    child: child,
                  ),
          ),
          child: widget.loading
              ? RepaintBoundary(
                  key: const ValueKey('loading'),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.onAccent,
                      semanticsLabel: widget.loadingLabel,
                    ),
                  ),
                )
              : Text(widget.label,
                  key: const ValueKey('label'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
        ),
      ),
    ));
  }
}

@immutable
class _ButtonLook {
  const _ButtonLook(this.fill, this.label);

  final Color fill, label;

  @override
  bool operator ==(Object other) =>
      other is _ButtonLook && other.fill == fill && other.label == label;

  @override
  int get hashCode => Object.hash(fill, label);
}

class _ButtonLookTween extends Tween<_ButtonLook> {
  _ButtonLookTween({required _ButtonLook end}) : super(end: end);

  @override
  _ButtonLook lerp(double t) => _ButtonLook(
        Color.lerp(begin!.fill, end!.fill, t)!,
        Color.lerp(begin!.label, end!.label, t)!,
      );
}

/// A plain accent-coloured text action. Pressing dims it to 50 %, and on
/// desktop an underline fades in on hover.
class AuthLink extends StatefulWidget {
  const AuthLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<AuthLink> createState() => _AuthLinkState();
}

class _AuthLinkState extends State<AuthLink> {
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  void _onStates() => _afterBuild(this, () {});

  @override
  void dispose() {
    _states.removeListener(_onStates);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AuthTokens.of(context);
    final pressed = _states.value.contains(WidgetState.pressed);
    final hovered = _states.value.contains(WidgetState.hovered);
    return TextButton(
      statesController: _states,
      onPressed: widget.onPressed,
      child: AnimatedOpacity(
        opacity: pressed ? 0.5 : 1,
        duration: AuthMotion.fade(context,
            pressed ? AuthMotion.press : const Duration(milliseconds: 200)),
        curve: AuthMotion.standard,
        child: TweenAnimationBuilder<Color?>(
          tween:
              ColorTween(end: hovered ? t.link : t.link.withValues(alpha: 0)),
          duration: AuthMotion.fade(context, AuthMotion.instant),
          curve: AuthMotion.standard,
          builder: (context, underline, _) => Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: underline),
          ),
        ),
      ),
    );
  }
}

/// A row-sized tap target with a quiet state layer instead of an ink ripple:
/// the background fades in over 100 ms on hover, press and keyboard focus.
class AuthPressable extends StatefulWidget {
  const AuthPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.focusable = true,
    this.highlighted = false,
    this.outset = 0,
    this.borderRadius = BorderRadius.zero,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// How far the highlight reaches beyond the row horizontally, so content
  /// can stay aligned with the fields while the highlight has some air.
  final double outset;
  final BorderRadius borderRadius;

  /// Whether the row takes part in keyboard focus. Rows whose control
  /// (e.g. a switch) is focusable itself, or options of a text field, opt out.
  final bool focusable;

  /// An externally driven highlight, e.g. the autocomplete's current option.
  final bool highlighted;

  @override
  State<AuthPressable> createState() => _AuthPressableState();
}

class _AuthPressableState extends State<AuthPressable> {
  bool _hovered = false, _pressed = false, _focused = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AuthTokens.of(context);
    final enabled = widget.onTap != null;
    final color = !enabled
        ? Colors.transparent
        : _pressed
            ? t.primaryText.withValues(alpha: 0.08)
            : _focused || widget.highlighted
                ? t.accent.withValues(alpha: 0.12)
                : _hovered
                    ? t.primaryText.withValues(alpha: 0.04)
                    : t.primaryText.withValues(alpha: 0);
    final cursor = enabled ? SystemMouseCursors.click : MouseCursor.defer;
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _press(true) : null,
      onTapUp: enabled ? (_) => _press(false) : null,
      onTapCancel: enabled ? () => _press(false) : null,
      onTap: widget.onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: AuthMotion.fade(context, AuthMotion.press),
        curve: AuthMotion.standard,
        builder: (context, color, child) => CustomPaint(
          painter: _HighlightPainter(
              color: color!,
              outset: widget.outset,
              borderRadius: widget.borderRadius),
          child: child,
        ),
        child: widget.child,
      ),
    );
    if (!widget.focusable) {
      return MouseRegion(
        cursor: cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: body,
      );
    }
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: cursor,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap?.call();
          return null;
        }),
      },
      child: Semantics(button: true, child: body),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  const _HighlightPainter({
    required this.color,
    required this.outset,
    required this.borderRadius,
  });

  final Color color;
  final double outset;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final rect = Rect.fromLTRB(-outset, 0, size.width + outset, size.height);
    canvas.drawRRect(borderRadius.toRRect(rect), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.color != color ||
      old.outset != outset ||
      old.borderRadius != borderRadius;
}

/// Applies [update] to [state] now, or after the current frame when a
/// button reports its states while it is itself being built (e.g. when it
/// becomes disabled).
void _afterBuild(State state, VoidCallback update) {
  void apply() {
    // ignore: invalid_use_of_protected_member
    if (state.mounted) state.setState(update);
  }

  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    SchedulerBinding.instance.addPostFrameCallback((_) => apply());
  } else {
    apply();
  }
}
