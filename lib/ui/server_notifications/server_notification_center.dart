import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/server_notifications/server_notification_links.dart';
import 'package:dr/server_notifications/server_notification_models.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:dr/ui/server_notifications/server_notification_routes.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart';
import 'package:flutter/material.dart';

/// From this width on, list and detail are shown side by side.
const _twoPaneWidth = 840.0;
const _listPaneWidth = 380.0;
const _readableWidth = 720.0;

// These routes have no name on purpose: the navigator observer turns route
// names into screen events, and this feature sends none.
Route<void> _route(WidgetBuilder builder) =>
    MaterialPageRoute<void>(builder: builder);

/// Opens the center. [initialId] preselects a notification.
void showServerNotificationCenter(
  NavigatorState navigator, {
  ServerNotificationRepository? repository,
  String? initialId,
}) {
  unawaited(navigator.push(_route((_) => ServerNotificationCenterPage(
        repository: repository,
        initialId: initialId,
      ))));
}

/// Asks before the final step, then hides [id] on this device for good.
Future<bool> confirmServerNotificationDismissal(
  BuildContext context,
  ServerNotificationRepository repository,
  String id,
) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.text('appNotifications.dismissTitle')),
      content: Text(l10n.text('appNotifications.dismissBody')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.text('appNotifications.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.text('appNotifications.dismissConfirm')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await repository.dismiss(id);
  return true;
}

/// All active notifications, newest first.
class ServerNotificationCenterPage extends StatefulWidget {
  const ServerNotificationCenterPage({
    super.key,
    this.repository,
    this.onRefresh,
    this.openLink = openServerNotificationLink,
    this.initialId,
  });

  final ServerNotificationRepository? repository;
  final VoidCallback? onRefresh;
  final ServerNotificationLinkOpener openLink;
  final String? initialId;

  @override
  State<ServerNotificationCenterPage> createState() =>
      _ServerNotificationCenterPageState();
}

class _ServerNotificationCenterPageState
    extends State<ServerNotificationCenterPage> {
  late final ServerNotificationRepository _repository =
      widget.repository ?? serverNotifications.repository;
  late String? _selectedId = widget.initialId;
  bool _openedInitial = false;

  void _refresh() => (widget.onRefresh ?? serverNotifications.refresh)();

  void _open(String id, {required bool twoPanes}) {
    if (twoPanes) {
      setState(() => _selectedId = id);
      return;
    }
    unawaited(Navigator.of(context).push(_route((_) =>
        ServerNotificationDetailPage(
            id: id, repository: _repository, openLink: widget.openLink))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('appNotifications.title')),
        actions: [
          IconButton(
            tooltip: l10n.text('appNotifications.refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _repository,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final twoPanes = constraints.maxWidth >= _twoPaneWidth;
            if (!twoPanes && !_openedInitial && widget.initialId != null) {
              _openedInitial = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _open(widget.initialId!, twoPanes: false);
              });
            }
            final list = _NotificationList(
              repository: _repository,
              selectedId: twoPanes ? _selectedId : null,
              onOpen: (id) => _open(id, twoPanes: twoPanes),
              onRefresh: _refresh,
            );
            if (!twoPanes) return list;
            final selectedId = _selectedId;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: _listPaneWidth, child: list),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selectedId == null
                      ? _Placeholder(
                          icon: Icons.mark_email_read_outlined,
                          title: l10n.text('appNotifications.select'),
                        )
                      : ServerNotificationDetailView(
                          key: ValueKey(selectedId),
                          id: selectedId,
                          repository: _repository,
                          openLink: widget.openLink,
                          onDismissed: () => setState(() => _selectedId = null),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.repository,
    required this.selectedId,
    required this.onOpen,
    required this.onRefresh,
  });

  final ServerNotificationRepository repository;
  final String? selectedId;
  final ValueChanged<String> onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = repository.notifications;
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readableWidth),
          child: ListView(
            key: const Key('server-notification-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (repository.lastSyncFailed) const _StaleNotice(),
              if (items.isEmpty)
                _Placeholder(
                  icon: Icons.notifications_none_rounded,
                  title: l10n.text('appNotifications.emptyTitle'),
                  body: l10n.text('appNotifications.emptyBody'),
                )
              else
                for (final item in items)
                  _NotificationTile(
                    key: ValueKey(item.id),
                    item: item,
                    unread: repository.isUnread(item),
                    selected: item.id == selectedId,
                    onTap: () => onOpen(item.id),
                    onDismiss: () => unawaited(
                        confirmServerNotificationDismissal(
                            context, repository, item.id)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.cloud_off_outlined,
                size: 20, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(context.l10n.text('appNotifications.stale'),
                style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.item,
    required this.unread,
    required this.selected,
    required this.onTap,
    required this.onDismiss,
  });

  final ServerNotification item;
  final bool unread;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final time = formatServerNotificationTime(context, item.publishedAt);
    final status = unread ? l10n.text('appNotifications.unread') : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.secondaryContainer : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: [
                if (status != null) status,
                item.type.label,
                item.title,
                time,
              ].join(', '),
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ServerNotificationTypeIcon(type: item.type),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (unread) ...[
                                  Container(
                                    key: const Key(
                                        'server-notification-unread-dot'),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    item.type.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              time,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
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
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: IconButton(
              tooltip: l10n.text('appNotifications.dismiss'),
              iconSize: 20,
              color: scheme.onSurfaceVariant,
              icon: const Icon(Icons.visibility_off_outlined),
              onPressed: onDismiss,
            ),
          ),
        ],
      ),
    );
  }
}

/// One notification on its own page.
class ServerNotificationDetailPage extends StatelessWidget {
  const ServerNotificationDetailPage({
    super.key,
    required this.id,
    required this.repository,
    this.openLink = openServerNotificationLink,
  });

  final String id;
  final ServerNotificationRepository repository;
  final ServerNotificationLinkOpener openLink;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text(context.l10n.text('appNotifications.title'))),
        body: ServerNotificationDetailView(
          id: id,
          repository: repository,
          openLink: openLink,
          onDismissed: () => Navigator.of(context).maybePop(),
        ),
      );
}

/// The full text of one notification. Showing it is what marks it read.
class ServerNotificationDetailView extends StatefulWidget {
  const ServerNotificationDetailView({
    super.key,
    required this.id,
    required this.repository,
    required this.openLink,
    required this.onDismissed,
  });

  final String id;
  final ServerNotificationRepository repository;
  final ServerNotificationLinkOpener openLink;
  final VoidCallback onDismissed;

  @override
  State<ServerNotificationDetailView> createState() =>
      _ServerNotificationDetailViewState();
}

class _ServerNotificationDetailViewState
    extends State<ServerNotificationDetailView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.repository.markRead(widget.id));
    });
  }

  Future<void> _openLink(ServerNotificationLink link) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await widget.openLink(link);
    final message = switch (result) {
      ServerNotificationLinkResult.opened => null,
      ServerNotificationLinkResult.needsLogin =>
        l10n.text('appNotifications.linkNeedsLogin'),
      ServerNotificationLinkResult.failed =>
        l10n.text('appNotifications.linkFailed'),
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _dismiss() async {
    final dismissed = await confirmServerNotificationDismissal(
        context, widget.repository, widget.id);
    if (dismissed && mounted) widget.onDismissed();
  }

  Widget _linkButton(BuildContext context, ServerNotificationLink link) {
    final l10n = context.l10n;
    return switch (link) {
      InternalNotificationLink() => FilledButton.tonalIcon(
          onPressed: () => unawaited(_openLink(link)),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l10n.text('appNotifications.openInApp')),
        ),
      // The address is shown, so nobody opens it blindly.
      ExternalNotificationLink(:final uri) => FilledButton.tonalIcon(
          onPressed: () => unawaited(_openLink(link)),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(l10n
              .text('appNotifications.openExternal', args: {'host': uri.host})),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final item = widget.repository.byId(widget.id);
        if (item == null) {
          return _Placeholder(
            icon: Icons.notifications_off_outlined,
            title: context.l10n.text('appNotifications.gone'),
          );
        }
        final theme = Theme.of(context);
        final l10n = context.l10n;
        final muted = theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
        final link = item.link;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _readableWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Row(
                  children: [
                    ServerNotificationTypeIcon(type: item.type, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item.type.label,
                          style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: SelectableText(item.title,
                      style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.text('appNotifications.published', args: {
                    'date':
                        formatServerNotificationTime(context, item.publishedAt)
                  }),
                  style: muted,
                ),
                if (item.expiresAt != null)
                  Text(
                    l10n.text('appNotifications.expires', args: {
                      'date':
                          formatServerNotificationTime(context, item.expiresAt!)
                    }),
                    style: muted,
                  ),
                const SizedBox(height: 20),
                // Plain text by contract: never parsed, whatever it contains.
                SelectableText(item.body, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (link != null) _linkButton(context, link),
                    TextButton.icon(
                      onPressed: () => unawaited(_dismiss()),
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: Text(l10n.text('appNotifications.dismiss')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
