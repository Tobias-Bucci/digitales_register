import 'dart:async';

import 'package:dr/biometric_app_lock.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart' show navigatorKey;
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long an ordinary popup stays.
const serverNotificationPopupDuration = Duration(seconds: 6);

const _wideLayoutWidth = 600.0;
const _popupMaxWidth = 420.0;

/// Shows the popup for new notifications above the whole app, on any route.
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
  });

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
    _close();
    if (navigator == null) return;
    showServerNotificationCenter(
      navigator,
      repository: _repository,
      initialId: shown.length == 1 ? shown.single.id : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutWidth;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Align(
          alignment: wide ? AlignmentDirectional.topEnd : Alignment.topCenter,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: _shown.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      key: const Key('server-notification-popup'),
                      padding: const EdgeInsets.all(12),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _popupMaxWidth),
                        child: MouseRegion(
                          onEnter: (_) => _hold(true),
                          onExit: (_) => _hold(false),
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: _hold,
                            child: _Popup(
                              items: _shown,
                              primaryAction: _primaryAction,
                              onOpen: _open,
                              onClose: _close,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
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
    final heading = single != null
        ? (critical
            ? l10n.text('appNotifications.popupCritical')
            : l10n.text('appNotifications.popupNew'))
        : l10n.text('appNotifications.summary',
            args: {'count': '${items.length}'});
    return Semantics(
      container: true,
      liveRegion: true,
      label: single == null ? heading : '$heading: ${single.title}',
      child: Material(
        elevation: 6,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: critical
              ? BorderSide(color: scheme.error, width: 1.5)
              : BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
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
                      Text(
                        single.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
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
