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
import 'dart:io';
import 'dart:typed_data';

import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dr/account_scope.dart';
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
import 'package:dr/assessment_attachments.dart';
import 'package:dr/calendar_load_log.dart';
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
import 'package:dr/local_data_inventory.dart';
import 'package:dr/main.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/privacy_log.dart';
import 'package:dr/school_api_endpoints.dart';
import 'package:dr/school_notification_service.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/state_persistence_service.dart';
import 'package:dr/stored_login.dart';
import 'package:dr/study_data_migration.dart';
import 'package:dr/study_data_service.dart';
import 'package:dr/theme_controller.dart';
import 'package:dr/ui/debug_page.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/school_notification_opt_in.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode;
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
part 'local_data.dart';
part 'login.dart';
part 'messages.dart';
part 'notifications.dart';
part 'pass.dart';
part 'profile.dart';
part 'routing.dart';
part 'session.dart';
part 'settings.dart';

late FlutterSecureStorage secureStorage;
final AppStatePersistenceService statePersistenceService =
    AppStatePersistenceService();
final StudyDataService studyDataService =
    StudyDataService(storage: () => secureStorage);
final StudyDataMigration studyDataMigration = StudyDataMigration(
  service: studyDataService,
  settings: settingsPersistenceService,
);

/// Changes whenever the older learning notes that belong to no account are
/// assigned, discarded or found, so that what shows them can ask again.
final ValueNotifier<int> legacyStudyDataRevision = ValueNotifier<int>(0);
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

/// Marks [key] fresh for the session that loaded it. A load that finishes
/// after the app has switched account must not make the new account's cache
/// look fresh.
void _markRuntimeCacheFresh(String key, _Session session) {
  if (!session.isCurrent) return;
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
  _workingCourseMaterialCandidate = null;
  // A new session (or regenerated demo data) starts on an unknown server-side
  // semester, so the next grades request has to switch explicitly.
  _gradesLock.reset();
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
    } on StaleSessionException {
      // The account was left while loading: nothing to report or to retry.
      return;
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

/// Installs a fresh [Wrapper] (which also starts without cookies).
///
/// The old instance is retired first: its refresh timer, requests and
/// credentials must not outlive the session the app has left. With
/// [keepMock], tests that injected a mock keep it.
void _replaceWrapper({bool keepMock = false}) {
  // Everything started before this point belongs to a session we left, even
  // when a test keeps its mock wrapper.
  _sessionGeneration++;
  if (keepMock && wrapper is Mock) return;
  wrapper.retire();
  wrapper = Wrapper();
}

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
  // The cache key belongs to the account that asks, not to whoever is signed
  // in when the answer arrives.
  final session = _Session.capture(withStorageKey: true);
  try {
    // The official frontend sends a Unix timestamp in milliseconds here.
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final response = await session.send(
      'vorstand/homework&klasse?_=$timestamp',
      method: 'GET',
    );
    final html = response?.toString();
    if (html == null) {
      return null;
    }
    final snapshot = PagePayloadSnapshot<String>.fromPayload(html);
    await pagePayloadCacheService.save(
        _homeworkSummaryCacheKey(session), snapshot);
    return snapshot;
  } on StaleSessionException {
    return null;
  }
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

/// Loads every course and replaces the cached snapshot.
///
/// Throws [CourseMaterialsIncompleteException] instead of saving when a
/// course could not be loaded, so a partial result never replaces the last
/// complete snapshot.
Future<PagePayloadSnapshot<List<Map<String, dynamic>>>?>
    refreshCourseMaterialsPayload() async {
  final session = _Session.capture(withStorageKey: true);
  try {
    final courses = await _loadCourseMaterialsRemote(session);
    final payload = courseMaterialCoursesToPayload(courses);
    final snapshot =
        PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(payload);
    session.ensureCurrent();
    await pagePayloadCacheService.save(
        _courseMaterialsCacheKey(session), snapshot);
    return snapshot;
  } on StaleSessionException {
    return null;
  }
}

Future<List<CourseMaterialCourse>> _loadCourseMaterialsRemote(
    _Session session) async {
  if (session.wrapper.demoMode) {
    return const <CourseMaterialCourse>[];
  }

  final discovery = await _loadCurrentCourseMaterialSources(session);
  if (!discovery.complete) {
    // A failed discovery request only matters when it may have hidden a
    // course of the last snapshot.
    final found = {
      for (final source in discovery.sources)
        '${source.classId}|${source.subjectId}',
    };
    final cached = await pagePayloadCacheService.load(
      _courseMaterialsCacheKey(session),
      parseMapListPayload,
    );
    final lostKnownCourse = cached != null &&
        courseMaterialCoursesFromPayload(cached.payload).any(
          (course) => !found.contains('${course.classId}|${course.subjectId}'),
        );
    if (lostKnownCourse) {
      throw const CourseMaterialsIncompleteException();
    }
  }
  final courses = <CourseMaterialCourse>[];
  final seenCourseIds = <int>{};
  for (final source in discovery.sources) {
    final response = await session.send(
      'api/courseContent/getCourse',
      args: <String, Object?>{
        'classId': source.classId,
        'subjectId': source.subjectId,
      },
    );
    // A failed request: the course is unknown, not absent. Malformed
    // responses make getMap throw.
    final map =
        getMap(response) ?? (throw const CourseMaterialsIncompleteException());
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

/// The class/subject pairs found for the course materials. [complete] is
/// false when a discovery request failed, so pairs may be missing.
Future<({List<CourseMaterialSource> sources, bool complete})>
    _loadCurrentCourseMaterialSources(_Session session) async {
  final sources = <String, CourseMaterialSource>{};

  final monday = toMonday(now);
  dynamic response;
  var complete = true;
  for (final offset in <int>[0, -7, 7, -14, 14]) {
    response = await session.send(
      'api/calendar/student',
      args: {
        'startDate': DateFormat('yyyy-MM-dd').format(
          monday.add(Duration(days: offset)),
        ),
      },
    );
    if (response == null) complete = false;
    _addCourseMaterialSources(sources, response);
    if (sources.isNotEmpty) break;
  }

  final lessonSnapshot = await _refreshClassRegisterLessonPayload(session);
  if (lessonSnapshot == null) complete = false;
  _addCourseMaterialSources(sources, lessonSnapshot?.payload);

  if (sources.isEmpty && response == null && lessonSnapshot == null) {
    throw const CourseMaterialsLoadException();
  }

  return (
    sources: sources.values.toList()
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName)),
    complete: complete,
  );
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

@visibleForTesting
Future<String> Function()? attachmentDownloadDirectoryOverride;

@visibleForTesting
Future<OpenResult> Function(String)? courseMaterialFileOpenerOverride;

@visibleForTesting
TargetPlatform? courseMaterialPlatformOverride;

/// Replaces [OpenFile.open] for downloaded attachments in tests.
@visibleForTesting
Future<OpenResult> Function(String)? downloadedFileOpenerOverride;

/// Overrides whether local course material diagnostics are printed; they
/// are only printed in debug builds.
@visibleForTesting
bool? courseMaterialDebugLogsOverride;

// Local desktop debug console only. Use a closed set of categorical fields:
// never document names, file labels, local paths, requests, headers or
// exception messages, which may contain personal data or account names.
void _materialLog(String stage, Map<String, Object?> fields) {
  if (!(courseMaterialDebugLogsOverride ?? kDebugMode)) return;
  if (Platform.isWindows || Platform.isLinux) {
    debugPrint('[CourseMaterial] ${jsonEncode({'stage': stage, ...fields})}');
  }
}

/// How [openCourseMaterialEntryWithStatus] ended.
enum CourseMaterialOpenResult {
  opened,

  /// A newer version exists on the server but could not be downloaded, so
  /// the previously saved version was opened.
  openedOutdated,
  failed,
}

Future<bool> openCourseMaterialEntry(CourseMaterialEntry entry) async {
  return await openCourseMaterialEntryWithStatus(entry) !=
      CourseMaterialOpenResult.failed;
}

Future<CourseMaterialOpenResult> openCourseMaterialEntryWithStatus(
    CourseMaterialEntry entry) async {
  const failed = CourseMaterialOpenResult.failed;
  var stage = 'entry';
  // Files and their versions belong to the account that opens the document.
  final session = _Session.capture();
  try {
    _materialLog(stage, {
      'id': entry.id,
      'courseContentId': entry.courseContentId,
      'type': entry.type,
      'hasFile': entry.file != null,
    });
    if (entry.isLink) {
      final link = entry.link;
      if (link == null || link.trim().isEmpty) {
        return failed;
      }
      return await launchUrl(Uri.parse(link),
              mode: LaunchMode.externalApplication)
          ? CourseMaterialOpenResult.opened
          : failed;
    }

    stage = 'local_check';
    final local = await _canOpenFileIn(session, entry.uniqueName);
    final current =
        local && await _isCurrentCourseMaterialVersion(session, entry);
    _materialLog(stage, {'exists': local, 'current': current});
    var outdated = false;
    if (!current) {
      stage = 'download';
      if (!await _downloadCourseMaterialFile(session, entry,
          replaceOutdated: local)) {
        // A failed update keeps the previously saved file usable.
        if (!local || !await _canOpenFileIn(session, entry.uniqueName)) {
          return failed;
        }
        outdated = true;
      }
    }
    stage = 'open';
    final file = await _attachmentFile(entry.uniqueName, session.scope);
    if (file == null) return failed;
    final path = file.path;
    final exists = await file.exists();
    _materialLog(stage, {'exists': exists});
    if (!exists) return failed;
    // Every platform reports whether a viewer opened the file: on Android
    // and iOS a missing app or an error must not pass for success either.
    final result =
        await (courseMaterialFileOpenerOverride ?? OpenFile.open)(path);
    final platform = courseMaterialPlatformOverride ?? defaultTargetPlatform;
    if (platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux) {
      _materialLog('open_result', {
        'result': result.type.name,
        if (const {
          'Opening cancelled',
          'Portal could not open file',
          'File opening request timed out',
          'Invalid portal response',
        }.contains(result.message))
          'reason': result.message,
      });
    }
    if (result.type != ResultType.done) return failed;
    return outdated
        ? CourseMaterialOpenResult.openedOutdated
        : CourseMaterialOpenResult.opened;
  } catch (error) {
    _materialLog(
        'failed', {'at': stage, 'errorType': error.runtimeType.toString()});
    return failed;
  }
}

const _courseMaterialVersionsKey = 'courseMaterialFileVersions';

/// Where the saved versions of an account's course files are kept. Each
/// account has its own list, next to its own folder of files.
String _courseMaterialVersionsKeyFor(AccountScope scope) =>
    '$_courseMaterialVersionsKey:${scope.fileId}';

/// The [CourseMaterialEntry.contentVersion] of every saved course file of the
/// account, by [CourseMaterialEntry.uniqueName].
Future<Map<String, dynamic>> _loadCourseMaterialVersions(
    AccountScope scope) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_courseMaterialVersionsKeyFor(scope));
  final decoded = raw == null ? null : jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
}

/// Whether the saved file of [entry] is the version the server lists. Files
/// saved without a recorded version are revalidated once.
Future<bool> _isCurrentCourseMaterialVersion(
    _Session session, CourseMaterialEntry entry) async {
  try {
    final versions = await _loadCourseMaterialVersions(session.scope);
    return versions[entry.uniqueName] == entry.contentVersion;
  } catch (_) {
    privacyLog('technical_operation');
    return false;
  }
}

/// Records the version of [entry] as saved for the account signed in now.
@visibleForTesting
Future<void> rememberCourseMaterialVersion(CourseMaterialEntry entry) =>
    _rememberCourseMaterialVersion(_Session.capture(), entry);

Future<void> _rememberCourseMaterialVersion(
    _Session session, CourseMaterialEntry entry) async {
  try {
    final scope = session.scope;
    final versions = await _loadCourseMaterialVersions(scope);
    versions[entry.uniqueName] = entry.contentVersion;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _courseMaterialVersionsKeyFor(scope), jsonEncode(versions));
  } catch (_) {
    // The file is revalidated on the next open.
    privacyLog('technical_operation');
  }
}

/// Downloads [entry] into its saved file.
///
/// With [replaceOutdated], an existing file is a previous version of the same
/// document: it is replaced without asking, and only once the new content
/// has been validated, so a failed update keeps it.
Future<bool> _downloadCourseMaterialFile(
  _Session session,
  CourseMaterialEntry entry, {
  bool replaceOutdated = false,
}) async {
  // The request goes out on the session that asked, and a document is only
  // saved while the app is still in that session.
  final loggedIn = await session.wrapper.ensureLoggedIn();
  session.ensureCurrent();
  _materialLog('authentication', {'loggedIn': loggedIn});
  if (!loggedIn) {
    return false;
  }

  final saveFile = await _attachmentFile(entry.uniqueName, session.scope);
  if (saveFile == null) {
    return false;
  }
  _materialLog('destination', {'exists': await saveFile.exists()});
  if (!replaceOutdated && await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(entry.uniqueName);
    session.ensureCurrent();
    if (shouldOverwrite == null) {
      return false;
    }
    if (!shouldOverwrite) {
      return true;
    }
  }

  final candidates = _downloadCandidatesFor(session, entry);
  // Try the endpoint shape that worked last first, so a known server needs a
  // single request instead of probing every historical variant.
  final known = _workingCourseMaterialCandidate;
  final order = [
    if (known != null && known < candidates.length) known,
    for (var i = 0; i < candidates.length; i++)
      if (i != known) i,
  ];
  for (final index in order) {
    final result = await _downloadCourseMaterialCandidate(
        session, candidates[index], entry.uniqueName);
    session.ensureCurrent();
    final bytes = result.bytes;
    if (bytes != null) {
      _workingCourseMaterialCandidate = index;
      await _writeFileAtomically(saveFile, bytes);
      await _rememberCourseMaterialVersion(session, entry);
      _materialLog('saved', {
        'saved': true,
        'bytes': await saveFile.length(),
      });
      return true;
    }
    if (result.stop) break;
  }

  if (!replaceOutdated && await saveFile.exists()) {
    await saveFile.delete();
  }
  _materialLog('download_failed', {'saved': false});
  return false;
}

/// Index into [_downloadCandidatesFor] of the endpoint that last delivered
/// a document in this session.
int? _workingCourseMaterialCandidate;

/// Requests one endpoint candidate with GET and then POST.
///
/// [stop] is set when probing further endpoints cannot help: the session
/// returned the login page or the network failed.
Future<({List<int>? bytes, bool stop})> _downloadCourseMaterialCandidate(
  _Session session,
  _CourseMaterialDownloadCandidate candidate,
  String fileName,
) async {
  var stop = false;
  Future<List<int>?> validate(
    String method,
  ) async {
    // The endpoint path excludes host, userinfo, query and fragments.
    final endpoint = Uri.parse(candidate.url);
    final segments = endpoint.pathSegments;
    final hasFileSegment = segments.length > 1 &&
        const {'file', 'downloadFile'}.contains(segments[segments.length - 2]);
    _materialLog('request', {
      'endpoint': hasFileSegment
          ? '/${segments.take(segments.length - 1).join('/')}/[file]'
          : endpoint.path,
      'method': method,
      'parameters': candidate.parameters.keys.toList(),
    });
    void logResponse(dio.Response<List<int>> response) {
      _materialLog('response', {
        'method': method,
        'status': response.statusCode,
        'contentType': response.headers.value(HttpHeaders.contentTypeHeader),
        'bytes': response.data?.length ?? 0,
        'redirected': response.redirects.isNotEmpty,
      });
    }

    try {
      final response = method == 'GET'
          ? await session.wrapper.dio.get<List<int>>(candidate.url,
              queryParameters: candidate.parameters,
              options: dio.Options(responseType: dio.ResponseType.bytes))
          : await session.wrapper.dio.post<List<int>>(candidate.url,
              data: candidate.parameters,
              options: dio.Options(responseType: dio.ResponseType.bytes));
      logResponse(response);
      final bytes = response.data ?? const <int>[];
      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final validation = response.statusCode != 200
          ? null
          : validateDownloadedDocument(bytes, contentType, fileName);
      if (validation == DownloadValidation.valid) {
        return bytes;
      }
      if (validation == DownloadValidation.loginPage) {
        stop = true;
      }
      _materialLog('rejected', {
        'method': method,
        'reason': switch (validation) {
          null => 'http_status',
          DownloadValidation.loginPage => 'login_page',
          _ => bytes.isEmpty ? 'empty_body' : 'error_document',
        },
      });
      return null;
    } catch (error) {
      if (error is dio.DioException) {
        // Without a server response, other endpoints fail the same way.
        stop = error.type != dio.DioExceptionType.badResponse;
        final response = error.response;
        _materialLog('request_failed', {
          'method': method,
          'errorType': error.type.name,
          'status': response?.statusCode,
          'contentType': response?.headers.value(HttpHeaders.contentTypeHeader),
          'bytes': response?.data is List<int>
              ? (response!.data as List<int>).length
              : 0,
        });
      } else {
        _materialLog('request_failed',
            {'method': method, 'errorType': error.runtimeType.toString()});
      }
      privacyLog('technical_operation');
      return null;
    }
  }

  final bytes = await validate('GET');
  if (bytes != null || stop) return (bytes: bytes, stop: stop);
  return (bytes: await validate('POST'), stop: stop);
}

List<_CourseMaterialDownloadCandidate> _downloadCandidatesFor(
  _Session session,
  CourseMaterialEntry entry,
) {
  final wrapper = session.wrapper;
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
  try {
    return await _refreshClassRegisterLessonPayload(
        _Session.capture(withStorageKey: true));
  } on StaleSessionException {
    return null;
  }
}

Future<ClassRegisterPayloadSnapshot?> _refreshClassRegisterLessonPayload(
    _Session session) async {
  if (session.wrapper.demoMode) {
    final snapshot = ClassRegisterPayloadSnapshot.fromPayload(
      const <Map<String, dynamic>>[],
    );
    await classRegisterCacheService.save(
        _classRegisterCacheKey(session), snapshot);
    return snapshot;
  }
  await session.send(
    'register/student?_=${DateTime.now().millisecondsSinceEpoch}',
    method: 'GET',
  );
  final response = await session.send('api/lesson/student');
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
  await classRegisterCacheService.save(
      _classRegisterCacheKey(session), snapshot);
  return snapshot;
}

/// Cache keys use the account of [session] when given (a load in progress),
/// otherwise whoever is signed in now (a plain read).
String _storageKeyFor(_Session? session) =>
    session?.storageKey ?? getStorageKey(wrapper.user, wrapper.loginAddress);

String _classRegisterCacheKey([_Session? session]) =>
    'classRegisterLessons:${_storageKeyFor(session)}';

String _courseMaterialsCacheKey([_Session? session]) =>
    'courseMaterials:${_storageKeyFor(session)}';

String userScopedStorageKey(String namespace) =>
    '$namespace:${getStorageKey(wrapper.user, wrapper.loginAddress)}';

String _homeworkSummaryCacheKey([_Session? session]) =>
    'homeworkSummary:${_storageKeyFor(session)}';

List<Middleware<AppState, AppStateBuilder, AppActions>> middleware({
  @visibleForTesting bool includeErrorMiddleware = true,
}) =>
    [
      if (includeErrorMiddleware) _errorMiddleware,
      _productAnalyticsMiddleware,
      _diagnosticsMiddleware,
      _saveStateMiddleware,
      _staleSessionMiddleware,
      (MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
            ..add(LoginActionsNames.updateLogout, _tap)
            ..add(SettingsActionsNames.saveNoData, _saveNoData)
            ..add(AppActionsNames.deleteData, _deleteData)
            ..add(AppActionsNames.assignLegacyStudyData, _assignLegacyStudyData)
            ..add(AppActionsNames.discardLegacyStudyData,
                _discardLegacyStudyData)
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
            privacyLog('technical_operation');
            await navigatorKey?.currentState?.push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (context) {
                  return Scaffold(
                    appBar: AppBar(
                      backgroundColor: Colors.red,
                      title: Text(context.l10n.text('error.title')),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: <Widget>[
                        Center(
                          child: ElevatedButton(
                            onPressed: () async {
                              await launchUrl(
                                Uri.parse(
                                  "https://docs.google.com/forms/d/e/1FAIpQLScTmSAZzj0bjwX_8IHVx9dVTTVrncJJpZo_D20dF7mrnU_zdQ/viewform",
                                ),
                              );
                            },
                            child: Text(context.l10n.text('error.contact')),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                              context.l10n.text(e is UnexpectedLogoutException
                                  ? 'error.session'
                                  : e is ParseException
                                      ? 'error.parse'
                                      : 'error.generic')),
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
  schoolNotificationStartupReady.value = false;
  _unreadableStorageKeys.clear();
  localDataPolicy.reset();
  _studyDataScope = null;
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
  await _loadAccounts(api, beforeLoad: () => next(action));
}

Future<void> _loadAccounts(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api, {
  FutureOr<void> Function()? beforeLoad,
  bool explicitSelection = false,
}) async {
  // By resetting the wrapper we clear all cookies.
  // However we don't want to reset the wrapper in tests
  _replaceWrapper(keepMock: true);
  _cancelNoInternetRetry();
  _noInternetRetryInFlight = false;
  _clearRuntimeCaches();
  statePersistenceService.clear();
  await androidWidgetSnapshotService.clear();
  wrapper.noInternet = api.state.noInternet;
  await beforeLoad?.call();
  if (!api.state.noInternet) _popAll();
  Map<String, dynamic> login = <String, dynamic>{};
  try {
    final raw = await secureStorage.read(key: 'login');
    login = decodeStoredLogin(raw);
    if (raw != null && json.encode(login) != raw) {
      await secureStorage.write(key: 'login', value: json.encode(login));
    }
  } catch (e, stack) {
    diagnostics.report(e, stack, DiagnosticError.storage);
    // A failed repair must not discard the valid accounts already recovered.
    showSnackBar(tr('error.savedDataLoadFailed'));
  }

  final user = getString(login["user"]);
  final savedForNotificationMigration = [
    login,
    ...(login['otherAccounts'] as List? ?? []).whereType<Map>()
  ];
  unawaited(schoolNotificationOperation(
      () => schoolNotifications.migrateLegacyDecisions([
            for (final saved in savedForNotificationMigration)
              if (saved['url'] is String && saved['user'] is String)
                (saved['url'] as String, saved['user'] as String),
          ])));
  final pass = getString(login["pass"]);
  final url = getString(login["url"]);
  final hasPrimaryAccount = user != null && pass != null && url != null;
  final shouldSignIn =
      explicitSelection || !api.state.settingsState.noPasswordSaving;
  final List<String> otherAccounts = List.from(
    (login["otherAccounts"] as List?)?.map<String>(
          (dynamic login) => login["user"] as String,
        ) ??
        <String>[],
  );
  if (hasPrimaryAccount && !shouldSignIn) {
    otherAccounts.insert(0, user);
  }
  await api.actions.loginActions.setAvailableAccounts(otherAccounts);
  if ((api.state.url != null && api.state.url != url) ||
      (api.state.loginState.username != null &&
          api.state.loginState.username != user)) {
    // TODO: Figure out when exactly we'd hit this code path and how to handle it better.
    await api.actions.savePassActions.delete();
    await api.actions.routingActions.showLogin();
  } else {
    if (hasPrimaryAccount && shouldSignIn) {
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
  schoolNotificationStartupReady.value = true;
}

Future<void> _refresh(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  _markRuntimeCacheStale(_dashboardCacheKey(api.state.dashboardState.future));
  _markRuntimeCacheStale(_notificationsCacheKey);
  final showAbsences =
      api.state.settingsState.dashboardItems.contains('absences');
  if (showAbsences) _markRuntimeCacheStale(_absencesCacheKey);
  await Future.wait([
    api.actions.dashboardActions.load(api.state.dashboardState.future),
    api.actions.notificationsActions.load(),
    if (showAbsences) api.actions.absencesActions.load(),
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
  if (!action.payload.fromStorage) {
    await api.actions.savePassActions.save();
  }
  deletedData = false;
  final session = _Session.capture();
  final key = getStorageKey(action.payload.username, wrapper.loginAddress);
  if (!api.state.loginState.loggedIn && !action.payload.secondaryOnlineLogin) {
    privacyLog('technical_operation');
    final state = await _readFromStorage(key);
    // The saved state of this account must not be mounted into another one.
    session.ensureCurrent();
    if (state != null) {
      try {
        final serializedState = serializers.deserialize(
          json.decode(state) as Object,
        );
        if (serializedState is SettingsState) {
          final currentSettings = await _settingsForAccountLoad(
            legacySettings: serializedState,
          );
          session.ensureCurrent();
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
          session.ensureCurrent();
          await api.actions.mountAppState(
            serializedState.rebuild(
              (b) => b
                ..loginState.replace(currentState.loginState)
                ..url = currentState.url
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
      } on StaleSessionException {
        rethrow;
      } catch (e) {
        showSnackBar(tr('error.savedDataLoadFailed'));
        privacyLog('technical_operation');
        await next(action);
      }
    } else {
      await next(action);
    }

    await _mountStudyData(api, session, action.payload.username);
    _popAll();
  } else {
    await next(action);
  }

  // Restoring settings applies the session policy without removing accounts or
  // rewriting their credentials as a side effect of signing in.
  wrapper.safeMode = api.state.settingsState.noPasswordSaving;
  if (!action.payload.offlineOnly &&
      !wrapper.demoMode &&
      wrapper.user != null) {
    unawaited(schoolNotificationOperation(() => schoolNotifications.activate(
          wrapper.url!,
          wrapper.user!,
          backgroundAllowed: !api.state.settingsState.noPasswordSaving,
        )));
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
    // Dashboard loading starts holiday hydration independently in the background.
  }
  await schoolNotificationOperation(() async {
    await schoolNotifications.onTap?.call();
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(schoolNotificationOperation(() async {
      await schoolNotifications.onTap?.call();
    }));
  });
  // Optional account onboarding is offered by the mounted home route after
  // startup notices finish, followed by the tutorial. Neither blocks login.
  // Registering a post-frame callback does not itself request a frame. With
  // idle startup data the offer would otherwise wait for the user's next tap.
  WidgetsBinding.instance.ensureVisualUpdate();
}

Future<SettingsState> _settingsForAccountLoad({
  required SettingsState legacySettings,
}) async {
  final globalSettings = await settingsPersistenceService.load();
  if (globalSettings != null) {
    return globalSettings;
  }
  // The first shared settings are the ones this account has saved so far,
  // learning notes included: they are not lost, and belong to no account yet.
  await settingsPersistenceService.adopt(legacySettings);
  return StudyData.empty.applyTo(legacySettings);
}

/// The account whose learning notes are in the settings of the store, or null
/// while they are not (not loaded yet, or they could not be read). Notes are
/// only saved for this account: a failed read must never be followed by a
/// write that replaces what could not be read.
AccountScope? _studyDataScope;

AccountScope _studyScopeOf(String? username) =>
    AccountScope(wrapper.url, username);

/// Puts the learning notes of the account that just signed in into the
/// settings of the store. Whoever signed in before left none behind.
Future<void> _mountStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session,
  String? username,
) async {
  final scope = _studyScopeOf(username);
  _studyDataScope = null;
  var unreadable = false;
  // The notes older versions kept for all accounts are put aside before any
  // account reads its own. A read that fails postpones this to the next start.
  try {
    await studyDataMigration.ensureQuarantined();
    legacyStudyDataRevision.value++;
  } on StudyDataUnreadable catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    unreadable = true;
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
  session.ensureCurrent();
  StudyData data;
  try {
    data = await studyDataService.load(scope);
  } on StudyDataUnreadable catch (error, stack) {
    session.ensureCurrent();
    diagnostics.report(error, stack, DiagnosticError.storage);
    showSnackBar(tr('error.savedDataUnreadable'));
    return;
  }
  session.ensureCurrent();
  if (unreadable) showSnackBar(tr('error.savedDataUnreadable'));
  await api.actions.mountAppState(
    api.state.rebuild((b) => b..settingsState.replace(
          data.applyTo(api.state.settingsState),
        )),
  );
  _studyDataScope = scope;
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_offerLegacyStudyData(api, session)));
}

const _legacyStudyPromptedKey = 'studyDataLegacyPromptedV1';

/// Once, after the first sign-in that finds older learning notes without an
/// account, asks what to do with them. Closing the question means later.
Future<void> _offerLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  _Session session,
) async {
  try {
    if (!session.isCurrent ||
        wrapper.demoMode ||
        session.scope.user == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyStudyPromptedKey) ?? false) return;
    final summary = await studyDataMigration.summary();
    if (summary == null) return;
    session.ensureCurrent();
    await prefs.setBool(_legacyStudyPromptedKey, true);
    await showLegacyStudyDataDialog(api.actions, summary);
  } on StaleSessionException {
    // The account was left before the question was asked.
  } on StudyDataUnreadable {
    // Asked at the next start.
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
}

Map<String, String> _legacyStudyArgs(LegacyStudySummary summary) => {
      'exams': summary.exams.toString(),
      'notes': summary.notes.toString(),
      'files': summary.files.toString(),
    };

enum _LegacyStudyChoice { assign, later, discard }

/// Asks what to do with the older learning notes: numbers only, never their
/// content. Closing the dialog keeps them (later); discarding needs a second
/// confirmation.
Future<void> showLegacyStudyDataDialog(
  AppActions actions,
  LegacyStudySummary summary,
) async {
  final navigator = navigatorKey?.currentState;
  final context = navigatorKey?.currentContext;
  if (navigator == null || context == null) return;
  final choice = await navigator.push<_LegacyStudyChoice>(
    DialogRoute(
      context: context,
      builder: (context) => InfoDialog(
        title: Text(tr('studyData.legacy.title')),
        content: Text(
            tr('studyData.legacy.body', args: _legacyStudyArgs(summary))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.discard),
            child: Text(tr('studyData.legacy.discard')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.assign),
            child: Text(tr('studyData.legacy.assign')),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, _LegacyStudyChoice.later),
            child: Text(tr('studyData.legacy.later')),
          ),
        ],
      ),
    ),
  );
  switch (choice) {
    case _LegacyStudyChoice.assign:
      await actions.assignLegacyStudyData();
    case _LegacyStudyChoice.discard:
      if (await _confirmDiscardLegacyStudyData(summary) == true) {
        await actions.discardLegacyStudyData();
      }
    case _LegacyStudyChoice.later:
    case null:
      break;
  }
}

Future<bool?> _confirmDiscardLegacyStudyData(LegacyStudySummary summary) {
  final context = navigatorKey?.currentContext;
  if (context == null) return Future.value(false);
  return navigatorKey!.currentState!.push<bool>(
    DialogRoute(
      context: context,
      builder: (context) => InfoDialog(
        title: Text(tr('studyData.legacy.discardConfirm.title')),
        content: Text(tr('studyData.legacy.discardConfirm.body',
            args: _legacyStudyArgs(summary))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('studyData.legacy.discardConfirm.confirm')),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('common.cancel')),
          ),
        ],
      ),
    ),
  );
}

/// Gives the older learning notes to the account that is signed in.
Future<void> _assignLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final session = _Session.capture();
  final scope = _studyScopeOf(api.state.loginState.username);
  // The demo account has no notes of its own to receive them, and an account
  // whose notes were not read must not be written to.
  if (!api.state.loginState.loggedIn ||
      scope.user == null ||
      wrapper.demoMode ||
      _studyDataScope != scope) {
    showSnackBar(tr('studyData.legacy.assignFailed'));
    return;
  }
  try {
    final outcome = await statePersistenceService.runExclusive(() async {
      session.ensureCurrent();
      final result = await studyDataMigration.assign(
        scope,
        current: StudyData.fromSettings(api.state.settingsState),
      );
      session.ensureCurrent();
      // With what was typed in the meantime, which replaces nothing.
      final merged = StudyData.fromSettings(api.state.settingsState)
          .withMissingFrom(result.moved);
      await api.actions.mountAppState(
        api.state.rebuild((b) => b
          ..settingsState.replace(merged.applyTo(api.state.settingsState))),
      );
      return result;
    });
    legacyStudyDataRevision.value++;
    if (outcome.moved.isEmpty && outcome.remaining.isEmpty) return;
    showSnackBar(outcome.remaining.isEmpty
        ? tr('studyData.legacy.assigned', args: {
            'notes': outcome.moved.noteCount.toString(),
            'files': outcome.moved.fileCount.toString(),
          })
        : tr('studyData.legacy.assignedPartly', args: {
            'notes': outcome.moved.noteCount.toString(),
            'files': outcome.moved.fileCount.toString(),
            'exams': outcome.remaining.keys.length.toString(),
          }));
  } on StaleSessionException {
    rethrow;
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.assignFailed'));
  }
}

/// Deletes the older learning notes for good. Asked twice before.
Future<void> _discardLegacyStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  try {
    await statePersistenceService.runExclusive(studyDataMigration.discard);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.discarded'));
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
    legacyStudyDataRevision.value++;
    showSnackBar(tr('studyData.legacy.discardFailed'));
  }
}

/// Saves the learning notes of the signed-in account after they changed.
Future<void> _persistStudyData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) async {
  final state = api.state;
  if (deletedData || !state.loginState.loggedIn) return;
  final scope = _studyScopeOf(state.loginState.username);
  if (_studyDataScope != scope) return;
  final requested = StudyData.fromSettings(state.settingsState);
  try {
    // Behind every earlier write and deletion, in the order requested. What
    // is written is what the account has by then, so a save that waited
    // behind a move of the older notes cannot write them away again.
    await statePersistenceService.runExclusive(() {
      final stillSignedIn = !deletedData &&
          api.state.loginState.loggedIn &&
          _studyScopeOf(api.state.loginState.username) == scope &&
          _studyDataScope == scope;
      return studyDataService.save(
        scope,
        stillSignedIn
            ? StudyData.fromSettings(api.state.settingsState)
            : requested,
      );
    });
  } catch (error, stack) {
    diagnostics.report(error, stack, DiagnosticError.storage);
  }
}

bool _studyDataChanged(SettingsState before, SettingsState after) =>
    before.assessmentStudyProgress != after.assessmentStudyProgress ||
    before.assessmentStudyNotes != after.assessmentStudyNotes ||
    before.assessmentStudyAttachments != after.assessmentStudyAttachments ||
    before.assessmentStudyPhases != after.assessmentStudyPhases;

// This is to avoid saving data in an action right after deleting data,
// which would restore it. Caches ask the same flag where they write.
@visibleForTesting
bool get deletedData => localDataPolicy.dataDeletionActive;

@visibleForTesting
set deletedData(bool value) => localDataPolicy.dataDeletionActive = value;

NextActionHandler _saveStateMiddleware(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) {
  // Caches decide at the place they write whether the user turned saving off.
  localDataPolicy.noDataSavingReader =
      () => api.state.settingsState.noDataSaving;
  return _saveStateHandler(api);
}

NextActionHandler _saveStateHandler(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
) =>
    (ActionHandler next) => (Action action) async {
          final previousSettings = api.state.settingsState;
          await next(action);
          if (action.name != AppActionsNames.mountAppState.name &&
              (api.state.settingsState != previousSettings ||
                  action.name == SettingsActionsNames.dashboardItems.name ||
                  action.name ==
                      SettingsActionsNames.setDashboardConfiguration.name)) {
            await settingsPersistenceService.save(api.state.settingsState);
          }
          if (action.name != AppActionsNames.mountAppState.name &&
              _studyDataChanged(previousSettings, api.state.settingsState)) {
            await _persistStudyData(api);
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
                writer: _persistWriter(),
                keyFactory: getStorageKey,
              );
              if (deletedData) {
                await androidWidgetSnapshotService.clear(reason: action.name);
              } else {
                await androidWidgetSnapshotService.flush(
                    state: api.state, reason: action.name);
              }
            } else {
              statePersistenceService.schedule(
                state: api.state,
                deletedData: deletedData,
                server: wrapper.loginAddress,
                writer: _persistWriter(),
                keyFactory: getStorageKey,
              );
              if (deletedData) {
                await androidWidgetSnapshotService.clear(reason: action.name);
              } else {
                androidWidgetSnapshotService.scheduleSync(api.state,
                    reason: action.name);
              }
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

/// Storage keys whose saved state could not be read in this session.
///
/// A failed read does not prove that the entry is damaged: the keystore or
/// keyring may only be unavailable for a moment. The entry is therefore kept
/// and, until a later read succeeds, not overwritten with the state of this
/// session, which started without the saved data.
final Set<String> _unreadableStorageKeys = <String>{};

@visibleForTesting
Duration storageReadRetryDelay = const Duration(milliseconds: 200);

/// Whether data deletion is active is decided when a write is requested, not
/// when it finally runs behind the writes in front of it.
PersistStateWriter _persistWriter() {
  final deleting = deletedData;
  return (key, txt) => _writeToStorage(key, txt, deleting: deleting);
}

Future<void> _writeToStorage(
  String key,
  String txt, {
  required bool deleting,
}) async {
  if (_unreadableStorageKeys.contains(key) && !deleting) {
    privacyLog('technical_operation');
    return;
  }
  await secureStorage.write(key: escapeKey(key), value: txt);
}

/// Reads the saved state of [key].
///
/// A read error never deletes stored data: other accounts, saved
/// credentials and the unreadable entry itself are kept. The read is retried
/// once; if it still fails the user is told that the data was kept and will
/// be loaded again on the next start.
Future<String?> _readFromStorage(String key) async {
  for (var attempt = 0;; attempt++) {
    try {
      final value = await secureStorage.read(key: escapeKey(key));
      _unreadableStorageKeys.remove(key);
      return value;
    } catch (e, stack) {
      privacyLog('technical_operation');
      if (attempt == 0) {
        await Future<void>.delayed(storageReadRetryDelay);
        continue;
      }
      diagnostics.report(e, stack, DiagnosticError.storage);
      _unreadableStorageKeys.add(key);
      showSnackBar(tr('error.savedDataUnreadable'));
      return null;
    }
  }
}

Future<void> _saveNoData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  if (api.state.settingsState.noDataSaving) {
    // Turning saving off removes the caches that are there. Confirmed by the
    // user in the settings before this action is dispatched.
    try {
      await _deleteCurrentAccountData(api.state, LocalDataTrigger.stopSaving);
    } catch (error, stack) {
      diagnostics.report(error, stack, DiagnosticError.storage);
      showSnackBar(tr('settings.storeData.deleteFailed'));
    }
  }
  await api.actions.saveState();
}

Future<void> _deleteData(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  deletedData = true;
  // No later write can bring the data back while deletion is active.
  await _deleteCurrentAccountData(api.state, LocalDataTrigger.deleteData);
  await androidWidgetSnapshotService.clear();
  await api.actions.saveState();
}

Future<void> _restarted(
  MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
  ActionHandler next,
  Action<void> action,
) async {
  await next(action);
  final source = wrapper;
  final server = source.url;
  final user = source.user;
  unawaited(schoolNotificationOperation(() async {
    await schoolNotifications.reload();
    if (api.state.loginState.loggedIn &&
        identical(source, wrapper) &&
        server == wrapper.url &&
        user == wrapper.user) {
      await api.actions.notificationsActions.load();
      await schoolNotifications.schedule();
      await schoolNotifications.onTap?.call();
    }
  }));
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
  final override = attachmentDownloadDirectoryOverride;
  if (override != null) return override();
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
      privacyLog('technical_operation');
      return (await getApplicationDocumentsDirectory()).path;
    }
  }();
  _attachmentDownloadDirectoryFuture = future;
  return future;
}

/// The folder of one account inside the attachment download directory. Files
/// of other accounts, and files saved before accounts had folders, are not in
/// it and so are never found, opened or replaced for this account.
Future<String> _accountDownloadFolder(AccountScope scope) async =>
    '${await _getAttachmentDownloadDirectory()}/${scope.fileId}';

/// Resolves [fileName] inside the download folder of [scope].
///
/// Attachment names are derived from backend metadata, so anything that is
/// not a single plain file name, or that is a link which could redirect the
/// access elsewhere, is rejected with `null` instead of being allowed to
/// leave the folder.
Future<File?> _attachmentFile(String fileName, AccountScope scope) async {
  if (!isSafeFileNameSegment(fileName)) {
    return null;
  }
  final folder = await _accountDownloadFolder(scope);
  final file = File('$folder/$fileName');
  if (await FileSystemEntity.isLink(folder) ||
      await FileSystemEntity.isLink(file.path)) {
    return null;
  }
  return file;
}

/// Deletes the download folder of [scope] with everything in it.
Future<void> _deleteAccountDownloads(AccountScope scope) async {
  try {
    final folder = await _accountDownloadFolder(scope);
    // A link planted in place of the folder is removed, never followed.
    if (await FileSystemEntity.isLink(folder)) {
      await Link(folder).delete();
    } else if (await Directory(folder).exists()) {
      await Directory(folder).delete(recursive: true);
    }
  } catch (_) {
    privacyLog('technical_operation');
  }
}

/// Downloads a file.
///
/// Returns true on success and false on a failure. The file is only written
/// once the authenticated response has been validated, so an expired session
/// never leaves a login page behind as a supposedly downloaded document.
Future<bool> downloadFile(
  String url,
  String fileName,
  Map<String, dynamic> parameters,
) async {
  // The request goes out on the session that asked, and a document is only
  // saved while the app is still in that session.
  final session = _Session.capture();
  final loggedIn = await session.wrapper.ensureLoggedIn();
  session.ensureCurrent();
  if (!loggedIn) {
    privacyLog('technical_operation');
    return false;
  }

  final saveFile = await _attachmentFile(fileName, session.scope);
  if (saveFile == null) {
    privacyLog('technical_operation');
    return false;
  }
  if (await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(fileName);
    session.ensureCurrent();
    if (shouldOverwrite == null) {
      return false;
    } else if (!shouldOverwrite) {
      return true;
    }
  }

  // Mirrors Wrapper.send: one background relogin, then one forced relogin.
  const maxLoginRetries = 2;
  for (var attempt = 0; attempt <= maxLoginRetries; attempt++) {
    if (attempt > 0) {
      final relogin = await session.wrapper.ensureLoggedIn(
        isRetryAfterUnexpectedLogout: true,
        forceRelogin: attempt > 1,
      );
      session.ensureCurrent();
      if (!relogin) {
        privacyLog('technical_operation');
        return false;
      }
    }
    final List<int> bytes;
    final String contentType;
    try {
      final result = await session.wrapper.dio.get<List<int>>(
        url,
        queryParameters: parameters,
        options: dio.Options(responseType: dio.ResponseType.bytes),
      );
      session.ensureCurrent();
      if (result.statusCode != 200) {
        privacyLog('technical_operation');
        return false;
      }
      bytes = result.data ?? const <int>[];
      contentType = result.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    } on StaleSessionException {
      rethrow;
    } catch (_) {
      // A request that failed because the session was retired is no failure.
      session.ensureCurrent();
      privacyLog('technical_operation');
      return false;
    }

    switch (validateDownloadedDocument(bytes, contentType, fileName)) {
      case DownloadValidation.valid:
        try {
          await _writeFileAtomically(saveFile, bytes);
          return true;
        } catch (_) {
          privacyLog('technical_operation');
          return false;
        }
      case DownloadValidation.loginPage:
        privacyLog('technical_operation');
        continue;
      case DownloadValidation.invalid:
        privacyLog('technical_operation');
        return false;
    }
  }
  return false;
}

enum DownloadValidation { valid, loginPage, invalid }

/// Checks that an HTTP 200 download body is the requested document and not
/// the login page or an error response.
///
/// HTML and JSON bodies are only accepted when [fileName] asks for such a
/// document, so legitimate `.html`/`.json` attachments keep working.
@visibleForTesting
DownloadValidation validateDownloadedDocument(
  List<int> bytes,
  String contentType,
  String fileName,
) {
  if (bytes.isEmpty) {
    return DownloadValidation.invalid;
  }
  final prefix = utf8
      .decode(bytes.take(64 * 1024).toList(), allowMalformed: true)
      .replaceFirst('﻿', '')
      .trimLeft();
  final looksLikeMarkup = prefix.startsWith('<');
  if (looksLikeMarkup && Wrapper.isLoginPage(prefix)) {
    return DownloadValidation.loginPage;
  }
  final extension = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
      : '';
  final normalizedContentType = contentType.toLowerCase();
  if (looksLikeMarkup &&
      normalizedContentType.contains('text/html') &&
      !const {'htm', 'html', 'xhtml', 'xml', 'svg'}.contains(extension)) {
    return DownloadValidation.invalid;
  }
  if ((prefix.startsWith('{') || prefix.startsWith('[')) &&
      normalizedContentType.contains('application/json') &&
      extension != 'json') {
    return DownloadValidation.invalid;
  }
  return DownloadValidation.valid;
}

/// Writes [bytes] to a sibling temporary file and moves it into place, so a
/// failed write never replaces or leaves behind a partial [file].
Future<void> _writeFileAtomically(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final partial = File('${file.path}.part');
  if (await FileSystemEntity.isLink(partial.path)) {
    throw FileSystemException('Refusing to write through a link', partial.path);
  }
  try {
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  } catch (_) {
    if (await partial.exists()) {
      await partial.delete();
    }
    rethrow;
  }
}

Future<Uint8List> fetchAuthenticatedBytes(String url) async {
  final session = _Session.capture();
  // One request per session: another account must not share this answer.
  final key = '${session.generation}|$url';
  final existing = _authenticatedBytesInFlight[key];
  if (existing != null) {
    return existing;
  }
  final request = () async {
    await session.wrapper.ensureLoggedIn();
    session.ensureCurrent();
    final response = await session.wrapper.dio.get<List<int>>(
      url,
      options: dio.Options(responseType: dio.ResponseType.bytes),
    );
    // Bytes fetched for an account the app has left are not for the next one.
    session.ensureCurrent();
    return Uint8List.fromList(response.data ?? const <int>[]);
  }();
  _authenticatedBytesInFlight[key] = request;
  try {
    return await request;
  } finally {
    if (identical(_authenticatedBytesInFlight[key], request)) {
      final removed = _authenticatedBytesInFlight.remove(key);
      assert(identical(removed, request));
    }
  }
}

/// Whether the account signed in now has [fileName] saved.
Future<bool> canOpenFile(String fileName) =>
    _canOpenFileIn(_Session.capture(), fileName);

Future<bool> _canOpenFileIn(_Session session, String fileName) async {
  return await (await _attachmentFile(fileName, session.scope))?.exists() ??
      false;
}

/// Opens a downloaded attachment and tells the user when that fails.
Future<void> openFile(String fileName) async {
  privacyLog('technical_operation');
  final file = await _attachmentFile(fileName, _Session.capture().scope);
  if (file == null || !await _openDownloadedFile(file)) {
    showSnackBar(tr('courseMaterials.openFailed'));
  }
}

/// Opens [file] with the platform's viewer. Only [ResultType.done] counts as
/// success; no app, a denied permission, an error code or an exception from
/// the plugin all report failure.
Future<bool> _openDownloadedFile(File file) async {
  try {
    final result =
        await (downloadedFileOpenerOverride ?? OpenFile.open)(file.path);
    return result.type == ResultType.done;
  } catch (_) {
    return false;
  }
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
