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

import 'package:dr/app_state.dart';
import 'package:dr/container/export_container.dart';
import 'package:dr/data.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/compact_day_list.dart' show compactRowHeight;
import 'package:dr/ui/dashboard_app_header.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_segmented_control.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

const _rowGap = 4.0;

/// A row in the list and the card it opens into, with the corners of the rows
/// of the grades page.
const _rowShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(compactRowHeight / 2)),
);

/// What a closed row is about as high as, to find a message that is not built
/// yet.
const _estimatedRowExtent = 60.0;

Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: milliseconds);

/// The keys of the folder names, in the order of the folders of
/// `MessagesPage`.
const messageFolderKeys = [
  'messages.incoming',
  'messages.outgoing',
  'messages.archived',
  'messages.all',
];

/// The messages page of the new design. Legacy keeps the view of
/// `MessagesPage`, which also keeps the folder and the open message for both.
class MessagesPageNew extends StatefulWidget {
  const MessagesPageNew({
    super.key,
    required this.state,
    required this.messages,
    required this.noInternet,
    required this.loading,
    required this.folder,
    required this.onFolderChanged,
    required this.expandedMessageId,
    required this.onExpansionChanged,
    required this.focusMessageId,
    required this.onOpenFile,
    required this.onMarkAsRead,
    required this.onArchive,
    required this.onReply,
    required this.onRetry,
  });

  final MessagesState? state;

  /// The messages of [folder].
  final List<Message> messages;
  final bool noInternet, loading;
  final int folder;
  final ValueChanged<int> onFolderChanged;
  final int? expandedMessageId;
  final void Function(Message message, bool expanded) onExpansionChanged;

  /// The message a link asked for, which is scrolled into view.
  final int? focusMessageId;
  final void Function(MessageAttachmentFile file) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final void Function(Message message) onArchive;
  final void Function(int messageId, String response) onReply;
  final VoidCallback? onRetry;

  @override
  State<MessagesPageNew> createState() => _MessagesPageNewState();
}

class _MessagesPageNewState extends State<MessagesPageNew> {
  final _controller = ScrollController();
  final Map<int, GlobalKey> _keys = {};

  /// The message the last link asked for, once it was scrolled into view.
  int? _revealed;

  GlobalKey _key(int id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(MessagesPageNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusMessageId != oldWidget.focusMessageId) _revealed = null;
    _scheduleReveal();
    _keys.removeWhere(
      (id, _) => !widget.messages.any((message) => message.id == id),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls to the message a link asked for, once it is in the list.
  void _scheduleReveal() {
    final id = widget.focusMessageId;
    if (id == null || id == _revealed) return;
    if (!widget.messages.any((message) => message.id == id)) return;
    _revealed = id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id, 0));
  }

  void _reveal(int id, int attempt) {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final context = _keys[id]?.currentContext;
    final object = context?.findRenderObject();
    if (context == null || object == null || !object.attached) {
      // Not built yet: a lazy list builds only what is in view. Jump to where
      // it should be, then look again.
      final index = widget.messages.indexWhere((message) => message.id == id);
      if (index < 0 || attempt > 6) return;
      position.jumpTo(
        (index * _estimatedRowExtent).clamp(0, position.maxScrollExtent),
      );
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _reveal(id, attempt + 1));
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;
    // Its top comes to rest right below the header.
    final top = MediaQuery.paddingOf(context).top + _rowGap;
    final target = (viewport.getOffsetToReveal(object, 0).offset - top)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final duration = _motion(context, 300);
    if (duration == Duration.zero) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final floatingMaxWidth =
        glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width);
    return GlassPage(
      loading: widget.loading || (widget.state == null && !widget.noInternet),
      header: GlassPageHeader(
        surfaceKey: const Key('messages-app-header'),
        titleKey: const Key('messages-header-title'),
        title: l10n.text('messages.title'),
        floatingMaxWidth: floatingMaxWidth,
        actions: [
          HeaderDiscButton(
            key: const Key('messages-export'),
            tooltip: l10n.text('export.title'),
            icon: Icons.file_download_outlined,
            onPressed: () =>
                openExportPage(context, category: ExportCategory.messages),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(GlassSegmentedControl.height),
          child: _Folders(
            folder: widget.folder,
            onChanged: widget.onFolderChanged,
          ),
        ),
      ),
      body: Builder(builder: _body),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    // Offline before anything ever arrived: nothing to show but that.
    final neverFetched =
        state == null || (state.messages.isEmpty && state.lastFetched == null);
    if (neverFetched && widget.noInternet) {
      return GlassStateCard(
        key: const Key('messages-offline'),
        icon: Icons.wifi_off_rounded,
        title: l10n.text('offline.title'),
        body: l10n.text('offline.body'),
        actionLabel: widget.onRetry == null ? null : l10n.text('common.retry'),
        onAction: widget.onRetry,
      );
    }
    if (state == null) return const _ListSkeleton();
    final messages = widget.messages;
    if (messages.isEmpty && !widget.loading) {
      return GlassStateCard(
        key: ValueKey('messages-empty-${widget.folder}'),
        icon: Icons.mail_outline_rounded,
        title: l10n.text(messageFolderKeys[widget.folder]),
        body: l10n.text('messages.none'),
      );
    }
    final lastFetched = state.lastFetched;
    final hint = widget.noInternet && lastFetched != null;
    final offset = hint ? 1 : 0;
    return GlassListBody.builder(
      key: ValueKey('messages-folder-${widget.folder}'),
      listKey: const Key('messages-list'),
      controller: _controller,
      itemCount: messages.length + offset,
      itemBuilder: (context, index) {
        if (index < offset) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassOfflineHint(
              key: const Key('messages-last-fetched'),
              message: l10n.text(
                'grades.offlineMode',
                args: {'time': l10n.formatTimeAgo(lastFetched!)},
              ),
              onRetry: widget.onRetry ?? () {},
            ),
          );
        }
        final message = messages[index - offset];
        // Each on a layer of its own: while one opens, the ones below it only
        // move and are not painted again.
        return RepaintBoundary(
          key: _key(message.id),
          child: MessageEntry(
            key: ValueKey('messages-entry-${message.id}'),
            message: message,
            noInternet: widget.noInternet,
            expanded: message.id == widget.expandedMessageId,
            onExpansionChanged: (expanded) =>
                widget.onExpansionChanged(message, expanded),
            onOpenFile: widget.onOpenFile,
            onMarkAsRead: widget.onMarkAsRead,
            onArchive: widget.onArchive,
            onReply: widget.onReply,
          ),
        );
      },
    );
  }
}

/// The four folders. Full names where they fit, short ones on small phones;
/// the full name is always what a screen reader says.
class _Folders extends StatelessWidget {
  const _Folders({required this.folder, required this.onChanged});

  final int folder;
  final ValueChanged<int> onChanged;

  /// What a segment takes around its text.
  static const double _segmentExtra = 2 * 12 + 2 * 2;

  bool _fits(BuildContext context, List<String> labels, double width) {
    final style = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(fontWeight: FontWeight.w600);
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return labels.length * (widest + _segmentExtra) <= width;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = [for (final key in messageFolderKeys) l10n.text(key)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final labels = _fits(context, full, constraints.maxWidth)
            ? full
            : [for (final key in messageFolderKeys) l10n.text('$key.short')];
        return Align(
          alignment: AlignmentDirectional.centerStart,
          // Very large text gets smaller rather than cut off.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GlassSegmentedControl<int>(
              key: const Key('messages-folders'),
              selected: folder,
              onChanged: onChanged,
              segments: [
                for (var i = 0; i < full.length; i++)
                  GlassSegment(value: i, label: labels[i], fullLabel: full[i]),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Quiet rows in place of the messages that are on their way. The bar below
/// the header shows that something is happening.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassListBody(
      key: const Key('messages-loading'),
      children: [
        ExcludeSemantics(
          child: Column(
            children: [
              for (var row = 0; row < 6; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: _rowGap),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: _rowShape.copyWith(
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: SizedBox(
                      height: 56,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            const _SkeletonBar(width: 28, height: 28),
                            const SizedBox(width: 10),
                            _SkeletonBar(
                              width: 120.0 + row % 3 * 30,
                              height: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width, height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
}

/// The badge of [message] as Legacy chooses it, or null for none. "new" is
/// the badge of an unread message.
String? _badgeOf(Message message) {
  if (message.responseRequired == 1 ||
      (message.badge != null && message.badge!.isNotEmpty)) {
    final badge = message.needsResponse == true
        ? 'Nicht beantwortet'
        : (message.badge ?? (message.isNew ? 'new' : ''));
    return badge.isEmpty ? null : badge;
  }
  return message.isNew ? 'new' : null;
}

/// One message: a slim row that opens into a card with its text, its
/// attachments, the reply and the archive.
class MessageEntry extends StatefulWidget {
  const MessageEntry({
    super.key,
    required this.message,
    required this.noInternet,
    required this.expanded,
    required this.onExpansionChanged,
    required this.onOpenFile,
    required this.onMarkAsRead,
    required this.onArchive,
    required this.onReply,
  });

  final Message message;
  final bool noInternet, expanded;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(MessageAttachmentFile file) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final void Function(Message message) onArchive;
  final void Function(int messageId, String response) onReply;

  @override
  State<MessageEntry> createState() => _MessageEntryState();
}

class _MessageEntryState extends State<MessageEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.expanded ? 1 : 0,
  )..addStatusListener(_onStatus);

  late final _sizeFactor = CurvedAnimation(
    parent: _opening,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// What is closed is not built at all, which keeps the list light.
  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // As in Legacy: a message that opens, by a tap or a link, is read.
    if (widget.expanded && widget.message.isNew) {
      widget.onMarkAsRead(widget.message);
    }
  }

  @override
  void didUpdateWidget(MessageEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (widget.expanded && widget.message.isNew) {
      widget.onMarkAsRead(widget.message);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _opening.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _opening.forward();
    } else {
      _opening.reverse();
    }
  }

  @override
  void dispose() {
    _sizeFactor.dispose();
    _opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: _rowShape.copyWith(
          side: BorderSide(
            color: highContrast ? scheme.outline : scheme.outlineVariant,
          ),
        ),
        // The text stands on a solid colour here, so this only gets the rim.
        child: GlassEdge(
          shape: _rowShape,
          sheen: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _MessageHeader(
                message: widget.message,
                expanded: widget.expanded,
                onTap: () => widget.onExpansionChanged(!widget.expanded),
              ),
              if (widget.expanded || !_opening.isDismissed)
                SizeTransition(
                  sizeFactor: _sizeFactor,
                  alignment: Alignment.topCenter,
                  child: _MessageDetails(
                    message: widget.message,
                    noInternet: widget.noInternet,
                    onOpenFile: widget.onOpenFile,
                    onArchive: widget.onArchive,
                    onReply: widget.onReply,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageHeader extends StatelessWidget {
  const _MessageHeader({
    required this.message,
    required this.expanded,
    required this.onTap,
  });

  final Message message;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = message.isNew;
    final badge = _badgeOf(message);
    final date = DateFormat(
      'd.M.yy H:mm',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(message.timeSent);
    final from = message.outgoing ? message.recipientString : message.fromName;
    // The subject keeps the whole width; with large text, the badge gets a
    // line of its own.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final badgeChip = switch (badge) {
      null => null,
      // The open message shows its text, it needs no mark that it is new.
      'new' when expanded => null,
      final badge => _Badge(badge: badge, ownLine: large),
    };
    final subtitle = Text(
      '$from · $date',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    return GlassFocusRing(
      shape: _rowShape,
      activeTint: scheme.onSurface.withValues(alpha: 0.06),
      child: Semantics(
        button: true,
        expanded: expanded,
        onTap: onTap,
        label: [
          message.subject,
          if (unread) l10n.text('messages.new'),
          if (badge != null && badge != 'new') _badgeText(l10n, badge),
          from,
          date,
        ].join(', '),
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('messages-open-${message.id}'),
          customBorder: _rowShape,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          mouseCursor: NewDesignTheme.clickCursor,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: compactRowHeight + 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                children: [
                  _ReadMark(unread: unread),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.subject,
                          maxLines: expanded ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        if (badgeChip == null || large)
                          subtitle
                        else
                          Row(
                            children: [
                              Flexible(child: subtitle),
                              const SizedBox(width: 6),
                              badgeChip,
                            ],
                          ),
                        if (badgeChip != null && large)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: badgeChip,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: _motion(context, 240),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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

/// An envelope on the blue of messages while unread, a quiet outline after.
class _ReadMark extends StatelessWidget {
  const _ReadMark({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = unread ? scheme.info : scheme.outline;
    return DecoratedBox(
      key: unread ? const Key('messages-unread-mark') : null,
      decoration: ShapeDecoration(
        color: unread ? scheme.infoContainer : Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(color: color, width: unread ? 1.5 : 1),
        ),
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(
          unread ? Icons.mark_email_unread_outlined : Icons.drafts_outlined,
          size: 16,
          color: unread ? scheme.onInfoContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _badgeText(AppLocalizations l10n, String badge) => switch (badge) {
      'agree' => l10n.text('messages.agree'),
      'not_agree' => l10n.text('messages.not_agree'),
      'Nicht beantwortet' => l10n.text('messages.not_answered'),
      'new' => l10n.text('messages.new'),
      _ => badge,
    };

class _Badge extends StatelessWidget {
  const _Badge({required this.badge, this.ownLine = false});

  final String badge;

  /// On a line of its own, it may take all of it.
  final bool ownLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (badge) {
      'agree' => (scheme.successContainer, scheme.onSuccessContainer),
      'not_agree' => (scheme.errorContainer, scheme.onErrorContainer),
      'Nicht beantwortet' => (
          scheme.warningContainer,
          scheme.onWarningContainer
        ),
      'new' => (scheme.info, scheme.surfaceContainerLowest),
      _ => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return ConstrainedBox(
      // A long answer does not push the subject out.
      constraints: BoxConstraints(maxWidth: ownLine ? double.infinity : 120),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(
            _badgeText(context.l10n, badge),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageDetails extends StatelessWidget {
  const _MessageDetails({
    required this.message,
    required this.noInternet,
    required this.onOpenFile,
    required this.onArchive,
    required this.onReply,
  });

  final Message message;
  final bool noInternet;
  final void Function(MessageAttachmentFile file) onOpenFile;
  final void Function(Message message) onArchive;
  final void Function(int messageId, String response) onReply;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final strong = muted?.copyWith(fontWeight: FontWeight.w700);
    Widget fact(String label, String value) => Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$label: ', style: strong),
              TextSpan(text: value),
            ],
          ),
          style: muted,
        );
    final divider = Divider(height: 20, color: scheme.outlineVariant);
    final history = messageHistoryText(l10n, message);
    final attachmentsTitle =
        l10n.attachmentLabel(message.attachments.length).replaceAll(':', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          fact(
            l10n.text('messages.sent'),
            DateFormat(
              'd.M.yy H:mm',
              Localizations.localeOf(context).toLanguageTag(),
            ).format(message.timeSent),
          ),
          fact(l10n.text('messages.from'), message.fromName),
          fact(l10n.text('messages.to'), message.recipientString),
          divider,
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            child: renderMessage(message),
          ),
          if (message.attachments.isNotEmpty) ...[
            divider,
            Semantics(
              header: true,
              child: Text(
                attachmentsTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final attachment in message.attachments)
              _AttachmentRow(
                key: ValueKey('messages-attachment-${attachment.id}'),
                attachment: attachment,
                onOpen: !attachment.fileAvailable && noInternet
                    ? null
                    : () => onOpenFile(attachment),
              ),
          ],
          if (history != null) ...[
            divider,
            Text(
              history,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (message.showReply == true && message.needsResponse == true) ...[
            divider,
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('messages-reply-agree'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.success,
                    foregroundColor: scheme.onSuccess,
                  ),
                  onPressed: () => onReply(message.id, 'agree'),
                  child: Text(l10n.text('messages.agree')),
                ),
                FilledButton(
                  key: const Key('messages-reply-not-agree'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: () => onReply(message.id, 'not_agree'),
                  child: Text(l10n.text('messages.not_agree')),
                ),
              ],
            ),
          ],
          if (message.canArchive || message.canUnarchive) ...[
            divider,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('messages-archive'),
                onPressed: noInternet || message.archiving
                    ? null
                    : () => onArchive(message),
                icon: message.archiving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        message.archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                      ),
                label: Text(
                  l10n.text(
                    message.archived
                        ? 'messages.unarchive'
                        : 'messages.archive',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An attachment: its name, what it is, and a button that opens it. While it
/// downloads, the icon turns into a ring.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    super.key,
    required this.attachment,
    required this.onOpen,
  });

  final MessageAttachmentFile attachment;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget icon;
    if (attachment.downloading) {
      icon = SizedBox.square(
        key: const Key('messages-attachment-downloading'),
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: scheme.info),
      );
    } else {
      icon = Icon(
        attachment.isLink
            ? Icons.link_rounded
            : attachment.fileAvailable
                ? Icons.download_done_rounded
                : Icons.insert_drive_file_outlined,
        size: 20,
        color: scheme.info,
      );
    }
    // One button for screen readers: its name, then "Open".
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MergeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerLow,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
            child: Row(
              children: [
                SizedBox(width: 20, child: Center(child: icon)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.originalName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: onOpen,
                  child: Text(l10n.text('common.open')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
