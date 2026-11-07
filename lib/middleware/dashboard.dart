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

final _dashboardMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(DashboardActionsNames.load, _loadDays)
      ..add(DashboardActionsNames.switchFuture, _switchFuture)
      ..add(DashboardActionsNames.addReminder, _addReminder)
      ..add(DashboardActionsNames.editReminder, _editReminder)
      ..add(DashboardActionsNames.deleteHomework, _deleteHomework)
      ..add(DashboardActionsNames.toggleDone, _toggleDone)
      ..add(DashboardActionsNames.openAttachment, _openAttachment)
      ..add(
        SettingsActionsNames.markNotSeenDashboardEntries,
        _markNotSeenEntries,
      );

Future<void> _loadDays(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<bool> action,
) async {
  if (api.state.noInternet) return;

  final cacheKey = _dashboardCacheKey(action.payload);
  if (_isRuntimeCacheFresh(cacheKey, _dashboardCacheTtl)) {
    _startCalendarBackgroundLoad(api);
    return;
  }

  await _runCoalescedLoad(cacheKey, () async {
    final session = _Session.capture();
    await next(action);
    final dynamic data = await session.send(
      "api/student/dashboard/dashboard",
      args: {"viewFuture": action.payload},
    );

    if (data is! List) {
      await api.actions.dashboardActions.notLoaded();
      return;
    }
    await api.actions.dashboardActions.loaded(
      DaysLoadedPayload(
        (b) => b
          ..data = data
          ..future = action.payload
          ..markNewOrChangedEntries =
              api.state.settingsState.dashboardMarkNewOrChangedEntries
          ..deduplicateEntries =
              api.state.settingsState.dashboardDeduplicateEntries,
      ),
    );
    _markRuntimeCacheFresh(cacheKey, session);
    // Holidays also need calendar data when the timetable has never been opened.
    _startCalendarBackgroundLoad(api);
  });
}

Future<void> _switchFuture(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  await api.actions.dashboardActions.load(api.state.dashboardState.future);
}

/// Says that a change did not reach the server. With [retry] the user can send
/// it again, as long as the app is still in the session that made it: what they
/// entered is kept by the button even when the screen they entered it on is gone.
Future<void> _showSaveFailed(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session, {
  Future<void> Function()? retry,
}) async {
  final l10n = await _loadMiddlewareLocalizations(api.state);
  showSnackBar(
    l10n.text(wrapper.noInternet ? 'error.saveOffline' : 'error.save'),
    actionLabel: retry == null ? null : l10n.text('common.retry'),
    onAction: retry == null
        ? null
        : () {
            if (session.isCurrent) unawaited(retry());
          },
  );
}

Future<void> _addReminder(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<AddReminderPayload> action,
) async {
  final session = _Session.capture();
  await next(action);
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  final dynamic result = await session.send(
    "api/student/dashboard/save_reminder",
    args: {
      "date": DateFormat("yyyy-MM-dd").format(action.payload.date),
      "text": action.payload.msg,
    },
  );
  if (result == null) {
    await _showSaveFailed(
      api,
      session,
      retry: () => api.actions.dashboardActions.addReminder(action.payload),
    );
    return;
  }
  await api.actions.dashboardActions.homeworkAdded(
    HomeworkAddedPayload(
      (b) => b
        ..data = result
        ..date = action.payload.date,
    ),
  );
}

Future<void> _deleteHomework(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Homework> action,
) async {
  // Remove the entry from the dashboard immediately and reconcile with the
  // server afterwards, so reminder deletes behave responsively.
  final session = _Session.capture();
  Future<void> retry() =>
      api.actions.dashboardActions.deleteHomework(action.payload);
  // Offline it could not come back, so it does not go away in the first place.
  if (wrapper.noInternet) {
    await _showSaveFailed(api, session, retry: retry);
    return;
  }
  await next(action);
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  final dynamic result = await session.send(
    "api/student/dashboard/delete_reminder",
    args: {"id": action.payload.id},
  );
  if (result == null || result["success"] != true) {
    await api.actions.dashboardActions.load(api.state.dashboardState.future);
    await _showSaveFailed(api, session, retry: retry);
  }
}

Future<void> _editReminder(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<EditReminderPayload> action,
) async {
  final session = _Session.capture();
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  // The new text first: if anything fails, the worst case is that both entries
  // exist, and not that the old one is gone and the new one was never saved.
  final dynamic saveResult = await session.send(
    "api/student/dashboard/save_reminder",
    args: {
      "date": DateFormat("yyyy-MM-dd").format(action.payload.date),
      "text": action.payload.msg,
    },
  );
  if (saveResult == null) {
    await _showSaveFailed(
      api,
      session,
      retry: () => api.actions.dashboardActions.editReminder(action.payload),
    );
    return;
  }

  final deleteResult = await session.send(
    "api/student/dashboard/delete_reminder",
    args: {"id": action.payload.previousHomework.id},
  );
  if (deleteResult == null || deleteResult["success"] != true) {
    await api.actions.dashboardActions.load(api.state.dashboardState.future);
    await _showSaveFailed(api, session);
    return;
  }

  await api.actions.dashboardActions.reminderEdited(
    HomeworkEditedPayload(
      (b) => b
        ..previousHomework.replace(action.payload.previousHomework)
        ..data = saveResult
        ..date = action.payload.date,
    ),
  );
}

Future<void> _toggleDone(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<ToggleDonePayload> action,
) async {
  final session = _Session.capture();
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  final dynamic result = await session.send(
    "api/student/dashboard/toggle_reminder",
    args: {
      "id": action.payload.homeworkId,
      "type": action.payload.type,
      "value": action.payload.done,
    },
  );
  if (result != null && result["success"] == true) {
    await next(action);
  } else {
    await _showSaveFailed(
      api,
      session,
      retry: () => api.actions.dashboardActions.toggleDone(action.payload),
    );
  }
}

Future<void> _markNotSeenEntries(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<bool> action,
) async {
  if (!action.payload) {
    await api.actions.dashboardActions.markAllAsSeen();
  }
  await next(action);
}

Future<void> _openAttachment(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<GradeGroupSubmission> action,
) async {
  await next(action);

  if (!action.payload.fileAvailable ||
      !await canOpenFile(action.payload.uniqueName)) {
    await api.actions.dashboardActions.downloadAttachment(action.payload);

    await next(action);
    final success = await downloadFile(
      "${wrapper.baseAddress}api/gradeGroup/gradeGroupSubmissionDownloadEntry",
      action.payload.uniqueName,
      <String, dynamic>{
        "submissionId": action.payload.id,
        "parentId": action.payload.gradeGroupId,
      },
    );
    await api.actions.dashboardActions.attachmentReady(
      action.payload.rebuild((b) => b..fileAvailable = success),
    );
    if (!success) {
      return;
    }
  }

  await openFile(action.payload.uniqueName);
}
