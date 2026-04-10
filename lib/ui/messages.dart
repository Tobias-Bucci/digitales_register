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
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:quill_delta_viewer/quill_delta_viewer.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

final LinkedHashMap<int, _CachedMessageDelta> _messageDeltaCache =
    LinkedHashMap<int, _CachedMessageDelta>();
const _messageDeltaCacheLimit = 200;

class MessagesPage extends StatefulWidget {
  final MessagesState? state;
  final bool noInternet;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;

  const MessagesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.onOpenFile,
    required this.onMarkAsRead,
  });
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int? _expandedMessageId;

  @override
  void initState() {
    super.initState();
    _expandedMessageId = widget.state?.showMessage;
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      ),
      body: widget.state == null
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
                        !visibleMessages.any(
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
                    itemCount: visibleMessages.length,
                    itemBuilder: (context, i) {
                      return MessageWidget(
                        key: ValueKey(visibleMessages[i].id),
                        message: visibleMessages[i],
                        onOpenFile: widget.onOpenFile,
                        onMarkAsRead: widget.onMarkAsRead,
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
            ),
    );
  }

  List<Message> _visibleMessages(MessagesState? state) {
    if (state == null) {
      return const <Message>[];
    }
    return state.messages.where(_canRenderMessage).toList(growable: false);
  }
}

class MessageWidget extends StatefulWidget {
  final Message message;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final bool noInternet;
  final bool expand;
  final ValueChanged<bool> onExpansionChanged;

  const MessageWidget({
    super.key,
    required this.message,
    required this.onOpenFile,
    required this.noInternet,
    required this.onMarkAsRead,
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
    if (widget.expand) {
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
          Expanded(
            child: Text(
              widget.message.subject,
              style: textTheme.titleMedium,
            ),
          ),
          if (widget.message.isNew && !widget.expand)
            badge.Badge(
              badgeStyle: badge.BadgeStyle(
                shape: badge.BadgeShape.square,
                borderRadius: BorderRadius.circular(20),
              ),
              badgeContent: Text(
                context.t('messages.new'),
                style: const TextStyle(color: Colors.white),
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
            ],
          ),
        ),
      ],
    );
  }
}

bool _canRenderMessage(Message message) {
  try {
    final resolved = _resolveMessageDelta(message);
    return _isRenderableMessageDelta(resolved.delta);
  } catch (_) {
    return false;
  }
}

Widget renderMessage(Message message) {
  try {
    final stopwatch = Stopwatch()..start();
    final resolved = _resolveMessageDelta(message);
    if (!_isRenderableMessageDelta(resolved.delta)) {
      return const SizedBox.shrink();
    }
    stopwatch.stop();
    logPerformanceEvent(
      "message_render_ready",
      <String, Object?>{
        "messageId": message.id,
        "elapsedUs": stopwatch.elapsedMicroseconds,
        "fromCache": resolved.fromCache,
      },
    );
    return QuillDeltaViewer(delta: resolved.delta);
  } catch (_) {
    return const SizedBox.shrink();
  }
}

bool _isRenderableMessageDelta(Delta delta) {
  final operations = <Operation>[];
  for (var i = 0; i < delta.length; i++) {
    final op = delta.elementAt(i);
    if (op.data is! String) {
      return false;
    }
    var string = op.data as String;
    final split = <String>[];
    for (;;) {
      final index = string.indexOf("\n");
      if (index == -1) {
        split.add(string);
        break;
      }
      split.add(string.substring(0, index + 1));
      string = string.substring(index + 1);
    }
    operations.addAll(
      split.map((s) => Operation.insert(s, op.attributes)),
    );
  }

  while (operations.isNotEmpty) {
    final last = operations.last.data;
    if (last is! String || last.isNotEmpty) {
      break;
    }
    operations.removeLast();
  }

  return operations.isNotEmpty;
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
