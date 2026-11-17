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

// Course materials: discovery, cached payloads, and downloading and
// opening their files with per-account version tracking.

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
      // The server answers a subject without a course with an empty body.
      acceptEmptyResponse: true,
    );
    if (response == true) {
      continue;
    }
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
  if (HostPlatform.isWindows || HostPlatform.isLinux) {
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

  /// The app left the account while the document was loading. Nothing was
  /// saved or opened, and nothing may be shown in the account it is in now.
  abandoned,
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
    // Web: the download went to the browser, which opens it from there.
    if (kIsWeb) return CourseMaterialOpenResult.opened;
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
  } on StaleSessionException {
    _materialLog('abandoned', {'at': stage});
    return CourseMaterialOpenResult.abandoned;
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

  final saveFile =
      kIsWeb ? null : await _attachmentFile(entry.uniqueName, session.scope);
  if (saveFile == null && !kIsWeb) {
    return false;
  }
  _materialLog('destination', {'exists': await saveFile?.exists() ?? false});
  if (saveFile != null && !replaceOutdated && await saveFile.exists()) {
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
      if (saveFile == null) return saveInBrowser(entry.uniqueName, bytes);
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

  if (saveFile != null && !replaceOutdated && await saveFile.exists()) {
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
