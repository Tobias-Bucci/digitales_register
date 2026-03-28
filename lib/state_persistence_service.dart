import 'dart:async';
import 'dart:convert';

import 'package:dr/app_state.dart';
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
    await request.writer(storageKey, toPersist);
    stopwatch.stop();
    _lastPersistedIdentity = identity;
    _lastPersistedKey = storageKey;
    _lastPersistedPayload = toPersist;
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
