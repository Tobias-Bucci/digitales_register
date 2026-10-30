import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:open_file/open_file.dart';
import 'package:open_file/src/platform/linux_open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Wrapper extends Mock implements Wrapper {
  // Downloads capture the session they run in, which asks the wrapper.
  @override
  bool get isRetired => false;
}

CourseMaterialEntry entry(
        [String name = 'Prüfung mit Leerzeichen.pdf',
        String lastModified = '2026-10-01 08:00:00']) =>
    CourseMaterialEntry.fromJson({
      'id': 657,
      'courseContentId': 83,
      'type': 'file',
      'file': 'server.pdf',
      'originalName': name,
      'lastmodified': lastModified,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory base;
  late Directory directory;
  late Dio client;
  late Wrapper previousWrapper;
  late DebugPrintCallback previousPrint;
  late List<String> logs;
  late int requests;
  late int opens;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    base = await Directory.systemTemp.createTemp('course-material-');
    previousWrapper = wrapper;
    final mock = _Wrapper();
    wrapper = mock;
    when(() => mock.url).thenReturn('https://school.example');
    when(() => mock.user).thenReturn('max');
    // Files are kept in a folder of the account that is signed in.
    directory = Directory(
        '${base.path}/${AccountScope('https://school.example', 'max').fileId}')
      ..createSync();
    client = Dio();
    when(() => mock.dio).thenReturn(client);
    when(() => mock.baseAddress).thenReturn('https://school.example/v2/');
    when(() => mock.ensureLoggedIn()).thenAnswer((_) async => true);
    attachmentDownloadDirectoryOverride = () async => base.path;
    courseMaterialPlatformOverride = TargetPlatform.windows;
    opens = 0;
    requests = 0;
    courseMaterialFileOpenerOverride = (path) async {
      opens++;
      expect(path, '${directory.path}/${entry().uniqueName}');
      expect(await File(path).exists(), isTrue);
      return OpenResult(type: ResultType.done, message: 'done');
    };
    clearRuntimeCaches();
    previousPrint = debugPrint;
    logs = [];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() async {
    wrapper = previousWrapper;
    attachmentDownloadDirectoryOverride = null;
    courseMaterialPlatformOverride = null;
    courseMaterialFileOpenerOverride = null;
    debugPrint = previousPrint;
    courseMaterialDebugLogsOverride = null;
    client.close(force: true);
    await base.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('digitales_register/linux_file_open'), null);
  });

  void respond(
      {int status = 200,
      String type = 'application/pdf',
      List<int> bytes = const [37, 80, 68, 70, 45, 49]}) {
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      // These sensitive values must never appear in the local diagnosis.
      options.headers['Cookie'] = 'session=SECRET_COOKIE';
      options.headers['Authorization'] = 'Bearer SECRET_TOKEN';
      handler.resolve(Response<List<int>>(
        requestOptions: options,
        statusCode: status,
        data: bytes,
        headers: Headers.fromMap({
          'content-type': [type]
        }),
      ));
    }));
  }

  test('downloads, saves and opens the first successful GET candidate',
      () async {
    respond();
    expect(await openCourseMaterialEntry(entry()), isTrue);
    expect(requests, 1);
    expect(opens, 1);
    expect(await File('${directory.path}/${entry().uniqueName}').readAsBytes(),
        [37, 80, 68, 70, 45, 49]);
    final output = logs.join('\n');
    for (final field in [
      'authentication',
      'downloadEntry',
      'GET',
      'parameters',
      'status',
      'contentType',
      'bytes',
      'saved',
      'open_result',
    ]) {
      expect(output, contains(field));
    }
    expect(output, isNot(contains('SECRET')));
    expect(output, isNot(contains('Authorization')));
    expect(output, isNot(contains('Cookie')));
  });

  test('diagnostics contain no document names or local paths', () async {
    const name = 'Zeugnis Max Mustermann.pdf';
    courseMaterialFileOpenerOverride = (path) async {
      opens++;
      return OpenResult(type: ResultType.done, message: 'done');
    };
    respond();
    expect(await openCourseMaterialEntry(entry(name)), isTrue);
    // Open again so the local-file branch is logged as well.
    expect(await openCourseMaterialEntry(entry(name)), isTrue);

    final output = logs.join('\n');
    expect(output, contains('[CourseMaterial]'));
    for (final private in [
      'Mustermann',
      'Zeugnis',
      'server.pdf',
      entry(name).uniqueName,
      directory.path,
      jsonEncode(directory.path),
      directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ]) {
      expect(output, isNot(contains(private)), reason: private);
    }
  });

  test('release builds print no course material diagnostics', () async {
    courseMaterialDebugLogsOverride = false;
    respond();
    expect(await openCourseMaterialEntry(entry()), isTrue);
    expect(logs.where((l) => l.contains('[CourseMaterial]')), isEmpty);
  });

  for (final (name, type, body) in [
    (
      'diagram.svg',
      'image/svg+xml',
      '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
    ),
    ('exercise.xml', 'application/xml', '<?xml version="1.0"?><exercise/>'),
    (
      'notes.html',
      'text/html; charset=utf-8',
      '<html><head><title>Notes</title></head><body>Bruch</body></html>'
    ),
    ('data.json', 'application/json', '{"values":[1,2,3]}'),
  ]) {
    test('valid $name course files download with a single request', () async {
      courseMaterialFileOpenerOverride = (path) async {
        opens++;
        return OpenResult(type: ResultType.done, message: 'done');
      };
      respond(type: type, bytes: utf8.encode(body));
      expect(await openCourseMaterialEntry(entry(name)), isTrue);
      expect(requests, 1);
      expect(
          await File('${directory.path}/${entry(name).uniqueName}')
              .readAsString(),
          body);
    });
  }

  test('a login page stops probing further endpoints', () async {
    respond(
        type: 'text/html',
        bytes: utf8.encode('<!DOCTYPE html><html><head><title>Login</title>'
            '</head><body><form></form></body></html>'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(requests, 1);
    expect(logs.join('\n'), contains('login_page'));
    expect(await File('${directory.path}/${entry().uniqueName}').exists(),
        isFalse);
  });

  test('a JSON error response is still rejected for other file types',
      () async {
    respond(type: 'application/json', bytes: utf8.encode('{"error":"x"}'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(await File('${directory.path}/${entry().uniqueName}').exists(),
        isFalse);
  });

  test('network failures do not probe every endpoint', () async {
    var attempts = 0;
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      attempts++;
      handler.reject(DioException(
          requestOptions: options, type: DioExceptionType.connectionError));
    }));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(attempts, 1);
  });

  test('the working endpoint is remembered for later downloads', () async {
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      final works = options.method == 'GET' &&
          options.path.endsWith('api/courseContent/downloadFile') &&
          options.queryParameters.containsKey('entryId');
      handler.resolve(Response<List<int>>(
          requestOptions: options,
          statusCode: works ? 200 : 404,
          data: works ? [37, 80, 68, 70] : const [],
          headers: Headers.fromMap({
            'content-type': ['application/pdf']
          })));
    }));
    courseMaterialFileOpenerOverride = (path) async {
      opens++;
      return OpenResult(type: ResultType.done, message: 'done');
    };
    expect(await openCourseMaterialEntry(entry()), isTrue);
    expect(requests, greaterThan(1));

    requests = 0;
    expect(await openCourseMaterialEntry(entry('Zweites Blatt.pdf')), isTrue);
    expect(requests, 1);
  });

  test('retains POST fallback after rejected GET', () async {
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      expect(options.path,
          'https://school.example/v2/courseContent/downloadEntry');
      expect(options.method == 'GET' ? options.queryParameters : options.data,
          {'course': 83, 'entry': 657});
      handler.resolve(Response<List<int>>(
          requestOptions: options,
          statusCode: options.method == 'GET' ? 404 : 200,
          data: [37, 80, 68, 70],
          headers: Headers.fromMap({
            'content-type': ['application/pdf']
          })));
    }));
    expect(await openCourseMaterialEntry(entry()), isTrue);
    expect(requests, 2);
  });

  for (final failure in ['http', 'html', 'empty', 'network']) {
    test('failed $failure download leaves no file and never opens', () async {
      if (failure == 'network') {
        client.interceptors
            .add(InterceptorsWrapper(onRequest: (options, handler) {
          handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'SECRET_PASSWORD'));
        }));
      } else {
        respond(
            status: failure == 'http' ? 403 : 200,
            type: failure == 'html' ? 'text/html' : 'application/pdf',
            bytes: failure == 'empty' ? [] : [60, 104, 116, 109, 108, 62]);
      }
      expect(await openCourseMaterialEntry(entry()), isFalse);
      expect(opens, 0);
      expect(await File('${directory.path}/${entry().uniqueName}').exists(),
          isFalse);
      expect(logs.join('\n'), contains('download_failed'));
      expect(logs.join('\n'), isNot(contains('SECRET')));
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android
  ]) {
    test('existing file on $platform opens without login or download',
        () async {
      courseMaterialPlatformOverride = platform;
      await File('${directory.path}/${entry().uniqueName}')
          .writeAsBytes([1, 2]);
      await rememberCourseMaterialVersion(entry());
      expect(await openCourseMaterialEntry(entry()), isTrue);
      verifyNever(() => wrapper.ensureLoggedIn());
      expect(requests, 0);
      expect(opens, 1);
    });
    test('download path preserves spaces and umlauts on $platform', () async {
      courseMaterialPlatformOverride = platform;
      respond();
      expect(await openCourseMaterialEntry(entry()), isTrue);
      expect(opens, 1);
    });
  }

  test('Linux passes the saved full path to the portal channel', () async {
    courseMaterialPlatformOverride = TargetPlatform.linux;
    courseMaterialFileOpenerOverride = openLinuxFile;
    respond();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('digitales_register/linux_file_open'),
            (call) async {
      final path = (call.arguments as Map)['path'] as String;
      expect(path, '${directory.path}/${entry().uniqueName}');
      expect(await File(path).readAsBytes(), [37, 80, 68, 70, 45, 49]);
      return {'type': 0, 'message': 'done'};
    });
    expect(await openCourseMaterialEntry(entry()), isTrue);
  });

  test('desktop open failures return false and keep the downloaded file',
      () async {
    respond();
    courseMaterialFileOpenerOverride = (_) async =>
        OpenResult(type: ResultType.noAppToOpen, message: 'SECRET');
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(
        await File('${directory.path}/${entry().uniqueName}').exists(), isTrue);
    expect(logs.join('\n'), contains('noAppToOpen'));
    expect(logs.join('\n'), isNot(contains('SECRET')));
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform open failures return false instead of success', () async {
      courseMaterialPlatformOverride = platform;
      respond();
      courseMaterialFileOpenerOverride = (_) async =>
          OpenResult(type: ResultType.noAppToOpen, message: 'No APP found');
      expect(await openCourseMaterialEntry(entry()), isFalse);
      courseMaterialFileOpenerOverride =
          (_) async => OpenResult(type: ResultType.done, message: 'done');
      expect(await openCourseMaterialEntry(entry()), isTrue);
    });
  }

  test('storage and opener exceptions are contained', () async {
    attachmentDownloadDirectoryOverride =
        () => Future.error(FileSystemException('SECRET'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(logs.join('\n'), contains('local_check'));
    expect(logs.join('\n'), isNot(contains('SECRET')));
    attachmentDownloadDirectoryOverride = () async => base.path;
    respond();
    courseMaterialFileOpenerOverride =
        (_) => Future.error(StateError('SECRET'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(logs.join('\n'), contains('StateError'));
    expect(logs.join('\n'), isNot(contains('SECRET')));
  });
  group('updated documents', () {
    final old = entry('lesson.pdf', '2026-10-01 08:00:00');
    final updated = entry('lesson.pdf', '2026-10-18 09:30:00');
    late File saved;
    late List<List<int>> openedBytes;

    setUp(() async {
      saved = File('${directory.path}/${old.uniqueName}');
      await saved.writeAsBytes([1, 2, 3]);
      await rememberCourseMaterialVersion(old);
      openedBytes = [];
      courseMaterialFileOpenerOverride = (path) async {
        openedBytes.add(await File(path).readAsBytes());
        return OpenResult(type: ResultType.done, message: 'done');
      };
    });

    test('keep the file name', () {
      expect(updated.uniqueName, old.uniqueName);
      expect(updated.contentVersion, isNot(old.contentVersion));
    });

    test('a new server version replaces the saved file', () async {
      respond();
      expect(await openCourseMaterialEntryWithStatus(updated),
          CourseMaterialOpenResult.opened);
      verify(() => wrapper.ensureLoggedIn()).called(1);
      expect(requests, 1);
      expect(openedBytes, [
        [37, 80, 68, 70, 45, 49]
      ]);
      expect(await saved.readAsBytes(), [37, 80, 68, 70, 45, 49]);

      // The new version is now current and opens without a download.
      expect(await openCourseMaterialEntryWithStatus(updated),
          CourseMaterialOpenResult.opened);
      expect(requests, 1);
    });

    test('a changed server file id also counts as a new version', () async {
      respond();
      final replaced = CourseMaterialEntry.fromJson({
        ...old.toJson(),
        'file': 'replacement.pdf',
      });
      expect(await openCourseMaterialEntryWithStatus(replaced),
          CourseMaterialOpenResult.opened);
      expect(requests, 1);
    });

    test('the unchanged version opens without a download', () async {
      expect(await openCourseMaterialEntryWithStatus(old),
          CourseMaterialOpenResult.opened);
      verifyNever(() => wrapper.ensureLoggedIn());
      expect(requests, 0);
    });

    for (final failure in ['http', 'html', 'network']) {
      test('a failed $failure update keeps and opens the previous file',
          () async {
        if (failure == 'network') {
          client.interceptors
              .add(InterceptorsWrapper(onRequest: (options, handler) {
            handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError));
          }));
        } else {
          respond(
              status: failure == 'http' ? 403 : 200,
              type: failure == 'html' ? 'text/html' : 'application/pdf',
              bytes: [60, 104, 116, 109, 108, 62]);
        }
        expect(await openCourseMaterialEntryWithStatus(updated),
            CourseMaterialOpenResult.openedOutdated);
        expect(await saved.readAsBytes(), [1, 2, 3]);
        expect(openedBytes, [
          [1, 2, 3]
        ]);
        expect(await File('${saved.path}.part').exists(), isFalse);

        // The update is retried on the next open.
        client.interceptors.clear();
        respond();
        expect(await openCourseMaterialEntryWithStatus(updated),
            CourseMaterialOpenResult.opened);
        expect(await saved.readAsBytes(), [37, 80, 68, 70, 45, 49]);
      });
    }

    test('a failed login keeps the previous file', () async {
      when(() => wrapper.ensureLoggedIn()).thenAnswer((_) async => false);
      expect(await openCourseMaterialEntryWithStatus(updated),
          CourseMaterialOpenResult.openedOutdated);
      expect(await saved.readAsBytes(), [1, 2, 3]);
      expect(requests, 0);
    });

    test('a file saved before versions were recorded is revalidated once',
        () async {
      SharedPreferences.setMockInitialValues({});
      respond();
      expect(await openCourseMaterialEntryWithStatus(old),
          CourseMaterialOpenResult.opened);
      expect(requests, 1);
      expect(await openCourseMaterialEntryWithStatus(old),
          CourseMaterialOpenResult.opened);
      expect(requests, 1);
    });
  });
}
