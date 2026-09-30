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

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dr/actions/absences_actions.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/actions/certificate_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/grades_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/actions/messages_actions.dart';
import 'package:dr/actions/notifications_actions.dart';
import 'package:dr/actions/profile_actions.dart';
import 'package:dr/actions/routing_actions.dart';
import 'package:dr/actions/save_pass_actions.dart';
import 'package:dr/actions/settings_actions.dart';
import 'package:dr/analytics_schema.dart';
import 'package:dr/analytics_school_ids.dart';
import 'package:dr/analytics_service.dart';
import 'package:dr/android_widget_service.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_language_controller.dart';
import 'package:dr/app_selectors.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:dr/container/calendar_container.dart';
import 'package:dr/container/certificate_container.dart';
import 'package:dr/container/grades_page_container.dart';
import 'package:dr/container/messages_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/data.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/main.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/tutorial/tutorial_service.dart';
import 'package:dr/ui/debug_page.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Action, Notification;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as image;
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mutex/mutex.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

part 'absences.dart';
part 'calendar.dart';
part 'certificate.dart';
part 'dashboard.dart';
part 'grades.dart';
part 'login.dart';
part 'messages.dart';
part 'notifications.dart';
part 'pass.dart';
part 'profile.dart';
part 'routing.dart';
part 'settings.dart';

late FlutterSecureStorage secureStorage;
final AppStatePersistenceService statePersistenceService =
    AppStatePersistenceService();
final AndroidWidgetSnapshotService androidWidgetSnapshotService =
    AndroidWidgetSnapshotService();

@visibleForTesting
Duration noInternetRetryInterval = const Duration(seconds: 5);

const Duration _dashboardCacheTtl = Duration(seconds: 45);
const Duration _notificationsCacheTtl = Duration(seconds: 30);
const Duration _profileCacheTtl = Duration(minutes: 5);
const Duration _calendarCacheTtl = Duration(minutes: 5);
const Duration _gradesCacheTtl = Duration(minutes: 1);
const Duration _messagesCacheTtl = Duration(minutes: 1);
const Duration _absencesCacheTtl = Duration(minutes: 2);
const Duration _certificateCacheTtl = Duration(minutes: 5);

Timer? _noInternetRetryTimer;
bool _noInternetRetryInFlight = false;
final Map<String, Future<void>> _inFlightLoads = <String, Future<void>>{};
final Map<String, UtcDateTime> _runtimeCacheTimes = <String, UtcDateTime>{};
final Set<String> _staleCacheKeys = <String>{};

String _dashboardCacheKey(bool future) => 'dashboard:$future';
String _calendarCacheKey(UtcDateTime monday) =>
    'calendar:${monday.stripTime().toIso8601String()}';

const String _notificationsCacheKey = 'notifications';
const String _profileCacheKey = 'profile';
const String _messagesCacheKey = 'messages';
const String _absencesCacheKey = 'absences';
const String _certificateCacheKey = 'certificate';

bool _isFresh(UtcDateTime? timestamp, Duration ttl) {
  if (timestamp == null) {
    diagnostics.update('cache_hit', false);
    return false;
  }
  final age = realNow.difference(timestamp);
  final fresh = !age.isNegative && age < ttl;
  diagnostics.update('cache_hit', fresh);
  if (fresh) {
    diagnostics.update('data_source', 'cache');
    diagnostics.safeLog('cache_hit');
  }
  return fresh;
}

bool _isRuntimeCacheFresh(String key, Duration ttl) {
  final fresh = _isFresh(_runtimeCacheTimes[key], ttl);
  const features = {
    'dashboard': 'homework',
    'calendar': 'timetable',
    'notifications': 'notifications',
    'messages': 'messages',
    'absences': 'absences',
    'profile': 'register',
    'certificate': 'register'
  };
  final feature = features[key.split(':').first];
  if (fresh && feature != null) {
    unawaited(AnalyticsService.product
        .event('cache_result', {'feature': feature, 'result': 'hit'}));
    unawaited(AnalyticsService.product.event(
        'data_source_used', {'feature': feature, 'data_source': 'cache'}));
  }
  return fresh;
}

void _markRuntimeCacheFresh(String key) {
  _runtimeCacheTimes[key] = realNow;
  _staleCacheKeys.remove(key);
}

void _markRuntimeCacheStale(String key) {
  _runtimeCacheTimes.remove(key);
  _staleCacheKeys.add(key);
}

bool _isCacheMarkedStale(String key) {
  return _staleCacheKeys.contains(key);
}

void _clearRuntimeCaches() {
  _inFlightLoads.clear();
  _runtimeCacheTimes.clear();
  _staleCacheKeys.clear();
  _authenticatedBytesInFlight.clear();
}

/// Invalidates only in-memory response caches. Used after demo data changes so
/// freshly generated local data is shown immediately.
void clearRuntimeCaches() => _clearRuntimeCaches();

Future<void> _runCoalescedLoad(String key, Future<void> Function() load) async {
  final existing = _inFlightLoads[key];
  if (existing != null) {
    await existing;
    return;
  }

  final future = Future<void>(() async {
    final product = AnalyticsService.product;
    final epoch = product.sessionEpoch;
    final stopwatch = Stopwatch()..start();
    final previousCacheTime = _runtimeCacheTimes[key];
    final prefix = key.split(':').first;
    const features = {
      'dashboard': 'homework',
      'calendar': 'timetable',
      'notifications': 'notifications',
      'messages': 'messages',
      'absences': 'absences',
      'profile': 'register',
      'certificate': 'register'
    };
    final feature = features[prefix];
    if (feature != null) {
      unawaited(product
          .event('cache_result', {'feature': feature, 'result': 'miss'}));
    }
    diagnostics.update('cache_hit', false);
    diagnostics.safeLog('cache_miss');
    try {
      await load();
      if (feature != null && product.isSession(epoch)) {
        unawaited(product.event('refresh_result', {
          'feature': feature,
          'result': _runtimeCacheTimes[key] != previousCacheTime
              ? 'success'
              : 'failed',
          'data_source': wrapper.demoMode ? 'local' : 'remote',
          'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
        }));
      }
    } catch (e, stack) {
      if (feature != null && product.isSession(epoch)) {
        unawaited(product.event('refresh_result', {
          'feature': feature,
          'result': 'failed',
          'data_source': 'unknown',
          'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
        }));
      }
      diagnostics.report(
          e,
          stack,
          e is ParseException || e is FormatException
              ? DiagnosticError.parser
              : key == _notificationsCacheKey
                  ? DiagnosticError.notification
                  : DiagnosticError.caught);
      rethrow;
    }
  });
  _inFlightLoads[key] = future;
  try {
    await future;
  } finally {
    if (identical(_inFlightLoads[key], future)) {
      final removed = _inFlightLoads.remove(key);
      assert(identical(removed, future));
    }
  }
}

@visibleForTesting
Wrapper wrapper = Wrapper();

bool isOffline() => wrapper.noInternet;

Future<String?> loadHomeworkSummaryHtml() async {
  final snapshot = await refreshHomeworkSummaryHtmlPayload();
  return snapshot?.payload;
}

Future<PagePayloadSnapshot<String>?> loadCachedHomeworkSummaryHtmlPayload() {
  return pagePayloadCacheService.load(
    _homeworkSummaryCacheKey(),
    parseStringPayload,
  );
}

Future<PagePayloadSnapshot<String>?> refreshHomeworkSummaryHtmlPayload() async {
  if (wrapper.noInternet) {
    return null;
  }
  // The official frontend sends a Unix timestamp in milliseconds here.
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final response = await wrapper.send(
    'vorstand/homework&klasse?_=$timestamp',
    method: 'GET',
  );
  final html = response?.toString();
  if (html == null) {
    return null;
  }
  final snapshot = PagePayloadSnapshot<String>.fromPayload(html);
  await pagePayloadCacheService.save(_homeworkSummaryCacheKey(), snapshot);
  return snapshot;
}

Future<List<CourseMaterialCourse>> loadCourseMaterials() async {
  final snapshot = await refreshCourseMaterialsPayload();
  if (snapshot == null) {
    throw const CourseMaterialsLoadException();
  }
  return courseMaterialCoursesFromPayload(snapshot.payload);
}

Future<PagePayloadSnapshot<List<Map<String, dynamic>>>?>
    loadCachedCourseMaterialsPayload() {
  return pagePayloadCacheService.load(
    _courseMaterialsCacheKey(),
    parseMapListPayload,
  );
}

Future<PagePayloadSnapshot<List<Map<String, dynamic>>>?>
    refreshCourseMaterialsPayload() async {
  final courses = await _loadCourseMaterialsRemote();
  final payload = courseMaterialCoursesToPayload(courses);
  final snapshot =
      PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(payload);
  await pagePayloadCacheService.save(_courseMaterialsCacheKey(), snapshot);
  return snapshot;
}

Future<List<CourseMaterialCourse>> _loadCourseMaterialsRemote() async {
  if (wrapper.demoMode) {
    return const <CourseMaterialCourse>[];
  }

  final sources = await _loadCurrentCourseMaterialSources();
  final courses = <CourseMaterialCourse>[];
  final seenCourseIds = <int>{};
  for (final source in sources) {
    final response = await wrapper.send(
      'api/courseContent/getCourse',
      args: <String, Object?>{
        'classId': source.classId,
        'subjectId': source.subjectId,
      },
    );
    final map = getMap(response);
    if (map == null) {
      continue;
    }
    final course = CourseMaterialCourse.fromJson(map, source);
    if (seenCourseIds.add(course.id)) {
      courses.add(course);
    }
  }
  courses.sort((a, b) => a.subjectName.compareTo(b.subjectName));
  return courses;
}

List<CourseMaterialCourse> courseMaterialCoursesFromPayload(
  List<Map<String, dynamic>> payload,
) {
  return payload.map(CourseMaterialCourse.fromCacheJson).toList()
    ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
}

List<Map<String, dynamic>> courseMaterialCoursesToPayload(
  List<CourseMaterialCourse> courses,
) {
  return courses
      .map((course) => Map<String, dynamic>.from(course.toJson()))
      .toList();
}

Future<List<CourseMaterialSource>> _loadCurrentCourseMaterialSources() async {
  final sources = <String, CourseMaterialSource>{};

  final monday = toMonday(now);
  dynamic response;
  for (final offset in <int>[0, -7, 7, -14, 14]) {
    response = await wrapper.send(
      'api/calendar/student',
      args: {
        'startDate': DateFormat('yyyy-MM-dd').format(
          monday.add(Duration(days: offset)),
        ),
      },
    );
    _addCourseMaterialSources(sources, response);
    if (sources.isNotEmpty) break;
  }

  final lessonSnapshot = await refreshClassRegisterLessonPayload();
  _addCourseMaterialSources(sources, lessonSnapshot?.payload);

  if (sources.isEmpty && response == null && lessonSnapshot == null) {
    throw const CourseMaterialsLoadException();
  }

  return sources.values.toList()
    ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
}

void _addCourseMaterialSources(
  Map<String, CourseMaterialSource> sources,
  dynamic root,
) {
  for (final source in courseMaterialSourcesFromPayload(root)) {
    sources.putIfAbsent(
      '${source.classId}|${source.subjectId}',
      () => source,
    );
  }
}

Future<bool> openCourseMaterialEntry(CourseMaterialEntry entry) async {
  if (entry.isLink) {
    final link = entry.link;
    if (link == null || link.trim().isEmpty) {
      return false;
    }
    return launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  if (await canOpenFile(entry.uniqueName)) {
    await openFile(entry.uniqueName);
    return true;
  }

  if (await _downloadCourseMaterialFile(entry)) {
    await openFile(entry.uniqueName);
    return true;
  }
  return false;
}

Future<bool> _downloadCourseMaterialFile(CourseMaterialEntry entry) async {
  await wrapper.ensureLoggedIn();

  final saveFile =
      File("${await _getAttachmentDownloadDirectory()}/${entry.uniqueName}");
  if (await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(entry.uniqueName);
    if (shouldOverwrite == null) {
      return false;
    }
    if (!shouldOverwrite) {
      return true;
    }
  }

  for (final candidate in _downloadCandidatesFor(entry)) {
    final bytes = await _downloadCourseMaterialCandidate(candidate);
    if (bytes != null) {
      await saveFile.parent.create(recursive: true);
      await saveFile.writeAsBytes(bytes);
      return true;
    }
  }

  if (await saveFile.exists()) {
    await saveFile.delete();
  }
  return false;
}

Future<List<int>?> _downloadCourseMaterialCandidate(
  _CourseMaterialDownloadCandidate candidate,
) async {
  Future<List<int>?> validate(
    Future<dio.Response<List<int>>> request,
  ) async {
    try {
      final response = await request;
      final bytes = response.data ?? const <int>[];
      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (response.statusCode != 200 ||
          bytes.isEmpty ||
          _looksLikeErrorDocument(bytes, contentType)) {
        return null;
      }
      return bytes;
    } catch (error) {
      log(
        'failed course material download candidate ${candidate.url}',
        error: error,
      );
      return null;
    }
  }

  return await validate(
        wrapper.dio.get<List<int>>(
          candidate.url,
          queryParameters: candidate.parameters,
          options: dio.Options(responseType: dio.ResponseType.bytes),
        ),
      ) ??
      await validate(
        wrapper.dio.post<List<int>>(
          candidate.url,
          data: candidate.parameters,
          options: dio.Options(responseType: dio.ResponseType.bytes),
        ),
      );
}

bool _looksLikeErrorDocument(List<int> bytes, String contentType) {
  final normalizedContentType = contentType.toLowerCase();
  if (normalizedContentType.contains('text/html') ||
      normalizedContentType.contains('application/json')) {
    return true;
  }
  final prefix = String.fromCharCodes(bytes.take(32)).trimLeft();
  return prefix.startsWith('<') || prefix.startsWith('{');
}

List<_CourseMaterialDownloadCandidate> _downloadCandidatesFor(
  CourseMaterialEntry entry,
) {
  return [
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}courseContent/downloadEntry',
      <String, dynamic>{
        'course': entry.courseContentId,
        'entry': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}courseContent/download',
      <String, dynamic>{
        'course': entry.courseContentId,
        'entry': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/download',
      <String, dynamic>{
        'course': entry.courseContentId,
        'entry': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/downloadEntry',
      <String, dynamic>{'entryId': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/downloadEntry',
      <String, dynamic>{'id': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/downloadEntry',
      <String, dynamic>{'courseContentEntryId': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/downloadFile',
      <String, dynamic>{'entryId': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/downloadFile',
      <String, dynamic>{
        'courseContentId': entry.courseContentId,
        'entryId': entry.id,
      },
    ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}api/courseContent/downloadFile',
        <String, dynamic>{'file': entry.file},
      ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}courseContent/downloadFile',
        <String, dynamic>{'file': entry.file},
      ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}courseContent/downloadFile/${Uri.encodeComponent(entry.file!)}',
        const <String, dynamic>{},
      ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}api/courseContent/downloadFile/${Uri.encodeComponent(entry.file!)}',
        const <String, dynamic>{},
      ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}courseContent/file/${Uri.encodeComponent(entry.file!)}',
        const <String, dynamic>{},
      ),
    if (entry.file != null)
      _CourseMaterialDownloadCandidate(
        '${wrapper.baseAddress}api/courseContent/file/${Uri.encodeComponent(entry.file!)}',
        const <String, dynamic>{},
      ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}courseContent/downloadEntry',
      <String, dynamic>{'entry': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{
        'courseContentId': entry.courseContentId,
        'entryId': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{'entryId': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{'courseContentEntryId': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{'id': entry.id},
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{
        'courseContentId': entry.courseContentId,
        'courseContentEntryId': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{
        'course': entry.courseContentId,
        'entry': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{
        'parentId': entry.courseContentId,
        'entryId': entry.id,
      },
    ),
    _CourseMaterialDownloadCandidate(
      '${wrapper.baseAddress}api/courseContent/courseContentDownloadEntry',
      <String, dynamic>{
        'parentId': entry.courseContentId,
        'submissionId': entry.id,
      },
    ),
  ];
}

class _CourseMaterialDownloadCandidate {
  const _CourseMaterialDownloadCandidate(this.url, this.parameters);

  final String url;
  final Map<String, dynamic> parameters;
}

Future<List<Map<String, dynamic>>?> loadClassRegisterLessonPayload() async {
  final snapshot = await refreshClassRegisterLessonPayload();
  return snapshot?.payload;
}

Future<ClassRegisterPayloadSnapshot?> loadCachedClassRegisterLessonPayload() {
  return classRegisterCacheService.load(_classRegisterCacheKey());
}

Future<ClassRegisterPayloadSnapshot?>
    refreshClassRegisterLessonPayload() async {
  if (wrapper.demoMode) {
    final snapshot = ClassRegisterPayloadSnapshot.fromPayload(
      const <Map<String, dynamic>>[],
    );
    await classRegisterCacheService.save(_classRegisterCacheKey(), snapshot);
    return snapshot;
  }
  await wrapper.send(
    'register/student?_=${DateTime.now().millisecondsSinceEpoch}',
    method: 'GET',
  );
  final response = await wrapper.send('api/lesson/student');
  final rawLessons = switch (response) {
    final List<dynamic> list => list,
    final Map<dynamic, dynamic> map when map['data'] is List =>
      map['data'] as List,
    final Map<dynamic, dynamic> map when map['lessons'] is List =>
      map['lessons'] as List,
    _ => null,
  };
  final payload = rawLessons
      ?.map((item) => getMap(item))
      .nonNulls
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  if (payload == null) {
    return null;
  }
  final snapshot = ClassRegisterPayloadSnapshot.fromPayload(payload);
  await classRegisterCacheService.save(_classRegisterCacheKey(), snapshot);
  return snapshot;
}

String _classRegisterCacheKey() {
  return 'classRegisterLessons:${getStorageKey(wrapper.user, wrapper.loginAddress)}';
}

String _courseMaterialsCacheKey() {
  return 'courseMaterials:${getStorageKey(wrapper.user, wrapper.loginAddress)}';
}

String userScopedStorageKey(String namespace) =>
    '$namespace:${getStorageKey(wrapper.user, wrapper.loginAddress)}';

String _homeworkSummaryCacheKey() {
  return 'homeworkSummary:${getStorageKey(wrapper.user, wrapper.loginAddress)}';
}

List<Middleware<AppState, AppStateBuilder, AppActions>> middleware({
  @visibleForTesting bool includeErrorMiddleware = true,
}) =>
    [
      if (includeErrorMiddleware) _errorMiddleware,
      _productAnalyticsMiddleware,
      _diagnosticsMiddleware,
      _saveStateMiddleware,
      (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
            ..add(LoginActionsNames.updateLogout, _tap)
            ..add(SettingsActionsNames.saveNoData, _saveNoData)
            ..add(AppActionsNames.deleteData, _deleteData)
            ..add(AppActionsNames.load, _load)
            ..add(AppActionsNames.start, _start)
            ..add(DashboardActionsNames.refresh, _refresh)
            ..add(AppActionsNames.refreshNoInternet, _refreshNoInternet)
            ..add(AppActionsNames.noInternet, _noInternet)
            ..add(LoginActionsNames.loggedIn, _loggedIn)
            ..add(AppActionsNames.restarted, _restarted)
            ..combine(_absencesMiddleware)
            ..combine(_calendarMiddleware)
            ..combine(_dashboardMiddleware)
            ..combine(_gradesMiddleware)
            ..combine(_loginMiddleware)
            ..combine(_notificationsMiddleware)
            ..combine(_passMiddleware)
            ..combine(routingMiddleware)
            ..combine(_certificateMiddleware)
            ..combine(_messagesMiddleware)
            ..combine(_profileMiddleware)
            ..combine(_settingsMiddleware))
          .build(),
    ];

NextActionHandler _errorMiddleware(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) =>
    (ActionHandler next) => (Action action) async {
          Future<void> handleError(dynamic e, StackTrace? trace) async {
            unawaited(AnalyticsService.product.event('error_presented', {
              'feature': 'unknown',
              'error_category': e is ParseException ? 'parsing' : 'unknown'
            }));
            diagnostics.report(
                e as Object, trace ?? StackTrace.empty, DiagnosticError.caught);
            log("Error caught by error middleware",
                error: e, stackTrace: trace);
            var stackTrace = trace;
            try {
              stackTrace ??= (e as dynamic).stackTrace as StackTrace?;
            } catch (e) {
              // we can't get a stack trace
            }
            var error = e.toString();
            if (e is! ParseException) {
              // ParseExceptions will already provide a more precise stack trace
              error += "\n\n$stackTrace";
            }
            error +=
                "\n\nApp Version: $appVersion\nOS: ${Platform.operatingSystem}\nServer: ${api.state.url}";
            await navigatorKey?.currentState?.push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) {
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor: Colors.red,
                      title: const Text("Fehler!"),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        Center(
                          child: ElevatedButton(
                            onPressed: () async {
                              await launchUrl(
                                Uri.parse(
                                  "https://docs.google.com/forms/d/e/1FAIpQLScTmSAZzj0bjwX_8IHVx9dVTTVrncJJpZo_D20dF7mrnU_zdQ/viewform?usp=sf_link&entry.1875208362=${Uri.encodeQueryComponent(error)}",
                                ),
                              );
                            },
                            child: const Text("Entwickler benachrichtigen"),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text("""
Ein Fehler ist aufgetreten.
${e is UnexpectedLogoutException ? """

Dieser Fehler kann auftreten, wenn zwei Geräte gleichzeitig auf dasselbe Konto zugreifen.
In diesem Fall kannst du versuchen, die App zu schließen und erneut zu öffnen.

Falls dies nicht zutrifft, bitte benachrichtige uns, damit wir diesen Fehler beheben können.""" : e is ParseException ? """

Beim Einlesen der Daten ist ein Fehler aufgetreten.
Bitte benachrichtige uns, damit wir diesen Fehler beheben können.
Bitte beachte, dass das Fehlerprotokoll möglicherweise private Daten enthält.""" : """

Eine Funktion wird eventuell noch nicht unterstützt.
Bitte benachrichtige uns, damit wir diesen Fehler beheben können:"""}

 --  Fehlerprotokoll: --

$error"""),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }

          if (action.name == AppActionsNames.error.name) {
            await handleError(action.payload, null);
          } else {
            try {
              await next(action);
            } catch (e, stackTrace) {
              await handleError(e, stackTrace);
            }
          }
        };

void _tap(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) {
  wrapper.interaction();
  // do not call next: this action is only to update the logout time
}

Future<void> _refreshNoInternet(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final noInternet = await wrapper.refreshNoInternet();
  await api.actions.noInternet(noInternet);
}

void _cancelNoInternetRetry() {
  _noInternetRetryTimer?.cancel();
  _noInternetRetryTimer = null;
}

void pauseNetworkRequests() {
  wrapper.pauseNetworkActivity();
  _cancelNoInternetRetry();
}

void resumeNetworkRequests() {
  wrapper.resumeNetworkActivity();
  if (wrapper.noInternet) {
    _scheduleNoInternetRetry(actions.refreshNoInternet.call);
  }
}

@visibleForTesting
void resetNoInternetRetryForTest() {
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  noInternetRetryInterval = const Duration(seconds: 5);
}

/// Resets middleware state which is intentionally kept for the app lifetime.
///
/// Tests share an isolate within a test file, so an unfinished coalesced load
/// from one test must never be allowed to affect the next one.
@visibleForTesting
void resetMiddlewareStateForTest() {
  resetNoInternetRetryForTest();
  _clearRuntimeCaches();
}

void _scheduleNoInternetRetry(Future<void> Function() refreshNoInternet) {
  if (!wrapper.isAppInForeground) return;
  if (_noInternetRetryTimer != null) {
    return;
  }
  _noInternetRetryTimer = Timer(noInternetRetryInterval, () {
    _noInternetRetryTimer = null;
    unawaited(_runNoInternetRetry(refreshNoInternet));
  });
}

Future<void> _runNoInternetRetry(
  Future<void> Function() refreshNoInternet,
) async {
  if (!wrapper.isAppInForeground || _noInternetRetryInFlight) {
    return;
  }
  _noInternetRetryInFlight = true;
  try {
    await refreshNoInternet();
  } finally {
    _noInternetRetryInFlight = false;
    if (wrapper.isAppInForeground && wrapper.noInternet) {
      _scheduleNoInternetRetry(refreshNoInternet);
    }
  }
}

Future<void> _noInternet(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<bool> action,
) async {
  final prevNoInternet = api.state.noInternet;
  await next(action);
  final noInternet = api.state.noInternet;
  if (prevNoInternet != noInternet) {
    if (noInternet) {
      _scheduleNoInternetRetry(api.actions.refreshNoInternet.call);
      showSnackBar(tr('offline.title'));
    } else {
      _cancelNoInternetRetry();
      showSnackBar(tr('offline.reconnected'));
      await api.actions.dashboardActions.refresh();
    }
  }
}

Future<void> _load(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  // By resetting the wrapper we clear all cookies.
  // However we don't want to reset the wrapper in tests
  if (wrapper is! Mock) {
    wrapper = Wrapper();
  }
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  _clearRuntimeCaches();
  statePersistenceService.clear();
  await androidWidgetSnapshotService.clear();
  wrapper.noInternet = api.state.noInternet;
  await next(action);
  if (!api.state.noInternet) _popAll();
  dynamic login;
  try {
    login = json.decode(await secureStorage.read(key: "login") ?? "{}");
  } catch (e) {
    login = const <Never, Never>{};
    showSnackBar(tr('error.savedDataLoadFailed'));
    log("Failed to load login credentials", error: e);
    try {
      await secureStorage.deleteAll();
    } catch (e) {
      showSnackBar(tr('error.reinstallSuggested'));
    }
  }

  final user = getString(login["user"]);
  final pass = getString(login["pass"]);
  final url = getString(login["url"]);
  final List<String> otherAccounts = List.from(
    (login["otherAccounts"] as List?)?.map<String>(
          (dynamic login) => login["user"] as String,
        ) ??
        <String>[],
  );
  await api.actions.loginActions.setAvailableAccounts(otherAccounts);
  if ((api.state.url != null && api.state.url != url) ||
      (api.state.loginState.username != null &&
          api.state.loginState.username != user)) {
    // TODO: Figure out when exactly we'd hit this code path and how to handle it better.
    await api.actions.savePassActions.delete();
    await api.actions.routingActions.showLogin();
  } else {
    if (user != null && pass != null) {
      await api.actions.loginActions.login(
        LoginPayload(
          (b) => b
            ..user = user
            ..pass = pass
            ..url = url
            ..fromStorage = true,
        ),
      );
    } else {
      await api.actions.routingActions.showLogin();
    }
  }

  // The first-run dialogs must be pushed after the login or dashboard route is
  // visible. On Windows, pushing them while the opaque splash is still the
  // only route can leave the dialog future pending without a visible dialog.
  if (navigatorKey?.currentState != null) {
    await WidgetsBinding.instance.endOfFrame;
  }
  await _checkShowUnmaintainedAlert();
  await _checkShowPrivacyConsentAlert();
}

Future<void> _refresh(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  _markRuntimeCacheStale(_notificationsCacheKey);
  await Future.wait([
    api.actions.dashboardActions.load(api.state.dashboardState.future),
    api.actions.notificationsActions.load(),
  ]);
}

Future<void> _loggedIn(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<LoggedInPayload> action,
) async {
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    statePersistenceService.clear();
  }
  if (action.payload.fromStorage) {
    // If we logged in with saved credentials password saving must be enabled.
    wrapper.safeMode = false;
  }
  if (!api.state.settingsState.noPasswordSaving &&
      !action.payload.fromStorage) {
    await api.actions.savePassActions.save();
  }
  deletedData = false;
  final key = getStorageKey(action.payload.username, wrapper.loginAddress);
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    log("loading state");
    final state = await _readFromStorage(key);
    if (state != null) {
      try {
        final serializedState = serializers.deserialize(
          json.decode(state) as Object,
        );
        if (serializedState is SettingsState) {
          final currentSettings = await _settingsForAccountLoad(
            legacySettings: serializedState,
          );
          await api.actions.mountAppState(
            api.state.rebuild(
              (b) => b..settingsState.replace(currentSettings),
            ),
          );
        } else if (serializedState is AppState) {
          final currentState = api.state;
          final currentSettings = await _settingsForAccountLoad(
            legacySettings: serializedState.settingsState,
          );
          await api.actions.mountAppState(
            serializedState.rebuild(
              (b) => b
                ..loginState.replace(currentState.loginState)
                ..noInternet = currentState.noInternet
                ..config = currentState.config?.toBuilder()
                ..dashboardState.future = true
                ..gradesState.semester.replace(
                      currentState.gradesState.semester == Semester.all
                          ? serializedState.gradesState.semester
                          : currentState.gradesState.semester,
                    )
                ..settingsState.replace(currentSettings),
            ),
          );
        }

        // next not at the beginning: bug fix (serialization)
        await next(action);

        await api.actions.settingsActions.saveNoPass(
          api.state.settingsState.noPasswordSaving,
        );
      } catch (e) {
        showSnackBar(tr('error.savedDataLoadFailed'));
        log("Failed to load data", error: e);
        await next(action);
      }
    } else {
      await next(action);
    }

    _popAll();
  } else {
    await next(action);
  }

  for (final callback in api.state.loginState.callAfterLogin) {
    callback();
  }
  if (!action.payload.offlineOnly) {
    await Future.wait([
      api.actions.dashboardActions.load(api.state.dashboardState.future),
      api.actions.notificationsActions.load(),
      api.actions.profileActions.load(),
    ]);
    unawaited(_ensureSubstituteTeacherHistoryLoaded(api));
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = navigatorKey?.currentContext;
    if (context != null && api.state.loginState.loggedIn) {
      unawaited(tutorialService.maybeOffer(context));
    }
  });
}

Future<SettingsState> _settingsForAccountLoad({
  required SettingsState legacySettings,
}) async {
  final globalSettings = await settingsPersistenceService.load();
  if (globalSettings != null) {
    return globalSettings;
  }
  await settingsPersistenceService.save(legacySettings);
  return legacySettings;
}

// This is to avoid saving data in an action right after deleting data,
// which would restore it.
@visibleForTesting
bool deletedData = false;

NextActionHandler _saveStateMiddleware(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) =>
    (ActionHandler next) => (Action action) async {
          final previousSettings = api.state.settingsState;
          await next(action);
          if (action.name != AppActionsNames.mountAppState.name &&
              api.state.settingsState != previousSettings) {
            await settingsPersistenceService.save(api.state.settingsState);
          }
          if (api.state.loginState.loggedIn &&
              api.state.loginState.username != null) {
            final immediately = action.name == AppActionsNames.saveState.name ||
                action.name == SettingsActionsNames.subjectNicks.name ||
                action.name ==
                    SettingsActionsNames.subjectNicksAutoGenerated.name ||
                action.name ==
                    SettingsActionsNames.showCalendarSubstituteBar.name;
            if (immediately) {
              await statePersistenceService.flush(
                state: api.state,
                deletedData: deletedData,
                server: wrapper.loginAddress,
                writer: _writeToStorage,
                keyFactory: getStorageKey,
              );
              await androidWidgetSnapshotService.flush(state: api.state);
            } else {
              statePersistenceService.schedule(
                state: api.state,
                deletedData: deletedData,
                server: wrapper.loginAddress,
                writer: _writeToStorage,
                keyFactory: getStorageKey,
              );
              androidWidgetSnapshotService.scheduleSync(api.state);
            }
          }
        };

String getStorageKey(String? user, String server) {
  // This is safe because the default Map in dart is a LinkedHashMap, which mantains
  // a stable ordering of its items.
  return json.encode({"username": user, "server_url": server});
}

String escapeKey(String key) {
  if (Platform.isWindows) {
    // secure_storage does not support certain characters on Windows.
    return key.replaceAll(RegExp(r'[\\/:*?"<>|]'), "_");
  }
  return key;
}

Future<void> _writeToStorage(String key, String txt) async {
  await secureStorage.write(key: escapeKey(key), value: txt);
}

Future<String?> _readFromStorage(String key) async {
  try {
    return await secureStorage.read(key: escapeKey(key));
  } catch (e) {
    try {
      await secureStorage.deleteAll();
    } catch (e) {
      showSnackBar(tr('error.reinstallSuggestedDetailed'));
    }
    return null;
  }
}

Future<void> _saveNoData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  await api.actions.saveState();
}

Future<void> _deleteData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  deletedData = true;
  await androidWidgetSnapshotService.clear();
  await api.actions.saveState();
}

Future<void> _restarted(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  if (api.state.loginState.loggedIn &&
      DateTime.now().difference(wrapper.lastInteraction).inMinutes > 3) {
    wrapper.interaction();
    final poppedAnything = _popAll();
    if (!poppedAnything) {
      // If we pop something the routeObserver will trigger a reload of the dasboard.
      // However, if we are on the dashboard already, we need to this here.
      await api.actions.dashboardActions.refresh();
    }
  }
}

Future<void> _start(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<Uri?> action,
) async {
  await api.actions.loginActions.clearAfterLoginCallbacks();
  if (action.payload != null) {
    await api.actions.setUrl(action.payload!.origin);
    final parameters = action.payload!.queryParameters;
    switch (parameters["semesterWechsel"]) {
      case "1":
        await api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.first),
        );
      case "2":
        await api.actions.loginActions.addAfterLoginCallback(
          () => api.actions.gradesActions.setSemester(Semester.second),
        );
    }
    switch (action.payload!.path) {
      case "":
      case "/":
      case "/v2/":
        break;
      case "/v2/login":
        if (parameters["resetmail"] == "true") {
          final email = parameters["email"];
          final token = parameters["token"];
          await api.actions.routingActions.showPassReset(
            ShowPassResetPayload(
              (b) => b
                ..token = token
                ..email = email,
            ),
          );
          return;
        }
        if (parameters["username"] != null) {
          await api.actions.loginActions.setUsername(parameters["username"]!);
        }
        if (parameters["redirect"] != null) {
          await redirectAfterLogin(
            parameters["redirect"]!.replaceFirst("#", ""),
            api,
          );
        }
      default:
        showSnackBar(tr('navigation.linkOpenFailed'));
    }
    await redirectAfterLogin(action.payload!.fragment, api);
  }
  final widgetDestination =
      await AndroidWidgetPlatformBridge().consumeLaunchDestination();
  if (widgetDestination != null) {
    await handleAndroidWidgetLaunchDestination(
      api.actions,
      widgetDestination,
      deferUntilLogin: true,
    );
  }
  await api.actions.load();
}

Future<void> redirectAfterLogin(
  String location,
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  switch (location) {
    case "":
    case "dashboard/student":
      break;
    case "student/absences":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showAbsences.call,
      );
    case "calendar/student":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCalendar.call,
      );
    case "student/subjects":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showGrades.call,
      );
    case "student/certificate":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showCertificate.call,
      );
    case "message/list":
      await api.actions.loginActions.addAfterLoginCallback(
        api.actions.routingActions.showMessages.call,
      );
    default:
      showSnackBar(tr('navigation.linkOpenFailed'));
  }
}

bool _popAll() {
  var poppedAnything = false;
  navigatorKey?.currentState?.popUntil((route) {
    if (!route.isFirst) {
      poppedAnything = true;
    }
    return route.isFirst;
  });
  nestedNavKey.currentState?.popUntil((route) {
    if (!route.isFirst) {
      poppedAnything = true;
    }
    return route.isFirst;
  });
  return poppedAnything;
}

Future<String>? _attachmentDownloadDirectoryFuture;
final Map<String, Future<Uint8List>> _authenticatedBytesInFlight =
    <String, Future<Uint8List>>{};

Future<String> _getAttachmentDownloadDirectory() {
  final cached = _attachmentDownloadDirectoryFuture;
  if (cached != null) {
    return cached;
  }

  // TODO: this remains to be tested on all platforms
  final future = () async {
    try {
      return (await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      ))!
          .first
          .path;
    } catch (_) {
      log(
        "failed to get download directory, falling back to application storage",
      );
      return (await getApplicationDocumentsDirectory()).path;
    }
  }();
  _attachmentDownloadDirectoryFuture = future;
  return future;
}

/// Downloads a file.
///
/// Returns true on success and false on a failure.
Future<bool> downloadFile(
  String url,
  String fileName,
  Map<String, dynamic> parameters,
) async {
  await wrapper.ensureLoggedIn();

  final saveFile = File("${await _getAttachmentDownloadDirectory()}/$fileName");
  var success = true;
  if (await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(fileName);
    if (shouldOverwrite == null) {
      return false;
    } else if (!shouldOverwrite) {
      return true;
    }
  }
  try {
    final result = await wrapper.dio.get<dynamic>(
      url,
      queryParameters: parameters,
      options: dio.Options(responseType: dio.ResponseType.stream),
    );
    await saveFile.parent.create(recursive: true);
    final sink = saveFile.openWrite();
    await sink.addStream((result.data as dio.ResponseBody).stream);
    await sink.flush();
    await sink.close();
    success = result.statusCode == 200;
  } catch (e) {
    log("failed to download file $url: $e");
    success = false;
  }

  if (!success && await saveFile.exists()) {
    // The download was not successful, we should not keep the empty file or whatever was downloaded.
    await saveFile.delete();
  }

  return success;
}

Future<Uint8List> fetchAuthenticatedBytes(String url) async {
  final existing = _authenticatedBytesInFlight[url];
  if (existing != null) {
    return existing;
  }
  final request = () async {
    await wrapper.ensureLoggedIn();
    final response = await wrapper.dio.get<List<int>>(
      url,
      options: dio.Options(responseType: dio.ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }();
  _authenticatedBytesInFlight[url] = request;
  try {
    return await request;
  } finally {
    if (identical(_authenticatedBytesInFlight[url], request)) {
      final removed = _authenticatedBytesInFlight.remove(url);
      assert(identical(removed, request));
    }
  }
}

Future<bool> canOpenFile(String fileName) async {
  return File("${await _getAttachmentDownloadDirectory()}/$fileName").exists();
}

Future<void> openFile(String fileName) async {
  log("opening file: $fileName");
  await OpenFile.open("${await _getAttachmentDownloadDirectory()}/$fileName");
}

Future<bool?> askShouldOverwriteFile(String fileName) {
  return navigatorKey!.currentState!.push<bool>(
    DialogRoute(
      builder: (context) {
        return InfoDialog(
          title: Text(tr('files.overwrite.title')),
          content: Text(
            tr('files.overwrite.body', args: {'fileName': fileName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('files.overwrite.keep')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('files.overwrite.redownload')),
            ),
          ],
        );
      },
      context: navigatorKey!.currentContext!,
    ),
  );
}

Future<void> _checkShowUnmaintainedAlert() async {
  final appDirectory = await getApplicationSupportDirectory();
  final file = File("${appDirectory.path}/unmaintainedAlertShown");
  if (await file.exists()) {
    return;
  }

  // A version of this app stored this file to the applications documents directory,
  // which is Documents/ for desktop. The directory was therefore fixed, but we should
  // still check for the file in the old location.
  final legacyFile = File(
    "${(await getApplicationDocumentsDirectory()).path}/unmaintainedAlertShown",
  );
  if (await legacyFile.exists()) {
    // create the file in the correct location
    await file.create(recursive: true);
    return;
  }

  await showDialog<void>(
    context: navigatorKey!.currentContext!,
    builder: (context) {
      return InfoDialog(
        title: Text(tr('about.welcome.title')),
        content: Text.rich(
          TextSpan(
            text: tr('about.welcome.bodyPrefix'),
            children: [
              TextSpan(
                text: "github.com/mideb/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse("https://github.com/miDeb/digitales_register"),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              TextSpan(text: tr('about.welcome.bodyMiddle')),
              TextSpan(
                text: "github.com/Tobias-Bucci/digitales_register",
                style: const TextStyle(color: Colors.blue),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(
                      Uri.parse(
                        "https://github.com/Tobias-Bucci/digitales_register",
                      ),
                      mode: LaunchMode.externalApplication,
                    );
                  },
              ),
              TextSpan(text: tr('about.welcome.bodySuffix')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('common.done')),
          ),
        ],
      );
    },
  );

  await file.create(recursive: true);
}

Future<void> _checkShowPrivacyConsentAlert() async {
  final context = navigatorKey?.currentContext;
  if (context == null || !context.mounted) {
    return;
  }

  await AnalyticsService.showPrivacyConsentDialog(context);
}

NextActionHandler _diagnosticsMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          final name = action.name;
          var feature = 'unknown';
          if (name.startsWith('Grades')) feature = 'grades';
          if (name.startsWith('Calendar')) feature = 'timetable';
          if (name.startsWith('Absences')) feature = 'absences';
          if (name.startsWith('Dashboard')) feature = 'homework';
          if (name.startsWith('Notifications')) feature = 'notifications';
          if (name.startsWith('Login')) feature = 'authentication';
          if (name.startsWith('Settings')) feature = 'settings';
          if (name.startsWith('Messages')) feature = 'messages';
          if (name.startsWith('Profile') || name.startsWith('Certificate')) {
            feature = 'register';
          }
          diagnostics.values(
              {'feature': feature, 'parser': feature, 'operation': 'load'});
          if (feature == 'grades') {
            diagnostics.update(
                'selected_filter',
                api.state.settingsState.typeSorted
                    ? 'type_sorted'
                    : 'date_sorted');
          }
          if (feature == 'homework') {
            diagnostics.update('selected_filter',
                api.state.dashboardState.future ? 'future' : 'past');
          }
          if (feature == 'authentication' && name == 'LoginActions-login') {
            diagnostics.safeLog('login_started');
          }
          if (name.endsWith('-loaded') && feature != 'unknown') {
            diagnostics.safeLog('parser_started');
          }
          if (feature == 'notifications') {
            diagnostics.update('notification_type', 'general');
          }
          try {
            await next(action);
          } catch (e, stack) {
            diagnostics.report(
                e,
                stack,
                e is ParseException || e is FormatException
                    ? DiagnosticError.parser
                    : feature == 'authentication'
                        ? DiagnosticError.login
                        : feature == 'notifications'
                            ? DiagnosticError.notification
                            : DiagnosticError.caught);
            rethrow;
          } finally {
            try {
              diagnostics.auth(
                  loggedIn: api.state.loginState.loggedIn,
                  demo: wrapper.demoMode);
              final screen = diagnostics.context['current_screen'];
              if (screen == 'grades') {
                diagnostics.update(
                    'selected_filter',
                    api.state.settingsState.typeSorted
                        ? 'type_sorted'
                        : 'date_sorted');
              } else if (screen == 'dashboard' || screen == 'homework') {
                diagnostics.update('selected_filter',
                    api.state.dashboardState.future ? 'future' : 'past');
              }
              diagnostics.values({
                'cache_enabled': !api.state.settingsState.noDataSaving,
                'locale': api.state.settingsState.languageCode,
                'semester':
                    api.state.gradesState.semester.n?.toString() ?? 'all',
                'notification_enabled': api.state.loginState.loggedIn,
                'network_available': !api.state.noInternet
              });
            } catch (_) {
              /* Optional context must never break action dispatch. */
            }
          }
        };

Future<void> refreshProductAnalyticsContext(AppState state) async {
  final product = AnalyticsService.product;
  if (!product.enabled) return;
  if (state.loginState.loggedIn && state.loginState.username != null) {
    if (state.url != wrapper.url || state.isDemo != wrapper.demoMode) return;
    // This local key is used only by encrypted identity storage, never Firebase.
    await product.identifyUser(
        jsonEncode([state.url, state.loginState.username]),
        demo: state.isDemo,
        schoolId: analyticsSchoolIdForUrl(state.url));
  }
  final year = schoolYearForDate(now);
  await product.updateUserProperties({
    'app_language': state.settingsState.languageCode == 'lld'
        ? 'ld'
        : state.settingsState.languageCode,
    'theme': themeController.themePreference.name,
    'build_flavor':
        const String.fromEnvironment('BUILD_FLAVOR', defaultValue: 'unknown'),
    'release_channel': kDebugMode
        ? 'debug'
        : const String.fromEnvironment('RELEASE_CHANNEL',
            defaultValue: 'unknown'),
    if (state.loginState.loggedIn) 'academic_year': '${year}_${year + 1}',
    if (state.loginState.loggedIn &&
        state.profileState.sendNotificationEmails != null)
      'notifications_enabled':
          state.profileState.sendNotificationEmails.toString(),
  });
}

Future<void> submitAcademicSummary(AppState state) async {
  final product = AnalyticsService.product;
  if (!product.identityReady ||
      state.isDemo ||
      !AnalyticsService.privacy.decision.academicStatsAllowed) {
    return;
  }
  final periods = _semestersFor(state.gradesState.semester)
      .map((semester) => semester.n.toString());
  if (!product.gradeOwnership
      .matches(jsonEncode([state.url, state.loginState.username]), periods)) {
    return;
  }
  final average = overallGradeAverage(state);
  if (average == null || !average.isFinite || average < 0 || average > 10) {
    return;
  }
  final year = schoolYearForDate(now);
  var grades = 0;
  var subjects = 0;
  for (final subject in state.gradesState.subjects) {
    if (state.settingsState.ignoreForGradesAverage
        .any((name) => name.toLowerCase() == subject.name.toLowerCase())) {
      continue;
    }
    final entries = subject.basicGrades(state.gradesState.semester);
    if (entries == null) {
      return; // Never contribute an incomplete semester snapshot.
    }
    var contributes = false;
    for (final grade in entries) {
      if (!grade.cancelled &&
          grade.grade != null &&
          grade.weightPercentage < 0) {
        return;
      }
      if (grade.cancelled ||
          grade.grade == null ||
          grade.weightPercentage <= 0) {
        continue;
      }
      if (schoolYearForDate(grade.date) != year ||
          grade.grade! < 0 ||
          grade.grade! > 1000) {
        return;
      }
      grades++;
      contributes = true;
    }
    if (contributes) subjects++;
  }
  if (grades == 0 || subjects == 0) return;
  await product.logAcademicSummary({
    'academic_year': '${year}_${year + 1}',
    'semester': state.gradesState.semester.n?.toString() ?? 'year',
    'grade_average_tenths': (average * 10).round(),
    'grade_count_bucket': AnalyticsSchema.gradeCount(grades),
    'subject_count_bucket': AnalyticsSchema.subjectCount(subjects),
    // No reliable scale metadata exists; grading_scale is deliberately omitted.
    'snapshot_schema_version': 1,
  });
}

NextActionHandler _productAnalyticsMiddleware(
        MiddlewareApi<AppState, AppStateBuilder, AppActions> api) =>
    (ActionHandler next) => (Action action) async {
          final product = AnalyticsService.product;
          final name = action.name;
          if (!product.enabled) {
            if ({
              'LoginActions-logout',
              'LoginActions-selectAccount',
              'LoginActions-addAccount',
              'LoginActions-removeCurrentAccount'
            }.contains(name)) {
              unawaited(product.clearIdentity());
            }
            await next(action);
            return;
          }
          final before = api.state;
          final stopwatch = Stopwatch()..start();
          const routes = <String, String>{
            'RoutingActions-showLogin': 'login',
            'RoutingActions-showProfile': 'register',
            'RoutingActions-showGrades': 'grades',
            'RoutingActions-showCalendar': 'timetable',
            'RoutingActions-showAbsences': 'absences',
            'RoutingActions-showNotifications': 'notifications',
            'RoutingActions-showSettings': 'settings',
            'RoutingActions-showMessages': 'messages',
            'RoutingActions-showCertificate': 'register',
            'RoutingActions-showGradesChart': 'grades',
            'RoutingActions-showGradeCalculator': 'grade_calculator',
          };
          const loads = <String, String>{
            'GradesActions-load': 'grades',
            'CalendarActions-load': 'timetable',
            'DashboardActions-load': 'homework',
            'AbsencesActions-load': 'absences',
            'NotificationsActions-load': 'notifications',
            'MessagesActions-load': 'messages',
          };
          final feature = loads[name];
          if (name == 'LoginActions-logout' ||
              name == 'LoginActions-selectAccount' ||
              name == 'LoginActions-addAccount' ||
              name == 'LoginActions-removeCurrentAccount') {
            final eventName = name == 'LoginActions-selectAccount'
                ? 'account_switch'
                : 'logout';
            final parameters = name == 'LoginActions-selectAccount'
                ? <String, Object>{}
                : {
                    'reason': name == 'LoginActions-logout'
                        ? 'user_action'
                        : 'account_switch'
                  };
            await product.clearIdentity();
            await product.event(eventName, parameters);
          }
          if (name == 'LoginActions-login') {
            await product.clearIdentity();
            final payload = action.payload as LoginPayload;
            unawaited(product.event('login_attempt', {
              'login_provider':
                  isDemoUser(url: payload.url, username: payload.user)
                      ? 'demo'
                      : 'school_api'
            }));
          }
          final epoch = product.sessionEpoch;
          if (routes.containsKey(name)) {
            unawaited(product.screenView(routes[name]!));
            unawaited(product.event('feature_opened',
                {'feature': routes[name]!, 'source': 'navigation'}));
          }
          if (feature != null) {
            unawaited(product.event('refresh_requested',
                {'feature': feature, 'source': 'automatic'}));
          }
          try {
            await next(action);
            if (!product.isSession(epoch)) return;
            if (name == 'LoginActions-loggedIn' ||
                name == 'AppActions-setUrl') {
              await refreshProductAnalyticsContext(api.state);
              if (name == 'LoginActions-loggedIn' &&
                  !(action.payload as LoggedInPayload).offlineOnly) {
                unawaited(product.event('login_result', {
                  'result': 'success',
                  'login_provider': api.state.isDemo ? 'demo' : 'school_api'
                }));
              }
            }
            if (name == 'LoginActions-loginFailed') {
              unawaited(product.event('login_result',
                  {'result': 'unknown', 'login_provider': 'school_api'}));
            }
            if (name == 'GradesActions-setSemester') {
              unawaited(product.event('semester_changed', {
                'semester':
                    api.state.gradesState.semester.n?.toString() ?? 'year'
              }));
            }
            if (name == 'SettingsActions-setLanguage') {
              await refreshProductAnalyticsContext(api.state);
              unawaited(product.event('language_changed', {
                'language': api.state.settingsState.languageCode == 'lld'
                    ? 'ld'
                    : api.state.settingsState.languageCode
              }));
            }
            if (name == 'SettingsActions-gradesTypeSorted') {
              unawaited(product.event('sort_changed', {
                'feature': 'grades',
                'sort_id': api.state.settingsState.typeSorted
                    ? 'type_sorted'
                    : 'date_sorted'
              }));
            }
            if (name == 'DashboardActions-switchFuture') {
              unawaited(product.event('filter_changed', {
                'feature': 'homework',
                'filter_id': api.state.dashboardState.future ? 'future' : 'past'
              }));
            }
            if (name == 'SettingsActions-calendarSyncEnabled') {
              unawaited(product.event('calendar_sync_changed', {
                'enabled': api.state.settingsState.calendarSyncEnabled ? 1 : 0
              }));
            }
            if (name == 'ProfileActions-loaded' ||
                name == 'ProfileActions-sendNotificationEmails') {
              await refreshProductAnalyticsContext(api.state);
            }
            if (name == 'ProfileActions-sendNotificationEmails') {
              unawaited(product.event('notification_settings_changed', {
                'enabled': api.state.profileState.sendNotificationEmails == true
                    ? 1
                    : 0
              }));
            }
            if (name == 'CalendarActions-setCurrentMonday') {
              unawaited(product.event('feature_action',
                  {'feature': 'timetable', 'action': 'change_day'}));
            }
            if (name == 'RoutingActions-showGradesChart') {
              unawaited(product.event(
                  'tab_changed', {'feature': 'grades', 'tab_id': 'chart'}));
              unawaited(product.event('feature_action',
                  {'feature': 'grades', 'action': 'change_view'}));
            }
            if (name == 'AppActions-noInternet') {
              unawaited(product.event('error_presented',
                  {'feature': 'unknown', 'error_category': 'offline'}));
            }
            if (name == 'NotificationsActions-delete' ||
                name == 'NotificationsActions-deleteAll') {
              unawaited(product.event('feature_action',
                  {'feature': 'notifications', 'action': 'mark_read'}));
            }
            if (name == 'DashboardActions-toggleDone') {
              unawaited(product.event('feature_action',
                  {'feature': 'homework', 'action': 'toggle_done'}));
            }
            if (before.isDemo != api.state.isDemo) {
              unawaited(product.event(
                  'demo_mode_changed', {'enabled': api.state.isDemo ? 1 : 0}));
            }
            if (name == 'GradesActions-loaded' ||
                name == 'GradesActions-setSemester' ||
                name == 'SettingsActions-ignoreSubjectsForAverage') {
              await submitAcademicSummary(api.state);
            }
            if (feature != null) {
              // Dispatcher completion is not always remote completion in this legacy app.
              // Only cache/offline outcomes are asserted here; loaded actions cover remote success.
              if (before.noInternet) {
                unawaited(product.event('offline_usage',
                    {'feature': feature, 'action': 'opened_cached_data'}));
              }
            }
            const loaded = {
              'GradesActions-loaded': 'grades',
              'CalendarActions-loaded': 'timetable',
              'DashboardActions-loaded': 'homework',
              'AbsencesActions-loaded': 'absences',
              'NotificationsActions-loaded': 'notifications',
              'MessagesActions-loaded': 'messages'
            };
            if (loaded.containsKey(name)) {
              unawaited(product.event('data_source_used', {
                'feature': loaded[name]!,
                'data_source': api.state.isDemo ? 'local' : 'remote'
              }));
            }
          } catch (_) {
            if (feature != null) {
              unawaited(product.event('refresh_result', {
                'feature': feature,
                'result': 'failed',
                'data_source': 'unknown',
                'duration_bucket': AnalyticsSchema.duration(stopwatch.elapsed)
              }));
            }
            rethrow;
          }
        };
