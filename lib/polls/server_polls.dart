import 'dart:async';

import 'package:dr/app_language_controller.dart';
import 'package:dr/polls/poll_api.dart';
import 'package:dr/polls/poll_models.dart';
import 'package:dr/polls/poll_storage.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_service.dart'
    show serverNotificationLanguage;
import 'package:flutter/foundation.dart';

/// Polls of this installation: the API, the installation ID and the local
/// record of votes. Works without a school login. Everything fails open: a
/// missing configuration, storage that does not work or a server that is
/// down only means that voting is not possible right now.
class ServerPolls {
  ServerPolls({
    PollApi? api,
    PollStorage storage = const SharedPreferencesPollStorage(),
    Uri? baseUri,
    String Function()? language,
    DateTime Function()? now,
  })  : _api = api,
        _baseUri = baseUri ?? configuredServerNotificationBaseUri,
        _language = language ??
            (() => serverNotificationLanguage(
                appLanguageController.language.code)),
        now = now ?? DateTime.now,
        installationId = PollInstallationId(storage),
        votes = PollVoteStore(storage);

  PollApi? _api;
  final Uri? _baseUri;
  final String Function() _language;

  /// The real clock, as for announcements: the demo mode's simulated date
  /// has no meaning for server times.
  final DateTime Function() now;
  final PollInstallationId installationId;
  final PollVoteStore votes;

  PollApi? get api {
    final base = _baseUri;
    if (_api == null && base != null && serverNotificationsEnabledByBuild) {
      _api = PollApi(baseUri: base);
    }
    return _api;
  }

  String get language => _language();
}

/// The one instance of this process.
final ServerPolls serverPolls = ServerPolls();

/// What the poll screen shows besides the poll itself.
enum PollNotice {
  none,

  /// The poll could not be refreshed; the screen shows the announcement's copy.
  stale,

  /// A vote failed for a reason that may pass.
  voteFailed,

  /// The poll no longer exists on the server.
  gone,
}

/// State of one poll screen.
class ServerPollController extends ChangeNotifier {
  ServerPollController({required ServerPoll poll, ServerPolls? polls})
      : _poll = poll,
        _polls = polls ?? serverPolls;

  final ServerPolls _polls;
  ServerPoll _poll;
  ServerPoll get poll => _poll;

  bool _loading = true;

  /// Until the local record and the server have been asked.
  bool get loading => _loading;

  bool _sending = false;
  bool get sending => _sending;

  String? _voted;

  /// The option this installation voted for, if it did.
  String? get votedOptionId => _voted;
  ServerPollOption? get votedOption => _poll.option(_voted);

  bool? _serverOpen;
  ServerPollResults? _results;
  PollNotice _notice = PollNotice.none;
  PollNotice get notice => _notice;
  bool _disposed = false;

  /// Votes are accepted: the server says so, or, without an answer, the
  /// closing time has not passed.
  bool get open =>
      _notice != PollNotice.gone &&
      (_serverOpen ?? !_poll.isClosedAt(_polls.now().toUtc()));

  /// The result, when voters may see it and this device may look: after its
  /// vote, or once the poll is over, so it cannot steer the vote.
  ServerPollResults? get visibleResults {
    if (!_poll.showResults || _results == null) return null;
    return _voted != null || !open ? _results : null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the local record, then the server. Neither can block the screen.
  Future<void> load() async {
    try {
      _voted = await _polls.votes.votedFor(_poll.id);
    } catch (_) {}
    _changed();
    await refresh();
  }

  Future<void> refresh() async {
    final api = _polls.api;
    PollFetchResult result = const PollFetchFailed();
    if (api != null) {
      try {
        result = await api.fetch(_poll.id, language: _polls.language);
      } catch (_) {}
    }
    switch (result) {
      case PollFetched(:final state):
        _poll = state.poll;
        _serverOpen = state.open;
        _results = state.results;
        if (_notice == PollNotice.stale) _notice = PollNotice.none;
      case PollGone():
        _notice = PollNotice.gone;
      case PollFetchFailed():
        _notice = PollNotice.stale;
    }
    _loading = false;
    _changed();
  }

  /// Votes for [optionId]. Never throws: every failure becomes a notice.
  Future<void> vote(String optionId) async {
    if (_sending || _voted != null || !open) return;
    _sending = true;
    _notice = PollNotice.none;
    _changed();
    final api = _polls.api;
    PollVoteResult result = const PollVoteFailed();
    if (api != null) {
      try {
        final voter = await _polls.installationId.obtain();
        result = await api.vote(
          _poll.id,
          optionId: optionId,
          installationId: voter,
        );
      } catch (_) {
        result = const PollVoteFailed();
      }
    }
    switch (result) {
      case PollVoteRecorded(:final optionId, :final results):
        _voted = optionId;
        if (results != null) _results = results;
        unawaited(_polls.votes.remember(_poll.id, optionId));
      case PollVoteClosed():
        // The screen now says that the poll is over, with its final result.
        _serverOpen = false;
        unawaited(refresh());
      case PollVoteGone():
        _notice = PollNotice.gone;
      case PollVoteFailed():
        _notice = PollNotice.voteFailed;
    }
    _sending = false;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
