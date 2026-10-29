// Copyright (C) 2021 Michael Debertol
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

import 'dart:collection';
import 'dart:convert';

import 'package:badges/badges.dart' as badge;
import 'package:dr/app_state.dart';
import 'package:dr/container/export_container.dart';
import 'package:dr/data.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

final LinkedHashMap<int, _CachedMessageDelta> _messageDeltaCache =
    LinkedHashMap<int, _CachedMessageDelta>();
const _messageDeltaCacheLimit = 200;

enum _MessageFolder { incoming, outgoing, archived, all }

/// Reply confirmations that older versions stored as German text after a
/// local reply, mapped to the response they describe.
const _legacyLocalReplyHistory = <String, String>{
  'Mit "Stimme zu" beantwortet.': 'agree',
  'Mit "Stimme nicht zu" beantwortet.': 'not_agree',
};

/// The history line shown below [message], or null when there is none.
///
/// Server-provided history text is shown unchanged. A reply given in the app
/// is described from the stored response in the selected language, including
/// confirmations that older versions saved as German text.
String? messageHistoryText(AppLocalizations l10n, Message message) {
  final history = message.historyString;
  var response = history == null ? null : _legacyLocalReplyHistory[history];
  if (history != null && history.isNotEmpty && response == null) {
    return history;
  }
  if (response == null &&
      message.needsResponse == false &&
      (message.badge == 'agree' || message.badge == 'not_agree')) {
    response = message.badge;
  }
  if (response == null) return null;
  return l10n.text(
    'messages.repliedWith',
    args: {'response': l10n.text('messages.$response')},
  );
}

class MessagesPage extends StatefulWidget {
  final MessagesState? state;
  final bool noInternet;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final void Function(Message message) onArchive;
  final void Function(int messageId, String response) onReply;

  const MessagesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onOpenFile,
    required this.onMarkAsRead,
    required this.onArchive,
    required this.onReply,
  });
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with SingleTickerProviderStateMixin {
  int? _expandedMessageId;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _expandedMessageId = widget.state?.showMessage;
    _tabs = TabController(length: _MessageFolder.values.length, vsync: this);
    _selectMessageFolder(_expandedMessageId);
    _tabs.addListener(_folderChanged);
  }

  void _folderChanged() => setState(() {});

  void _selectMessageFolder(int? id) {
    final message =
        widget.state?.messages.where((message) => message.id == id).firstOrNull;
    if (message == null) return;
    _tabs.index = (message.archived
            ? _MessageFolder.archived
            : message.incoming
                ? _MessageFolder.incoming
                : message.outgoing
                    ? _MessageFolder.outgoing
                    : _MessageFolder.all)
        .index;
  }

  @override
  void dispose() {
    _tabs.removeListener(_folderChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state?.showMessage != null &&
        (oldWidget.state?.showMessage != widget.state?.showMessage ||
            !(oldWidget.state?.messages.any(
                    (message) => message.id == widget.state!.showMessage) ??
                false))) {
      _selectMessageFolder(widget.state!.showMessage);
      _expandedMessageId = widget.state!.showMessage;
    }
    final messages = _visibleMessages(widget.state);
    if (_expandedMessageId != null &&
        !messages.any((message) => message.id == _expandedMessageId)) {
      _expandedMessageId = widget.state?.showMessage != null &&
              messages.any((message) => message.id == widget.state!.showMessage)
          ? widget.state!.showMessage
          : null;
    } else if (oldWidget.state?.showMessage != widget.state?.showMessage &&
        widget.state?.showMessage != null &&
        messages.any((message) => message.id == widget.state!.showMessage)) {
      _expandedMessageId = widget.state!.showMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = _visibleMessages(widget.state);
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Text(context.t('messages.title')),
        actions: [
          IconButton(
              tooltip: context.t('export.title'),
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () =>
                  openExportPage(context, category: ExportCategory.messages))
        ],
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: [
              Tab(text: context.t('messages.incoming')),
              Tab(text: context.t('messages.outgoing')),
              Tab(text: context.t('messages.archived')),
              Tab(text: context.t('messages.all')),
            ],
          ),
          Expanded(
              child: ReadableContent(
                  child: _buildMessageList(context, visibleMessages))),
        ],
      ),
    );
  }

  Widget _buildMessageList(
      BuildContext context, List<Message> visibleMessages) {
    return widget.state == null
        ? widget.noInternet
            ? const NoInternet()
            : const Center(child: CircularProgressIndicator())
        : LastFetchedOverlay(
            lastFetched: widget.state!.lastFetched,
            noInternet: widget.noInternet,
            child: Stack(
              children: <Widget>[
                AnimatedLinearProgressIndicator(
                  show: widget.state!.showMessage != null &&
                      !widget.state!.messages.any(
                        (m) => m.id == widget.state!.showMessage,
                      ),
                ),
                if (visibleMessages.isEmpty)
                  Center(
                    child: Text(
                      context.t('messages.none'),
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ListView.builder(
                  key: ValueKey('messages-folder-${_tabs.index}'),
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, i) {
                    return MessageWidget(
                      key: ValueKey(visibleMessages[i].id),
                      message: visibleMessages[i],
                      onOpenFile: widget.onOpenFile,
                      onMarkAsRead: widget.onMarkAsRead,
                      onArchive: widget.onArchive,
                      onReply: widget.onReply,
                      noInternet: widget.noInternet,
                      expand: visibleMessages[i].id == _expandedMessageId,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _expandedMessageId = visibleMessages[i].id;
                          } else if (_expandedMessageId ==
                              visibleMessages[i].id) {
                            _expandedMessageId = null;
                          }
                        });
                      },
                    );
                  },
                ),
              ],
            ),
          );
  }

  List<Message> _visibleMessages(MessagesState? state) {
    if (state == null) {
      return const <Message>[];
    }
    final folder = _MessageFolder.values[_tabs.index];
    return state.messages.where((message) {
      final matches = switch (folder) {
        _MessageFolder.incoming => message.incoming && !message.archived,
        _MessageFolder.outgoing => message.outgoing && !message.archived,
        _MessageFolder.archived => message.archived,
        _MessageFolder.all => message.labelAll,
      };
      // Messages whose body cannot be rendered stay listed: their subject,
      // attachments and actions remain available with a body fallback.
      return matches;
    }).toList(growable: false);
  }
}

class MessageWidget extends StatefulWidget {
  final Message message;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final void Function(Message message) onArchive;
  final void Function(int messageId, String response) onReply;
  final bool noInternet;
  final bool expand;
  final ValueChanged<bool> onExpansionChanged;

  const MessageWidget({
    super.key,
    required this.message,
    required this.onOpenFile,
    required this.noInternet,
    required this.onMarkAsRead,
    required this.onArchive,
    required this.onReply,
    required this.expand,
    required this.onExpansionChanged,
  });

  @override
  _MessageWidgetState createState() => _MessageWidgetState();
}

class _MessageWidgetState extends State<MessageWidget> {
  late final ExpansibleController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ExpansibleController();
    if (widget.expand && widget.message.isNew) {
      widget.onMarkAsRead(widget.message);
    }
  }

  @override
  void didUpdateWidget(covariant MessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expand == oldWidget.expand) {
      return;
    }
    if (widget.expand) {
      _controller.expand();
      if (widget.message.isNew) {
        widget.onMarkAsRead(widget.message);
      }
    } else {
      _controller.collapse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getTranslatedBadge(BuildContext context, String badgeKey) {
    if (badgeKey == "agree") return context.t('messages.agree');
    if (badgeKey == "not_agree") return context.t('messages.not_agree');
    if (badgeKey == "Nicht beantwortet") {
      return context.t('messages.not_answered');
    }
    return badgeKey;
  }

  Color _getBadgeColor(BuildContext context, String badgeKey) {
    final scheme = Theme.of(context).colorScheme;
    if (badgeKey == "agree") return scheme.success;
    if (badgeKey == "not_agree") return scheme.error;
    if (badgeKey == "Nicht beantwortet") return scheme.warning;
    return scheme.primary;
  }

  Color _getBadgeTextColor(BuildContext context, String badgeKey) {
    final scheme = Theme.of(context).colorScheme;
    if (badgeKey == "agree") return scheme.onSuccess;
    if (badgeKey == "not_agree") return scheme.onError;
    if (badgeKey == "Nicht beantwortet") return scheme.onWarning;
    return scheme.onPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ExpansionTile(
      controller: _controller,
      initiallyExpanded: widget.expand,
      maintainState: true,
      onExpansionChanged: (expanded) {
        if (expanded && widget.message.isNew) {
          widget.onMarkAsRead(widget.message);
        }
        widget.onExpansionChanged(expanded);
      },
      title: Row(
        children: <Widget>[
          if (widget.message.needsResponse == true)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Expanded(
            child: Text(
              widget.message.subject,
              style: textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.message.responseRequired == 1 ||
              (widget.message.badge != null &&
                  widget.message.badge!.isNotEmpty))
            Builder(builder: (context) {
              final badgeStr = (widget.message.needsResponse == true)
                  ? "Nicht beantwortet"
                  : (widget.message.badge ??
                      (widget.message.isNew ? "new" : ""));

              if (badgeStr == "new") {
                return !widget.expand
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: badge.Badge(
                          badgeStyle: badge.BadgeStyle(
                            shape: badge.BadgeShape.square,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          badgeContent: Text(
                            context.t('messages.new'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              }

              if (badgeStr.isEmpty) return const SizedBox.shrink();

              return Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: badge.Badge(
                  badgeStyle: badge.BadgeStyle(
                    shape: badge.BadgeShape.square,
                    borderRadius: BorderRadius.circular(20),
                    badgeColor: _getBadgeColor(context, badgeStr),
                  ),
                  badgeContent: Text(
                    _getTranslatedBadge(context, badgeStr),
                    style: TextStyle(
                        color: _getBadgeTextColor(context, badgeStr),
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              );
            })
          else if (widget.message.isNew && !widget.expand)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: badge.Badge(
                badgeStyle: badge.BadgeStyle(
                  shape: badge.BadgeShape.square,
                  borderRadius: BorderRadius.circular(20),
                ),
                badgeContent: Text(
                  context.t('messages.new'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(
            bottom: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${context.t('messages.sent')}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                        text: DateFormat(
                      "d.M.yy H:mm",
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(widget.message.timeSent))
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${context.t('messages.from')}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: widget.message.fromName)
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${context.t('messages.to')}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: widget.message.recipientString)
                  ],
                ),
              ),
              const Divider(),
              renderMessage(widget.message),
              if (widget.message.attachments.isNotEmpty) ...[
                const Divider(),
                Text(
                  context.l10n.attachmentLabel(
                    widget.message.attachments.length,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              ...[
                for (final attachment in widget.message.attachments)
                  [
                    Text(
                      attachment.originalName,
                    ),
                    AnimatedLinearProgressIndicator(
                      show: attachment.downloading,
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed:
                            !attachment.fileAvailable && widget.noInternet
                                ? null
                                : () {
                                    widget.onOpenFile(attachment);
                                  },
                        child: Text(context.t('common.open')),
                      ),
                    ),
                  ]
              ].intersperse(const Divider()),
              if (messageHistoryText(context.l10n, widget.message)
                  case final history?) ...[
                const Divider(),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      history,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
              if (widget.message.showReply == true &&
                  widget.message.needsResponse == true) ...[
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.success,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSuccess,
                      ),
                      onPressed: () =>
                          widget.onReply(widget.message.id, "agree"),
                      child: Text(context.t('messages.agree')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: () =>
                          widget.onReply(widget.message.id, "not_agree"),
                      child: Text(context.t('messages.not_agree')),
                    ),
                  ],
                ),
              ],
              if (widget.message.canArchive || widget.message.canUnarchive) ...[
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.noInternet || widget.message.archiving
                        ? null
                        : () => widget.onArchive(widget.message),
                    icon: widget.message.archiving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(widget.message.archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined),
                    label: Text(context.t(widget.message.archived
                        ? 'messages.unarchive'
                        : 'messages.archive')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Widget renderMessage(Message message) {
  final Delta delta;
  try {
    final stopwatch = Stopwatch()..start();
    final resolved = _resolveMessageDelta(message);
    delta = resolved.delta;
    stopwatch.stop();
    logPerformanceEvent(
      "message_render_ready",
      <String, Object?>{
        "messageId": message.id,
        "elapsedUs": stopwatch.elapsedMicroseconds,
        "fromCache": resolved.fromCache,
      },
    );
  } catch (_) {
    return const _MessageBodyNotice('messages.body.unsupported');
  }
  // Embeds such as images are not supported by the viewer; their
  // surrounding text is still shown.
  final (:text, :hasEmbeds) = _textOnlyDelta(delta);
  final hasVisibleText = text.toList().any(
        (op) => (op.data as String).trim().isNotEmpty,
      );
  if (!hasVisibleText) {
    return _MessageBodyNotice(
      hasEmbeds ? 'messages.body.unsupported' : 'messages.body.empty',
    );
  }
  final viewer = QuillDeltaViewer(delta: text);
  if (!hasEmbeds) return viewer;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      viewer,
      const _MessageBodyNotice('messages.body.partiallyUnsupported'),
    ],
  );
}

({Delta text, bool hasEmbeds}) _textOnlyDelta(Delta delta) {
  final text = Delta();
  var hasEmbeds = false;
  for (var i = 0; i < delta.length; i++) {
    final op = delta.elementAt(i);
    final data = op.data;
    if (op.isInsert && data is String) {
      text.push(Operation.insert(data, op.attributes));
    } else {
      hasEmbeds = true;
    }
  }
  return (text: text, hasEmbeds: hasEmbeds);
}

class _MessageBodyNotice extends StatelessWidget {
  const _MessageBodyNotice(this.textKey);

  final String textKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        context.t(textKey),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

_ResolvedMessageDelta _resolveMessageDelta(Message message) {
  final cached = _messageDeltaCache[message.id];
  if (cached != null && cached.source == message.text) {
    _messageDeltaCache.remove(message.id);
    _messageDeltaCache[message.id] = cached;
    return _ResolvedMessageDelta(
      delta: cached.delta,
      fromCache: true,
    );
  }

  final stopwatch = Stopwatch()..start();
  final delta = Delta.fromJson(jsonDecode(message.text)["ops"] as List);
  stopwatch.stop();
  logPerformanceEvent(
    "message_delta_parsed",
    <String, Object?>{
      "messageId": message.id,
      "elapsedMs": stopwatch.elapsedMilliseconds,
    },
  );
  _messageDeltaCache[message.id] = _CachedMessageDelta(
    source: message.text,
    delta: delta,
  );
  while (_messageDeltaCache.length > _messageDeltaCacheLimit) {
    _messageDeltaCache.remove(_messageDeltaCache.keys.first);
  }
  return _ResolvedMessageDelta(
    delta: delta,
    fromCache: false,
  );
}

class _CachedMessageDelta {
  const _CachedMessageDelta({
    required this.source,
    required this.delta,
  });

  final String source;
  final Delta delta;
}

class _ResolvedMessageDelta {
  const _ResolvedMessageDelta({
    required this.delta,
    required this.fromCache,
  });

  final Delta delta;
  final bool fromCache;
}
