import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:flutter/material.dart';

/// Opens the notification center and shows how many are unread.
class ServerNotificationBell extends StatelessWidget {
  const ServerNotificationBell({
    super.key,
    this.repository,
    this.enabled,
    this.onPressed,
    this.hideWhenEmpty = false,
    this.style,
    this.iconSize,
    this.schoolUnread,
  });

  final ServerNotificationRepository? repository;
  final bool? enabled;
  final VoidCallback? onPressed;

  /// Takes no room while there is nothing to open, for screens that are not
  /// about notifications.
  final bool hideWhenEmpty;

  /// For bars whose buttons look different from a plain icon button.
  final ButtonStyle? style;
  final double? iconSize;

  /// The unread notifications of the school, for a bell that covers them too.
  final int? schoolUnread;

  @override
  Widget build(BuildContext context) {
    final school = schoolUnread;
    if (!(enabled ?? serverNotifications.enabled) && (school ?? 0) == 0) {
      return const SizedBox.shrink();
    }
    final source = repository ?? serverNotifications.repository;
    return AnimatedBuilder(
      animation: source,
      builder: (context, _) {
        if (hideWhenEmpty && source.notifications.isEmpty) {
          return const SizedBox.shrink();
        }
        final l10n = context.l10n;
        final unread = source.unreadCount + (school ?? 0);
        final title = school == null
            ? l10n.text('appNotifications.title')
            : l10n.text('notifications.title');
        final unreadKey = school == null
            ? 'appNotifications.bellUnread'
            : 'notifications.bellUnread';
        return IconButton(
          key: const Key('server-notification-bell'),
          style: style,
          iconSize: iconSize,
          tooltip: unread == 0
              ? title
              : l10n.text(unreadKey, args: {'count': '$unread'}),
          onPressed: onPressed ??
              () => showServerNotificationCenter(Navigator.of(context),
                  repository: source),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(unread > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}

/// Places the bell on a page without an app bar, for signed-out users.
class ServerNotificationCornerBell extends StatelessWidget {
  const ServerNotificationCornerBell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          const PositionedDirectional(
            top: 0,
            end: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Material(
                  type: MaterialType.transparency,
                  child: ServerNotificationBell(hideWhenEmpty: true),
                ),
              ),
            ),
          ),
        ],
      );
}
