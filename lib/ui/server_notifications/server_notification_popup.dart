import 'dart:async';
import 'dart:math' as math;

import 'package:dr/biometric_app_lock.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show navigatorKey;
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart'
    show showNotificationCenterInShell;
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long an ordinary popup stays.
const serverNotificationPopupDuration = Duration(seconds: 6);

const _wideLayoutWidth = 600.0;
const _popupMaxWidth = 420.0;

/// The share of the window the popup may take at most, whatever the text size.
const _popupMaxHeightFactor = 0.4;

/// The space between the header and the popup.
const _headerGap = 8.0;

/// Room for the close button even when the keyboard leaves almost nothing.
const _minPopupHeight = kMinInteractiveDimension + 16;

/// The space below the status bar for pages whose header does not report
/// itself: a toolbar of the [AppBar]s of the older pages, and on the sign-in
/// page the corner bell, which is as tall.
const _unreportedHeaderHeight = kToolbarHeight;

/// The page headers on screen now, see [ServerNotificationPopupClearance].
final Set<_PopupClearanceState> _headers = {};

/// Marks a page header, so that the popup for new app announcements appears
/// right below it instead of covering it, the school name or the bell.
///
/// The host of the popup sits above the navigator and cannot see the pages, so
/// the headers report themselves. Pages that another one covers do not count.
/// Without any header on screen the popup leaves room for a toolbar.
class ServerNotificationPopupClearance extends StatefulWidget {
  const ServerNotificationPopupClearance({super.key, required this.child});

  final Widget child;

  @override
  State<ServerNotificationPopupClearance> createState() =>
      _PopupClearanceState();
}

class _PopupClearanceState extends State<ServerNotificationPopupClearance> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The navigator keeps covered pages offstage, with their tickers off.
    if (TickerMode.valuesOf(context).enabled) {
      _headers.add(this);
    } else {
      _headers.remove(this);
    }
  }

  @override
  void dispose() {
    _headers.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows the popup for new notifications above the whole app, on any route.
///
/// It appears at the top, right below the header of the page, where system
/// banners appear too and next to the bell that keeps the notification. Narrow
/// windows show it across the width, wide ones in the top end corner.
///
/// It sits next to the navigator, not on top of it: the app below stays fully
/// usable. Closing it changes nothing about the notifications: they stay
/// unread in the center. Sits below the app lock, so that a locked app shows
/// no content, and waits for the unlock instead of timing out unseen.
class ServerNotificationHost extends StatefulWidget {
  const ServerNotificationHost({
    super.key,
    required this.child,
    this.repository,
    this.navigator,
    this.duration = serverNotificationPopupDuration,
    this.isBlocked,
    this.blockedChanges,
    this.onLanguage,
    this.newDesign = false,
    this.openInShell = showNotificationCenterInShell,
  });

  /// Glass, in the look of the new dashboard.
  final bool newDesign;

  /// Opens the center inside the shell of the new design, focused on the
  /// given notification, as the bell does. False where there is no shell;
  /// [navigator] then gets the center, as in Legacy and while signed out.
  final bool Function({String? initialId}) openInShell;

  final Widget child;
  final ServerNotificationRepository? repository;
  final NavigatorState? Function()? navigator;
  final Duration duration;

  /// Whether a popup must wait. Defaults to the app lock.
  final bool Function()? isBlocked;
  final Listenable? blockedChanges;
  final ValueChanged<String>? onLanguage;

  @override
  State<ServerNotificationHost> createState() => _ServerNotificationHostState();
}

class _ServerNotificationHostState extends State<ServerNotificationHost> {
  late final ServerNotificationRepository _repository =
      widget.repository ?? serverNotifications.repository;
  late final Listenable _blockedChanges =
      widget.blockedChanges ?? biometricAppLockController;
  final FocusNode _primaryAction =
      FocusNode(debugLabel: 'server notification popup');
  List<ServerNotification> _shown = const [];
  Timer? _timer;
  bool _held = false;

  bool get _blocked =>
      (widget.isBlocked ?? () => biometricAppLockController.isLocked)();

  NavigatorState? get _navigator =>
      (widget.navigator ?? () => navigatorKey?.currentState)();

  @override
  void initState() {
    super.initState();
    _repository.addListener(_update);
    _blockedChanges.addListener(_update);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language =
        AppLanguage.fromLocale(Localizations.localeOf(context)).code;
    (widget.onLanguage ?? serverNotifications.setLanguage)(language);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _repository.removeListener(_update);
    _blockedChanges.removeListener(_update);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _primaryAction.dispose();
    super.dispose();
  }

  /// Escape closes the popup. The popup does not take the focus by itself, as
  /// that would interrupt typing, so F6 moves the keyboard into it.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _shown.isEmpty) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      _primaryAction.requestFocus();
      return true;
    }
    return false;
  }

  void _update() {
    if (!mounted) return;
    // Opened, dismissed, expired or revoked in the meantime: nothing to say.
    final current = {
      for (final item in _repository.notifications)
        if (_repository.isUnread(item)) item.id: item,
    };
    final shown = [
      for (final item in _shown)
        if (current[item.id] != null) current[item.id]!,
    ];
    final added = _blocked ? const <ServerNotification>[] : _pendingAlerts();
    final changed = added.isNotEmpty || shown.length != _shown.length;
    if (changed) {
      setState(() {
        _shown = [
          ...shown,
          ...added.where((item) => !shown.any((old) => old.id == item.id)),
        ];
      });
      _restartTimer();
    }
    if (added.isNotEmpty) unawaited(_repository.markAlerted(added));
  }

  List<ServerNotification> _pendingAlerts() => _repository.pendingAlerts;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    final critical = _shown.any((item) => item.type.critical);
    if (_shown.isEmpty || critical || _held) return;
    _timer = Timer(widget.duration, _close);
  }

  void _hold(bool held) {
    if (held == _held) return;
    _held = held;
    _restartTimer();
  }

  void _close() {
    _timer?.cancel();
    _timer = null;
    _held = false;
    if (mounted && _shown.isNotEmpty) setState(() => _shown = const []);
  }

  void _open() {
    final navigator = _navigator;
    final shown = _shown;
    final initialId = shown.length == 1 ? shown.single.id : null;
    _close();
    if (widget.newDesign && widget.openInShell(initialId: initialId)) return;
    if (navigator == null) return;
    showServerNotificationCenter(
      navigator,
      repository: _repository,
      initialId: initialId,
    );
  }

  /// Where the lowest header on screen ends, in the host's coordinates, or null
  /// without one. Reads the layout of the last frame.
  double? _measureHeaders() {
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.hasSize) return null;
    double? bottom;
    for (final header in _headers) {
      if (!header.mounted) continue;
      final box = header.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = MatrixUtils.transformRect(
          box.getTransformTo(host), Offset.zero & box.size);
      if (bottom == null || rect.bottom > bottom) bottom = rect.bottom;
    }
    return bottom;
  }

  bool _following = false;

  /// While the popup shows, follows the header after every frame: the strip
  /// for new entries comes and goes, and pages change. Costs nothing while
  /// nothing draws, as it schedules no frame of its own.
  void _followHeaders(double? measured) {
    if (_following) return;
    _following = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _following = false;
      if (!mounted || _shown.isEmpty) return;
      final now = _measureHeaders();
      if (now != measured) {
        setState(() {});
      } else {
        _followHeaders(measured);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutWidth;
    final glass = widget.newDesign;
    final statusBar = MediaQuery.paddingOf(context).top;
    final measured = _shown.isEmpty ? null : _measureHeaders();
    if (_shown.isNotEmpty) _followHeaders(measured);
    final headerBottom = measured ?? statusBar + _unreportedHeaderHeight;
    final top = math.max(headerBottom, statusBar) + _headerGap;
    // The keyboard does not move it, but takes away room from a short window.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final side = glass ? DesignTokens.gutter : 12.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxHeight - top - keyboard - _headerGap;
            final cap =
                MediaQuery.sizeOf(context).height * _popupMaxHeightFactor;
            // Its content scrolls in what is left, but keeps a row of controls.
            final maxHeight = math.max(_minPopupHeight, math.min(room, cap));
            return Padding(
              padding: EdgeInsets.fromLTRB(side, top, side, 0),
              child: Align(
                alignment:
                    wide ? AlignmentDirectional.topEnd : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _popupMaxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: _transition(reducedMotion, glass),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _transition(bool reducedMotion, bool glass) => AnimatedSwitcher(
        duration:
            reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
        // Comes down from above, as banners of the system do.
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -0.2),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        child: _shown.isEmpty
            ? const SizedBox.shrink()
            : _SwipeUpToDismiss(
                key: const Key('server-notification-popup'),
                onDismiss: _close,
                child: MouseRegion(
                  onEnter: (_) => _hold(true),
                  onExit: (_) => _hold(false),
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: _hold,
                    child: glass
                        ? _GlassPopup(
                            items: _shown,
                            primaryAction: _primaryAction,
                            onOpen: _open,
                            onClose: _close,
                          )
                        : _Popup(
                            items: _shown,
                            primaryAction: _primaryAction,
                            onOpen: _open,
                            onClose: _close,
                          ),
                  ),
                ),
              ),
      );
}

/// Swiping the popup up on a touch screen closes it, as the button does. A body
/// that scrolls takes the drag first, so it never fights the scrolling.
class _SwipeUpToDismiss extends StatefulWidget {
  const _SwipeUpToDismiss({
    super.key,
    required this.onDismiss,
    required this.child,
  });

  static const _distance = 32.0;
  static const _velocity = 300.0;

  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_SwipeUpToDismiss> createState() => _SwipeUpToDismissState();
}

class _SwipeUpToDismissState extends State<_SwipeUpToDismiss> {
  double _offset = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        // The close button is the way for screen readers.
        excludeFromSemantics: true,
        onVerticalDragUpdate: (details) {
          final offset = _offset + details.delta.dy;
          setState(() => _offset = offset < 0 ? offset : 0);
        },
        onVerticalDragEnd: (details) {
          if (_offset < -_SwipeUpToDismiss._distance ||
              (details.primaryVelocity ?? 0) < -_SwipeUpToDismiss._velocity) {
            widget.onDismiss();
          } else {
            setState(() => _offset = 0);
          }
        },
        onVerticalDragCancel: () => setState(() => _offset = 0),
        child: Transform.translate(
          offset: Offset(0, _offset),
          child: widget.child,
        ),
      );
}

String _heading(AppLocalizations l10n, List<ServerNotification> items) {
  final critical = items.any((item) => item.type.critical);
  if (items.length != 1) {
    return l10n
        .text('appNotifications.summary', args: {'count': '${items.length}'});
  }
  return l10n.text(critical
      ? 'appNotifications.popupCritical'
      : 'appNotifications.popupNew');
}

/// What the live region announces. The body is part of it, as the text that
/// scrolls in a short popup is a node of its own for screen readers.
String _announcement(String heading, ServerNotification? single) =>
    single == null ? heading : '$heading: ${single.title}\n${single.body}';

/// The popup in the look of the new dashboard: a card of glass with the
/// radius, rim and edge of the event banners, and controls of glass.
class _GlassPopup extends StatelessWidget {
  const _GlassPopup({
    required this.items,
    required this.primaryAction,
    required this.onOpen,
    required this.onClose,
  });

  static const _edgeWidth = 1.5;
  static const _discSize = 36.0;

  final List<ServerNotification> items;
  final FocusNode primaryAction;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final critical = items.any((item) => item.type.critical);
    final single = items.length == 1 ? items.single : null;
    final heading = _heading(l10n, items);
    final edge = critical
        ? scheme.error
        : highContrast
            ? scheme.outline
            : scheme.outline.withValues(alpha: dark ? 0.45 : 0.2);
    return Semantics(
      container: true,
      liveRegion: true,
      label: _announcement(heading, single),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: DesignTokens.cardBorderRadius,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: dark ? 0.5 : 0.16),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: GlassSurface(
          tint: scheme.surfaceContainerHigh,
          opacity: DesignTokens.sheetOpacity,
          borderRadius: DesignTokens.cardBorderRadius,
          rim: GlassRim.around,
          border: Border.all(
            color: edge,
            width: critical ? _edgeWidth : 1,
          ),
          child: Material(
            type: MaterialType.transparency,
            // Large text or a short window: the card keeps its maximum height
            // and its content scrolls.
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: critical ? scheme.error : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      // No tooltip: the popup is outside the navigator's
                      // overlay. The label keeps the button its own node.
                      IconButton(
                        key: const Key('server-notification-popup-close'),
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(_discSize),
                          minimumSize: const Size.square(_discSize),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.standard,
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ).merge(glassControlStyle(scheme,
                            shape: const CircleBorder())),
                        iconSize: 20,
                        icon: Icon(
                          Icons.close_rounded,
                          semanticLabel: l10n.text('appNotifications.close'),
                        ),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  if (single != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ServerNotificationTypeIcon(type: single.type),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                  child: Text(
                                    single.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                ExcludeSemantics(
                                  child: Text(
                                    single.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    key: const Key('server-notification-popup-open'),
                    focusNode: primaryAction,
                    onPressed: onOpen,
                    style: glassControlStyle(scheme).merge(
                      FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(l10n.text('appNotifications.open')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Popup extends StatelessWidget {
  const _Popup({
    required this.items,
    required this.primaryAction,
    required this.onOpen,
    required this.onClose,
  });

  final List<ServerNotification> items;
  final FocusNode primaryAction;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final critical = items.any((item) => item.type.critical);
    final single = items.length == 1 ? items.single : null;
    final heading = _heading(l10n, items);
    return Semantics(
      container: true,
      liveRegion: true,
      label: _announcement(heading, single),
      child: Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: critical
              ? BorderSide(color: scheme.error, width: 1.5)
              : BorderSide(color: scheme.outlineVariant),
        ),
        // Large text or a short window: the content scrolls.
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (single != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ServerNotificationTypeIcon(type: single.type),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ExcludeSemantics(
                        child: Text(
                          heading,
                          style: single == null
                              ? theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)
                              : theme.textTheme.labelMedium?.copyWith(
                                  color: critical
                                      ? scheme.error
                                      : scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    if (single != null) ...[
                      const SizedBox(height: 2),
                      ExcludeSemantics(
                        child: Text(
                          single.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 2),
                      ExcludeSemantics(
                        child: Text(
                          single.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: const Key('server-notification-popup-open'),
                        focusNode: primaryAction,
                        onPressed: onOpen,
                        style: TextButton.styleFrom(
                          // The primary color misses AA on this surface.
                          foregroundColor: scheme.onSurface,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(l10n.text('appNotifications.open')),
                      ),
                    ),
                  ],
                ),
              ),
              // No tooltip here: the popup is outside the navigator's overlay.
              // The label on the icon keeps the button its own semantics node,
              // with its tap action.
              IconButton(
                key: const Key('server-notification-popup-close'),
                icon: Icon(
                  Icons.close_rounded,
                  semanticLabel: l10n.text('appNotifications.close'),
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
