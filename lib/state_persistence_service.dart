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

import 'dart:async';
import 'dart:convert';
import 'package:dr/app_state.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/serializers.dart';
import 'package:dr/util.dart';

typedef PersistStateWriter = Future<void> Function(String key, String value);
typedef StorageKeyFactory = String Function(String? user, String server);

class AppStatePersistenceService {
  AppStatePersistenceService({
    this.debounce = const Duration(seconds: 5),
  });

  final Duration debounce;

  Timer? _pendingSave;
  _PendingPersistenceRequest? _pendingRequest;

  /// Every write and every deletion runs behind this one, in the order it was
  /// requested. A native write that has started cannot be taken back, so the
  /// only way to keep an older write from landing after a newer one (or after
  /// a deletion) is to not start the newer one before it has finished.
  Future<void> _queue = Future<void>.value();

  /// Changes with every [clear]: bookkeeping of a write that was running
  /// while the service was cleared describes a state nobody has any more.
  int _generation = 0;
  _PersistedStateIdentity? _lastPersistedIdentity;
  String? _lastPersistedKey;
  String? _lastPersistedPayload;

  void schedule({
    required AppState state,
    required bool deletedData,
    required String server,
    required PersistStateWriter writer,
    required StorageKeyFactory keyFactory,
  }) {
    _pendingRequest = _PendingPersistenceRequest(
      state: state,
      deletedData: deletedData,
      server: server,
      writer: writer,
      keyFactory: keyFactory,
    );
    _pendingSave?.cancel();
    _pendingSave = Timer(
      debounce,
      () => unawaited(flush()),
    );
  }

  /// Runs [action] after every write requested so far has finished, and
  /// before any write requested later starts. Deleting stored data goes
  /// through here, so an older write cannot bring the data back.
  Future<T> runExclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    // A failing action must not block the writes behind it.
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Completes once every write requested so far has finished.
  Future<void> drain() => runExclusive<void>(() async {});

  Future<void> flush({
    AppState? state,
    bool? deletedData,
    String? server,
    PersistStateWriter? writer,
    StorageKeyFactory? keyFactory,
  }) async {
    final request = _PendingPersistenceRequest.resolved(
      pending: _pendingRequest,
      state: state,
      deletedData: deletedData,
      server: server,
      writer: writer,
      keyFactory: keyFactory,
    );
    if (request == null) {
      return;
    }
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingRequest = null;

    final generation = _generation;
    await runExclusive(() => _write(request, generation));
  }

  Future<void> _write(
    _PendingPersistenceRequest request,
    int generation,
  ) async {
    // Cleared while this request was waiting for its turn: the account it was
    // taken for has been left or deleted.
    if (generation != _generation) {
      return;
    }
    if (!request.state.loginState.loggedIn ||
        request.state.loginState.username == null) {
      return;
    }

    final storageKey = request.keyFactory(
      request.state.loginState.username,
      request.server,
    );
    final identity = _PersistedStateIdentity.from(
      request.state,
      deletedData: request.deletedData,
    );
    if (_lastPersistedKey == storageKey &&
        _lastPersistedIdentity?.sameAs(identity) == true) {
      return;
    }

    final toPersist = identity.serialize();
    if (_lastPersistedKey == storageKey && _lastPersistedPayload == toPersist) {
      _lastPersistedIdentity = identity;
      return;
    }

    final stopwatch = Stopwatch()..start();
    diagnostics.values({'operation': 'save', 'data_source': 'local'});
    try {
      await request.writer(storageKey, toPersist);
    } catch (e, stack) {
      diagnostics.report(e, stack, DiagnosticError.storage);
      rethrow;
    }
    stopwatch.stop();
    if (generation == _generation) {
      _lastPersistedIdentity = identity;
      _lastPersistedKey = storageKey;
      _lastPersistedPayload = toPersist;
    }
    logPerformanceEvent(
      "state_persisted",
      <String, Object?>{
        "bytes": utf8.encode(toPersist).length,
        "elapsedMs": stopwatch.elapsedMilliseconds,
        "settingsOnly": identity.settingsOnly,
      },
    );
  }

  void clear() {
    _generation++;
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingRequest = null;
    _lastPersistedIdentity = null;
    _lastPersistedKey = null;
    _lastPersistedPayload = null;
  }
}

class _PendingPersistenceRequest {
  const _PendingPersistenceRequest({
    required this.state,
    required this.deletedData,
    required this.server,
    required this.writer,
    required this.keyFactory,
  });

  final AppState state;
  final bool deletedData;
  final String server;
  final PersistStateWriter writer;
  final StorageKeyFactory keyFactory;

  static _PendingPersistenceRequest? resolved({
    required _PendingPersistenceRequest? pending,
    AppState? state,
    bool? deletedData,
    String? server,
    PersistStateWriter? writer,
    StorageKeyFactory? keyFactory,
  }) {
    final resolvedState = state ?? pending?.state;
    final resolvedDeletedData = deletedData ?? pending?.deletedData;
    final resolvedServer = server ?? pending?.server;
    final resolvedWriter = writer ?? pending?.writer;
    final resolvedKeyFactory = keyFactory ?? pending?.keyFactory;
    if (resolvedState == null ||
        resolvedDeletedData == null ||
        resolvedServer == null ||
        resolvedWriter == null ||
        resolvedKeyFactory == null) {
      return null;
    }
    return _PendingPersistenceRequest(
      state: resolvedState,
      deletedData: resolvedDeletedData,
      server: resolvedServer,
      writer: resolvedWriter,
      keyFactory: resolvedKeyFactory,
    );
  }
}

class _PersistedStateIdentity {
  const _PersistedStateIdentity({
    required this.settingsOnly,
    required this.settingsState,
    this.dashboardState,
    this.notificationState,
    this.gradesState,
    this.absencesState,
    this.profileState,
    this.calendarState,
    this.certificateState,
    this.messagesState,
  });

  factory _PersistedStateIdentity.from(
    AppState state, {
    required bool deletedData,
  }) {
    final settingsOnly = state.settingsState.noDataSaving || deletedData;
    return _PersistedStateIdentity(
      settingsOnly: settingsOnly,
      settingsState: state.settingsState,
      dashboardState: settingsOnly ? null : state.dashboardState,
      notificationState: settingsOnly ? null : state.notificationState,
      gradesState: settingsOnly ? null : state.gradesState,
      absencesState: settingsOnly ? null : state.absencesState,
      profileState: settingsOnly ? null : state.profileState,
      calendarState: settingsOnly ? null : state.calendarState,
      certificateState: settingsOnly ? null : state.certificateState,
      messagesState: settingsOnly ? null : state.messagesState,
    );
  }

  final bool settingsOnly;
  final SettingsState settingsState;
  final DashboardState? dashboardState;
  final NotificationState? notificationState;
  final GradesState? gradesState;
  final AbsencesState? absencesState;
  final ProfileState? profileState;
  final CalendarState? calendarState;
  final CertificateState? certificateState;
  final MessagesState? messagesState;

  bool sameAs(_PersistedStateIdentity other) {
    return settingsOnly == other.settingsOnly &&
        identical(settingsState, other.settingsState) &&
        identical(dashboardState, other.dashboardState) &&
        identical(notificationState, other.notificationState) &&
        identical(gradesState, other.gradesState) &&
        identical(absencesState, other.absencesState) &&
        identical(profileState, other.profileState) &&
        identical(calendarState, other.calendarState) &&
        identical(certificateState, other.certificateState) &&
        identical(messagesState, other.messagesState);
  }

  String serialize() {
    if (settingsOnly) {
      return json.encode(serializers.serialize(settingsState));
    }
    return json.encode(
      serializers.serialize(
        AppState(
          (b) => b
            ..dashboardState.replace(dashboardState!)
            ..notificationState.replace(notificationState!)
            ..gradesState.replace(gradesState!)
            ..absencesState.replace(absencesState!)
            ..settingsState.replace(settingsState)
            ..profileState.replace(profileState!)
            ..calendarState.replace(calendarState!)
            ..certificateState.replace(certificateState!)
            ..messagesState.replace(messagesState!),
        ),
      ),
    );
  }
}
