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

final Map<int, _CachedMessageDelta> _messageDeltaCache =
    <int, _CachedMessageDelta>{};

class MessagesPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ResponsiveAppBar(
        title: Text(context.t('messages.title')),
      ),
      body: state == null
          ? noInternet
              ? const NoInternet()
              : const Center(child: CircularProgressIndicator())
          : LastFetchedOverlay(
              lastFetched: state!.lastFetched,
              noInternet: noInternet,
              child: Stack(
                children: <Widget>[
                  AnimatedLinearProgressIndicator(
                    show: state!.showMessage != null &&
                        !state!.messages.any((m) => m.id == state!.showMessage),
                  ),
                  if (state!.messages.isEmpty)
                    Center(
                      child: Text(
                        context.t('messages.none'),
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ListView.builder(
                    itemCount: state!.messages.length,
                    itemBuilder: (context, i) {
                      return MessageWidget(
                        message: state!.messages[i],
                        onOpenFile: onOpenFile,
                        onMarkAsRead: onMarkAsRead,
                        noInternet: noInternet,
                        expand: state!.messages[i].id == state!.showMessage,
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class MessageWidget extends StatefulWidget {
  final Message message;
  final void Function(MessageAttachmentFile message) onOpenFile;
  final void Function(Message message) onMarkAsRead;
  final bool noInternet;
  final bool expand;

  const MessageWidget({
    super.key,
    required this.message,
    required this.onOpenFile,
    required this.noInternet,
    required this.onMarkAsRead,
    required this.expand,
  });

  @override
  _MessageWidgetState createState() => _MessageWidgetState();
}

class _MessageWidgetState extends State<MessageWidget> {
  late final bool initiallyExpanded;
  late bool _expanded;

  @override
  void initState() {
    initiallyExpanded = widget.expand;
    _expanded = widget.expand;
    if (initiallyExpanded) {
      widget.onMarkAsRead(widget.message);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      onExpansionChanged: (expanded) {
        setState(() {
          _expanded = expanded;
        });
        if (expanded && widget.message.isNew) {
          widget.onMarkAsRead(widget.message);
        }
      },
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              widget.message.subject,
              style: textTheme.titleMedium,
            ),
          ),
          if (widget.message.isNew || initiallyExpanded)
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
        if (_expanded || initiallyExpanded)
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
                          )
                              .format(widget.message.timeSent))
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

Widget renderMessage(Message message) {
  final stopwatch = Stopwatch()..start();
  final resolved = _resolveMessageDelta(message);
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
}

_ResolvedMessageDelta _resolveMessageDelta(Message message) {
  final cached = _messageDeltaCache[message.id];
  if (cached != null && cached.source == message.text) {
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
