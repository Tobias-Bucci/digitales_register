part of 'server_notification_center.dart';

/// The space between two cards of the list.
const double _gap = 8;

/// Asks in a sheet of glass whether to hide a notification for good.
Future<bool?> _confirmDismissalInSheet(BuildContext context) {
  final l10n = context.l10n;
  return showGlassSheet<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return GlassPanel(
        title: l10n.text('appNotifications.dismissTitle'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.text('appNotifications.dismissBody'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  key: const Key('notification-dismiss-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.text('appNotifications.cancel')),
                ),
                FilledButton(
                  key: const Key('notification-dismiss-confirm'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.text('appNotifications.dismissConfirm')),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

extension _NewCenter on _ServerNotificationCenterPageState {
  Widget _buildNew(BuildContext context) {
    final l10n = context.l10n;
    final title = l10n.text(widget.school == null
        ? 'appNotifications.title'
        : 'notifications.title');
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPanes = constraints.maxWidth >= _twoPaneWidth;
        _openInitialPage(twoPanes: twoPanes);
        final floating =
            glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width);
        return GlassPage(
          header: GlassPageHeader(
            surfaceKey: const Key('notification-center-header'),
            title: title,
            // Above both panes, as wide as they are.
            floatingMaxWidth: floating == null
                ? null
                : twoPanes
                    ? DashboardColumns.maxWidth
                    : floating,
            actions: [
              HeaderDiscButton(
                tooltip: l10n.text('appNotifications.refresh'),
                icon: Icons.refresh_rounded,
                onPressed: _refresh,
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: _repository,
            builder: (context, _) => _newBody(
              context,
              twoPanes: twoPanes,
              title: title,
              width: constraints.maxWidth,
            ),
          ),
        );
      },
    );
  }

  Widget _newBody(
    BuildContext context, {
    required bool twoPanes,
    required String title,
    required double width,
  }) {
    final selectedSchool = _selectedSchool;
    final selectedId = _selectedId;
    final list = _NewNotificationList(
      repository: _repository,
      school: widget.school,
      selectedKey: !twoPanes
          ? null
          : selectedSchool != null
              ? _keyOfSchool(selectedSchool.id)
              : selectedId == null
                  ? null
                  : _keyOfApp(selectedId),
      onOpen: (entry) => _openEntry(entry, twoPanes: twoPanes),
      onRefresh: _refresh,
      onMarkAllRead: _markAllRead,
      filter: _filter,
      onFilterChanged: _setFilter,
    );
    if (!twoPanes) return list;
    final Widget detail = selectedSchool != null
        ? SchoolNotificationDetailView(
            key: ValueKey(_keyOfSchool(selectedSchool.id)),
            notification: selectedSchool,
            onShown: _markSchoolRead,
          )
        : selectedId == null
            ? GlassStateCard(
                icon: Icons.mark_email_read_outlined,
                title: title,
                body: context.l10n.text('appNotifications.select'),
              )
            : ServerNotificationDetailView(
                key: ValueKey(selectedId),
                id: selectedId,
                repository: _repository,
                openLink: widget.openLink,
                onDismissed: _clearSelection,
              );
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: math.min(width, DashboardColumns.maxWidth),
        height: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: _listPaneWidth, child: list),
            Expanded(
              child: KeyedSubtree(
                key: const Key('notification-center-detail-pane'),
                child: detail,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list of the new design: hints, the filter, then one card per entry,
/// built only as they come into view.
class _NewNotificationList extends StatelessWidget {
  const _NewNotificationList({
    required this.repository,
    required this.school,
    required this.selectedKey,
    required this.onOpen,
    required this.onRefresh,
    required this.onMarkAllRead,
    required this.filter,
    required this.onFilterChanged,
  });

  final ServerNotificationRepository repository;
  final SchoolNotificationFeed? school;
  final NotificationFilter filter;
  final ValueChanged<NotificationFilter> onFilterChanged;
  final String? selectedKey;
  final ValueChanged<NotificationFeedEntry> onOpen;
  final VoidCallback onRefresh;
  final VoidCallback? onMarkAllRead;

  Widget _tile(BuildContext context, NotificationFeedEntry entry) {
    final school = this.school;
    return switch (entry) {
      AppFeedEntry(notification: final item) => _NewAppTile(
          key: ValueKey(_keyOfApp(item.id)),
          item: item,
          showSource: school != null,
          unread: repository.isUnread(item),
          selected: _keyOfApp(item.id) == selectedKey,
          onTap: () => onOpen(entry),
          onDismiss: () => unawaited(
              confirmServerNotificationDismissal(context, repository, item.id)),
        ),
      SchoolFeedEntry(notification: final item) => _NewSchoolTile(
          key: ValueKey(_keyOfSchool(item.id)),
          item: item,
          noInternet: school!.noInternet,
          selected: _keyOfSchool(item.id) == selectedKey,
          onTap: () => onOpen(entry),
          onMarkRead: () => school.onMarkRead(item),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final school = this.school;
    final all = combinedNotificationFeed(
      school: school?.notifications ?? const [],
      app: repository.notifications,
    );
    // Types by key, in the order they first appear. Only with both sources.
    final types = <String, String>{
      if (school != null)
        for (final item in repository.notifications)
          item.type.key: serverNotificationTypeLabel(l10n, item.type),
    };
    final entries = school == null
        ? all
        : all
            .where((entry) => filter.matches(entry,
                isUnread: repository.isUnread,
                availableTypes: types.keys.toSet()))
            .toList();
    final stale = repository.lastSyncFailed;
    final top = MediaQuery.paddingOf(context).top;
    Widget refreshable(Widget child) => RefreshIndicator(
          edgeOffset: top,
          onRefresh: () async => onRefresh(),
          child: child,
        );

    // Only announcements, and none of them: the message is the page.
    if (school == null && all.isEmpty) {
      return refreshable(GlassStateCard(
        key: const Key('notification-center-empty'),
        icon:
            stale ? Icons.cloud_off_outlined : Icons.notifications_none_rounded,
        title: l10n.text('appNotifications.emptyTitle'),
        body: l10n.text(
            stale ? 'appNotifications.stale' : 'appNotifications.emptyBody'),
        actionLabel: stale ? l10n.text('common.retry') : null,
        onAction: stale ? onRefresh : null,
      ));
    }

    final lastFetched = school?.lastFetched;
    final rows = <Widget>[
      if (stale)
        GlassOfflineHint(
          key: const Key('notification-center-stale'),
          message: l10n.text('appNotifications.stale'),
          onRetry: onRefresh,
        ),
      if (school != null && school.noInternet && lastFetched != null)
        GlassOfflineHint(
          key: const Key('notification-center-offline'),
          message: l10n.text('grades.offlineMode',
              args: {'time': l10n.formatTimeAgo(lastFetched)}),
          onRetry: onRefresh,
        ),
      if (school != null)
        _NewFilterBar(
          filter: filter,
          types: types,
          onChanged: onFilterChanged,
          // With the chips, so that it takes no row of its own.
          markAllRead:
              school.notifications.isNotEmpty || repository.unreadCount > 0
                  ? TextButton.icon(
                      onPressed: onMarkAllRead,
                      icon: const Icon(Icons.done_all),
                      label: Text(l10n.text('notifications.markAllRead')),
                    )
                  : null,
        ),
      if (entries.isEmpty && all.isNotEmpty)
        _InlineState(
          child: GlassStateCard(
            key: const Key('notification-center-filter-empty'),
            icon: Icons.filter_alt_off_outlined,
            title: l10n.text('notifications.filter.emptyTitle'),
            body: l10n.text('notifications.filter.emptyBody'),
            actionLabel: l10n.text('notifications.filter.reset'),
            actionIcon: Icons.filter_alt_off_outlined,
            onAction: () => onFilterChanged(const NotificationFilter()),
          ),
        )
      else if (entries.isEmpty)
        _InlineState(
          child: GlassStateCard(
            key: const Key('notification-center-empty'),
            icon: Icons.notifications_none_rounded,
            title: l10n.text('notifications.none'),
            body: '',
          ),
        ),
    ];
    final count = rows.length + entries.length;
    return refreshable(GlassListBody.builder(
      listKey: const Key('server-notification-list'),
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: index == count - 1 ? 0 : _gap),
        child: index < rows.length
            ? rows[index]
            : _tile(context, entries[index - rows.length]),
      ),
    ));
  }
}

/// A [GlassStateCard] among the rows of a list, which brings the gaps.
class _InlineState extends StatelessWidget {
  const _InlineState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: child,
        ),
      );
}

/// Source, type and read state, at a glance above the list.
class _NewFilterBar extends StatelessWidget {
  const _NewFilterBar({
    required this.filter,
    required this.types,
    required this.onChanged,
    required this.markAllRead,
  });

  final NotificationFilter filter;

  /// The announcement types of the current list, by key.
  final Map<String, String> types;
  final ValueChanged<NotificationFilter> onChanged;

  /// The button that marks everything read, after the chips.
  final Widget? markAllRead;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = types.containsKey(filter.appType) ? filter.appType : null;
    final markAllRead = this.markAllRead;
    GlassSegment<NotificationSourceFilter> segment(
      NotificationSourceFilter value,
      String key,
    ) {
      final label = l10n.text(key);
      return GlassSegment(value: value, label: label, fullLabel: label);
    }

    return Semantics(
      container: true,
      label: l10n.text('notifications.filter.label'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: GlassSegmentedControl<NotificationSourceFilter>(
                key: const Key('notification-filter-source'),
                segments: [
                  segment(
                      NotificationSourceFilter.all, 'notifications.filter.all'),
                  segment(NotificationSourceFilter.school,
                      'notifications.sourceSchool'),
                  segment(
                      NotificationSourceFilter.app, 'notifications.sourceApp'),
                ],
                selected: filter.source,
                onChanged: (source) => onChanged(filter.copyWith(
                  source: source,
                  // A type only means something for announcements.
                  appType: source == NotificationSourceFilter.app
                      ? null
                      : () => null,
                )),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _GlassChipTheme(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  key: const Key('notification-filter-unread'),
                  label: Text(l10n.text('notifications.filter.unread')),
                  selected: filter.unreadOnly,
                  onSelected: (value) =>
                      onChanged(filter.copyWith(unreadOnly: value)),
                  mouseCursor: NewDesignTheme.clickCursor,
                ),
                if (filter.source == NotificationSourceFilter.app &&
                    types.length > 1)
                  for (final entry in types.entries)
                    ChoiceChip(
                      key: ValueKey('notification-filter-type-${entry.key}'),
                      label: Text(entry.value),
                      selected: type == entry.key,
                      onSelected: (selected) => onChanged(filter.copyWith(
                          appType: () => selected ? entry.key : null)),
                      mouseCursor: NewDesignTheme.clickCursor,
                    ),
                if (filter.isActive)
                  TextButton.icon(
                    key: const Key('notification-filter-reset'),
                    onPressed: () => onChanged(const NotificationFilter()),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: Text(l10n.text('notifications.filter.reset')),
                  ),
                if (markAllRead != null) markAllRead,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chips of the filter on glass: light like the cards, the choice in the
/// tone of the other controls, opaque with an outline in high contrast.
class _GlassChipTheme extends StatelessWidget {
  const _GlassChipTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return ChipTheme(
      data: theme.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(
          color: highContrast
              ? scheme.outline
              : scheme.outline.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.45 : 0.2,
                ),
        ),
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLowest.withValues(
                  alpha: highContrast ? 1 : DesignTokens.cardOpacity,
                ),
        ),
        checkmarkColor: scheme.onSecondaryContainer,
        labelStyle: theme.textTheme.labelLarge,
      ),
      child: child,
    );
  }
}

/// One entry on a card: what it is, what it says and when it came, with its
/// action at the end.
class _NewFeedTile extends StatelessWidget {
  const _NewFeedTile({
    required this.leading,
    required this.label,
    required this.title,
    required this.body,
    required this.time,
    required this.unread,
    required this.selected,
    required this.onTap,
    required this.action,
  });

  static const _shape = RoundedRectangleBorder(
    borderRadius: DesignTokens.cardBorderRadius,
  );

  final Widget leading;
  final String label;
  final String title;
  final String? body;
  final String time;
  final bool unread;
  final bool selected;
  final VoidCallback onTap;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final status = unread ? context.l10n.text('appNotifications.unread') : null;
    final body = this.body;
    final card = GlassCard(
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: [
                if (status != null) status,
                label,
                title,
                time,
              ].join(', '),
              excludeSemantics: true,
              child: InkWell(
                customBorder: _shape,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                mouseCursor: NewDesignTheme.clickCursor,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 4, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leading,
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
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: muted),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            if (body != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted, height: 1.35),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              time,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted),
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
            padding: const EdgeInsetsDirectional.only(top: 2, end: 2),
            child: action,
          ),
        ],
      ),
    );
    return GlassFocusRing(
      shape: _shape,
      activeTint: scheme.onSurface.withValues(alpha: 0.05),
      child: Material(
        type: MaterialType.transparency,
        child: selected
            ? DecoratedBox(
                key: const Key('server-notification-selected'),
                position: DecorationPosition.foreground,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: DesignTokens.cardBorderRadius,
                    side: BorderSide(color: scheme.primary, width: 2),
                  ),
                ),
                child: card,
              )
            : card,
      ),
    );
  }
}

class _NewAppTile extends StatelessWidget {
  const _NewAppTile({
    super.key,
    required this.item,
    required this.showSource,
    required this.unread,
    required this.selected,
    required this.onTap,
    required this.onDismiss,
  });

  final ServerNotification item;
  final bool showSource;
  final bool unread;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = serverNotificationTypeLabel(l10n, item.type);
    return _NewFeedTile(
      leading: ServerNotificationTypeIcon(type: item.type),
      label:
          showSource ? '${l10n.text('notifications.sourceApp')} · $type' : type,
      title: item.title,
      body: item.body,
      time: formatServerNotificationTime(context, item.publishedAt),
      unread: unread,
      selected: selected,
      onTap: onTap,
      action: IconButton(
        tooltip: l10n.text('appNotifications.dismiss'),
        iconSize: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        icon: const Icon(Icons.visibility_off_outlined),
        onPressed: onDismiss,
      ),
    );
  }
}

class _NewSchoolTile extends StatelessWidget {
  const _NewSchoolTile({
    super.key,
    required this.item,
    required this.noInternet,
    required this.selected,
    required this.onTap,
    required this.onMarkRead,
  });

  final Notification item;
  final bool noInternet;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subTitle = item.subTitle;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return _NewFeedTile(
      leading: const SchoolNotificationIcon(),
      label: l10n.text('notifications.sourceSchool'),
      title: item.title,
      body: subTitle == null || subTitle.isEmpty ? null : subTitle,
      time: formatSchoolNotificationTime(context, item.timeSent),
      unread: true,
      selected: selected,
      onTap: onTap,
      action: _opensMessage(item)
          ? IconButton(
              tooltip: l10n.text('notifications.openMessages'),
              iconSize: 20,
              color: color,
              icon: const Icon(Icons.exit_to_app),
              onPressed: onTap,
            )
          : IconButton(
              tooltip: l10n.text('notifications.markRead'),
              iconSize: 20,
              color: color,
              icon: const Icon(Icons.done),
              onPressed: noInternet ? null : onMarkRead,
            ),
    );
  }
}

/// A notification on its own page, on phones: the glass header with its back
/// button above the detail.
class _NewDetailPage extends StatelessWidget {
  const _NewDetailPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('notification-detail-header'),
          title: title,
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        ),
        body: child,
      );
}

/// The full text of an entry on a card, below the header and above the
/// navigation bar, on a page or in the pane beside the list.
class _NewDetailFrame extends StatelessWidget {
  const _NewDetailFrame({
    required this.icon,
    required this.source,
    required this.title,
    required this.children,
  });

  final Widget icon;
  final String source, title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    return ReadableContent(
      maxWidth: DesignTokens.contentMaxWidth,
      child: ListView(
        key: const Key('notification-detail-list'),
        padding: EdgeInsets.fromLTRB(
          DesignTokens.gutter,
          padding.top + 8,
          DesignTokens.gutter,
          padding.bottom + DesignTokens.gutter,
        ),
        children: [
          GlassCard(
            key: const Key('notification-detail'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        source,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: SelectableText(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _NewAppDetail on _ServerNotificationDetailViewState {
  Widget _buildNew(BuildContext context) => AnimatedBuilder(
        animation: widget.repository,
        builder: (context, _) {
          final l10n = context.l10n;
          final item = widget.repository.byId(widget.id);
          if (item == null) {
            return GlassStateCard(
              icon: Icons.notifications_off_outlined,
              title: l10n.text('appNotifications.title'),
              body: l10n.text('appNotifications.gone'),
            );
          }
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final muted = theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant);
          final link = item.link;
          return _NewDetailFrame(
            icon: ServerNotificationTypeIcon(type: item.type, size: 36),
            source: serverNotificationTypeLabel(l10n, item.type),
            title: item.title,
            children: [
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
              const SizedBox(height: 16),
              // Plain text by contract: never parsed, whatever it contains.
              SelectableText(
                item.body,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (link != null)
                    FilledButton.icon(
                      style: glassControlStyle(scheme),
                      onPressed: () => unawaited(_openLink(link)),
                      icon: Icon(switch (link) {
                        InternalNotificationLink() =>
                          Icons.arrow_forward_rounded,
                        ExternalNotificationLink() => Icons.open_in_new_rounded,
                      }),
                      label: Text(switch (link) {
                        InternalNotificationLink() =>
                          l10n.text('appNotifications.openInApp'),
                        // The address is shown, so nobody opens it blindly.
                        ExternalNotificationLink(:final uri) => l10n.text(
                            'appNotifications.openExternal',
                            args: {'host': uri.host}),
                      }),
                    ),
                  TextButton.icon(
                    onPressed: () => unawaited(_dismiss()),
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: Text(l10n.text('appNotifications.dismiss')),
                  ),
                ],
              ),
            ],
          );
        },
      );
}

class _NewSchoolDetail extends StatelessWidget {
  const _NewSchoolDetail({required this.notification});

  final Notification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final item = notification;
    final subTitle = item.subTitle;
    return _NewDetailFrame(
      icon: const SchoolNotificationIcon(size: 36),
      source: l10n.text('notifications.sourceSchool'),
      title: item.title,
      children: [
        Text(
          formatSchoolNotificationTime(context, item.timeSent),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (subTitle != null && subTitle.isNotEmpty) ...[
          const SizedBox(height: 16),
          LinkifiedText(
            subTitle,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        ],
      ],
    );
  }
}
