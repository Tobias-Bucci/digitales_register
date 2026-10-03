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

Future<void> _replyMessage(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<ReplyMessagePayload> action,
) async {
  await next(action);
  try {
    await wrapper.send(
      "api/message/reply",
      args: {
        "messageId": action.payload.messageId,
        "response": {"response": action.payload.response},
      },
    );
    // If the API call completes without throwing, we consider it a success
    await api.actions.messagesActions.repliedMessage(action.payload);
    _markRuntimeCacheStale(_messagesCacheKey);
  } catch (e) {
    // Optionally handle error? The wrapper probably shows an error snackbar for generic failures.
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
