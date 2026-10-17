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

part of 'middleware.dart';

final _messagesMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(MessagesActionsNames.load, _loadMessages)
      ..add(MessagesActionsNames.markAsRead, _markAsRead)
      ..add(MessagesActionsNames.archiveMessage, _archiveMessage)
      ..add(MessagesActionsNames.openFile, _openFile)
      ..add(MessagesActionsNames.replyMessage, _replyMessage);

Future<void> _archiveMessage(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<int> action,
) async {
  final message = api.state.messagesState.messages
      .where((m) => m.id == action.payload)
      .firstOrNull;
  if (api.state.noInternet ||
      message == null ||
      !(message.canArchive || message.canUnarchive) ||
      message.archiving) {
    return;
  }
  await next(action);
  final archived = !message.archived;
  final failureKey =
      archived ? 'messages.archiveFailed' : 'messages.unarchiveFailed';
  try {
    final dynamic response = await wrapper.send(
      'api/message/archiveMessage',
      args: {'messageId': action.payload, 'archiveType': archived ? 1 : 2},
      acceptEmptyResponse: true,
    );
    final result = response is Map ? response : null;
    final error = result?['error'];
    final hasError =
        error != null && error != false && error != 0 && error != '';
    if (response == null ||
        response == false ||
        (result != null &&
            (result['success'] == false ||
                result['success'] == 0 ||
                hasError))) {
      await api.actions.messagesActions.archiveMessageFailed(action.payload);
      showSnackBar(tr(failureKey));
      return;
    }
    await api.actions.messagesActions.archivedMessage(
      ArchiveMessageResult(messageId: action.payload, archived: archived),
    );
    _markRuntimeCacheStale(_messagesCacheKey);
    // Reload the server labels so restored messages return to their original folder.
    try {
      await api.actions.messagesActions.load();
    } catch (e, stack) {
      diagnostics.report(e, stack, DiagnosticError.http);
    }
  } catch (e, stack) {
    await api.actions.messagesActions.archiveMessageFailed(action.payload);
    diagnostics.report(e, stack, DiagnosticError.http);
    showSnackBar(tr(failureKey));
  }
}

// Scope pending replies to the session and store, so navigation does not release
// the guard and an account switch cannot update the new account's messages.
final _pendingReplies = Expando<Expando<Set<int>>>();

bool _replyAccepted(dynamic response) {
  if (response == true || response == '') return true;
  if (response is! Map) return false;
  final error = response['error'];
  if (error != null && error != false && error != 0 && error != '') {
    return false;
  }
  if (response.containsKey('success') &&
      response['success'] != true &&
      response['success'] != 1) {
    return false;
  }
  return response.isEmpty ||
      response.containsKey('error') ||
      response.containsKey('success');
}

Future<void> _replyMessage(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<ReplyMessagePayload> action,
) async {
  final session = wrapper;
  final username = api.state.loginState.username;
  final sessionUrl = session.url;
  final sessionUser = session.user;
  final stores = _pendingReplies[session] ??= Expando<Set<int>>();
  final pending = stores[api.actions] ??= <int>{};
  final message = api.state.messagesState.messages
      .where((m) => m.id == action.payload.messageId)
      .firstOrNull;
  if (message == null ||
      message.showReply != true ||
      !pending.add(action.payload.messageId)) {
    return;
  }
  try {
    await next(action);
    final dynamic response = await session.send(
      "api/message/reply",
      args: {
        "messageId": action.payload.messageId,
        "response": {"response": action.payload.response},
      },
      acceptEmptyResponse: true,
    );
    if (!_replyAccepted(response)) {
      diagnostics.report(const FormatException('Reply not acknowledged'),
          StackTrace.current, DiagnosticError.http);
      if (identical(wrapper, session)) showSnackBar(tr('messages.replyFailed'));
      return;
    }
    if (!identical(wrapper, session) ||
        session.url != sessionUrl ||
        session.user != sessionUser ||
        api.state.loginState.username != username ||
        !api.state.messagesState.messages
            .any((m) => m.id == message.id && m.showReply == true)) {
      return;
    }
    await api.actions.messagesActions.repliedMessage(action.payload);
    _markRuntimeCacheStale(_messagesCacheKey);
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.http);
    if (identical(wrapper, session)) showSnackBar(tr('messages.replyFailed'));
  } finally {
    pending.remove(action.payload.messageId);
  }
}

Future<void> _loadMessages(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  if (api.state.noInternet) return;
  if (!_isCacheMarkedStale(_messagesCacheKey) &&
      _isFresh(api.state.messagesState.lastFetched, _messagesCacheTtl)) {
    return;
  }
  await _runCoalescedLoad(_messagesCacheKey, () async {
    await next(action);
    final dynamic response = await wrapper.send("api/message/getMyMessages");
    if (response != null) {
      await api.actions.messagesActions.loaded(response as List);
      _markRuntimeCacheFresh(_messagesCacheKey);
    }
  });
}

Future<void> _openFile(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<MessageAttachmentFile> action,
) async {
  await next(action);
  if (action.payload.isLink) {
    final link = action.payload.link;
    if (link == null) {
      return;
    }
    final launched = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      showSnackBar(tr('navigation.linkOpenFailed'));
    }
    return;
  }

  if (!action.payload.fileAvailable ||
      !await canOpenFile(action.payload.uniqueName)) {
    await api.actions.messagesActions.downloadFile(action.payload);

    final success = await downloadFile(
      "${wrapper.baseAddress}api/message/messageSubmissionDownloadEntry",
      action.payload.uniqueName,
      <String, dynamic>{
        "messageId": action.payload.messageId,
        "submissionId": action.payload.id,
      },
    );
    await api.actions.messagesActions.fileAvailable(
      action.payload.rebuild((b) => b..fileAvailable = success),
    );
    if (!success) {
      return;
    }
  }

  await openFile(action.payload.uniqueName);
}

Future<void> _markAsRead(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<int> action,
) async {
  await next(action);
  _markRuntimeCacheStale(_messagesCacheKey);
  _markRuntimeCacheStale(_notificationsCacheKey);
  await wrapper.send(
    "api/message/markAsRead",
    args: {"messageId": action.payload},
  );
}
