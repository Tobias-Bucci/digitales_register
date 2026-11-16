import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/polls/poll_models.dart';
import 'package:dr/polls/server_polls.dart';
import 'package:dr/ui/glass_page.dart';
import 'package:dr/ui/glass_surface.dart';
import 'package:dr/ui/readable_content.dart';
import 'package:dr/ui/server_notifications/server_notification_visuals.dart'
    show formatServerNotificationTime;
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

const double _readableWidth = 640;

/// Opens the poll of an announcement: a page in the shell of the new design,
/// a page with an app bar in the legacy design and while signed out.
Future<void> openServerPoll(BuildContext context, ServerPoll poll,
        {ServerPolls? polls}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServerPollPage(poll: poll, polls: polls),
    ));

/// The poll screen: question, answers, vote, then "You voted" with the
/// result if the poll shows it. Needs no school login.
class ServerPollPage extends StatefulWidget {
  const ServerPollPage({super.key, required this.poll, this.polls});

  final ServerPoll poll;
  final ServerPolls? polls;

  @override
  State<ServerPollPage> createState() => _ServerPollPageState();
}

class _ServerPollPageState extends State<ServerPollPage> {
  late final ServerPollController _controller =
      ServerPollController(poll: widget.poll, polls: widget.polls);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = context.l10n.text('polls.title');
    final newDesign = ResponsiveNavigationScope.isActive(context);
    final view = ServerPollView(controller: _controller, newDesign: newDesign);
    if (newDesign) {
      final padding = MediaQuery.paddingOf(context);
      return GlassPage(
        header: GlassPageHeader(
          surfaceKey: const Key('poll-header'),
          title: title,
          floatingMaxWidth:
              glassHeaderFloatingWidth(MediaQuery.sizeOf(context).width),
        ),
        body: ReadableContent(
          maxWidth: DesignTokens.contentMaxWidth,
          child: ListView(
            key: const Key('poll-list'),
            padding: EdgeInsets.fromLTRB(
              DesignTokens.gutter,
              padding.top + 8,
              DesignTokens.gutter,
              padding.bottom + DesignTokens.gutter,
            ),
            children: [
              GlassCard(
                key: const Key('poll-card'),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: view,
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readableWidth),
          child: ListView(
            key: const Key('poll-list'),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [view],
          ),
        ),
      ),
    );
  }
}

/// The content of the poll screen, the same in both designs.
class ServerPollView extends StatefulWidget {
  const ServerPollView({
    super.key,
    required this.controller,
    required this.newDesign,
  });

  final ServerPollController controller;
  final bool newDesign;

  @override
  State<ServerPollView> createState() => _ServerPollViewState();
}

class _ServerPollViewState extends State<ServerPollView> {
  String? _selected;
  final FocusNode _votedFocus = FocusNode(debugLabel: 'poll-voted');

  ServerPollController get _controller => widget.controller;

  @override
  void dispose() {
    _votedFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirm(ServerPollOption option) async {
    final l10n = context.l10n;
    final title =
        l10n.text('polls.confirmTitle', args: {'option': option.label});
    final body = l10n.text('polls.confirmBody');
    if (widget.newDesign) {
      final confirmed = await showGlassSheet<bool>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return GlassPanel(
            title: title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  body,
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
                      key: const Key('poll-confirm-cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.text('polls.cancel')),
                    ),
                    FilledButton(
                      key: const Key('poll-confirm'),
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(l10n.text('polls.confirm')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
      return confirmed ?? false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('poll-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.text('polls.cancel')),
          ),
          FilledButton(
            key: const Key('poll-confirm'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.text('polls.confirm')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _vote() async {
    final option = _controller.poll.option(_selected);
    if (option == null) return;
    if (!await _confirm(option) || !mounted) return;
    await _controller.vote(option.id);
    // Focus and the screen reader land on "You voted".
    if (mounted && _controller.votedOptionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _votedFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final poll = _controller.poll;
    final open = _controller.open;
    final voted = _controller.votedOption;
    final notice = _controller.notice;
    final results = _controller.visibleResults;
    final muted =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    final children = <Widget>[
      Semantics(
        header: true,
        child: SelectableText(
          poll.question,
          key: const Key('poll-question'),
          style: theme.textTheme.headlineSmall,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        notice == PollNotice.gone
            ? l10n.text('polls.gone')
            : open
                ? l10n.text('polls.openUntil', args: {
                    'date': formatServerNotificationTime(context, poll.closesAt)
                  })
                : l10n.text('polls.closedAt', args: {
                    'date': formatServerNotificationTime(context, poll.closesAt)
                  }),
        style: muted,
      ),
    ];

    if (notice == PollNotice.stale) {
      children.addAll([
        const SizedBox(height: 12),
        _Notice(
          key: const Key('poll-stale'),
          text: l10n.text('polls.stale'),
          icon: Icons.cloud_off_outlined,
          action: TextButton(
            onPressed: () => unawaited(_controller.refresh()),
            child: Text(l10n.text('polls.retry')),
          ),
        ),
      ]);
    }

    if (voted != null) {
      children.addAll([
        const SizedBox(height: 20),
        Focus(
          focusNode: _votedFocus,
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Container(
              key: const Key('poll-voted'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.how_to_vote_outlined,
                      color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.text('polls.voted', args: {'option': voted.label}),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
    } else if (open && notice != PollNotice.gone) {
      children.addAll([
        const SizedBox(height: 16),
        Text(l10n.text('polls.hint'),
            key: const Key('poll-hint'), style: muted),
        const SizedBox(height: 8),
        Semantics(
          label: l10n.text('polls.options'),
          container: true,
          explicitChildNodes: true,
          child: RadioGroup<String>(
            groupValue: _selected,
            onChanged: (value) {
              if (!_controller.sending) setState(() => _selected = value);
            },
            // Its own Material, so the ink of the tiles shows on the glass
            // card of the new design.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (final option in poll.options)
                    RadioListTile<String>(
                      key: ValueKey('poll-option-${option.id}'),
                      value: option.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (notice == PollNotice.voteFailed) ...[
          _Notice(
            key: const Key('poll-error'),
            text: l10n.text('polls.failed'),
            icon: Icons.error_outline_rounded,
            live: true,
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _controller.sending
              ? Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(l10n.text('polls.sending')),
                    ],
                  ),
                )
              : FilledButton.icon(
                  key: const Key('poll-vote'),
                  style: widget.newDesign ? glassControlStyle(scheme) : null,
                  onPressed:
                      _selected == null ? null : () => unawaited(_vote()),
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: Text(l10n.text('polls.vote')),
                ),
        ),
      ]);
    } else if (notice != PollNotice.gone) {
      children.addAll([
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(l10n.text('polls.closed'),
              key: const Key('poll-closed'),
              style: theme.textTheme.titleMedium),
        ),
      ]);
    }

    if (results != null) {
      children.addAll([
        const SizedBox(height: 24),
        _Results(poll: poll, results: results, mine: voted?.id),
      ]);
    } else if (voted != null && !poll.showResults) {
      children.addAll([
        const SizedBox(height: 16),
        Text(l10n.text('polls.resultHidden'),
            key: const Key('poll-result-hidden'), style: muted),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.text,
    required this.icon,
    this.action,
    this.live = false,
  });

  final String text;
  final IconData icon;
  final Widget? action;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: live,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.poll, required this.results, this.mine});

  final ServerPoll poll;
  final ServerPollResults results;
  final String? mine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String votes(int count) => count == 1
        ? l10n.text('polls.votesOne')
        : l10n.text('polls.votesMany', args: {'count': '$count'});
    return Column(
      key: const Key('poll-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.text('polls.results'),
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        for (final option in poll.options) ...[
          Semantics(
            container: true,
            label: l10n.text('polls.resultSemantics', args: {
              'option': option.label,
              'percent': '${results.percentFor(option.id)}',
              'votes': votes(results.votesFor(option.id)),
            }),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        style: option.id == mine
                            ? theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700)
                            : theme.textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${results.percentFor(option.id)} % · ${votes(results.votesFor(option.id))}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: results.percentFor(option.id) / 100,
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          '${votes(results.totalVotes)}. ${l10n.text('polls.perDevice')}',
          key: const Key('poll-total'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
