import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:open_file/open_file.dart';
import 'package:open_file/src/platform/linux_open_file.dart';

class _Wrapper extends Mock implements Wrapper {}

CourseMaterialEntry entry([String name = 'Prüfung mit Leerzeichen.pdf']) =>
    CourseMaterialEntry.fromJson({
      'id': 657,
      'courseContentId': 83,
      'type': 'file',
      'file': 'server.pdf',
      'originalName': name,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Dio client;
  late Wrapper previousWrapper;
  late DebugPrintCallback previousPrint;
  late List<String> logs;
  late int requests;
  late int opens;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('course-material-');
    previousWrapper = wrapper;
    final mock = _Wrapper();
    wrapper = mock;
    client = Dio();
    when(() => mock.dio).thenReturn(client);
    when(() => mock.baseAddress).thenReturn('https://school.example/v2/');
    when(() => mock.ensureLoggedIn()).thenAnswer((_) async => true);
    attachmentDownloadDirectoryOverride = () async => directory.path;
    courseMaterialPlatformOverride = TargetPlatform.windows;
    opens = 0;
    requests = 0;
    courseMaterialFileOpenerOverride = (path) async {
      opens++;
      expect(path, '${directory.path}/${entry().uniqueName}');
      expect(await File(path).exists(), isTrue);
      return OpenResult(type: ResultType.done, message: 'done');
    };
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
    client.close(force: true);
    await directory.delete(recursive: true);
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
      'uniqueName'
    ]) {
      expect(output, contains(field));
    }
    expect(output, isNot(contains('SECRET')));
    expect(output, isNot(contains('Authorization')));
    expect(output, isNot(contains('Cookie')));
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

  test('storage and opener exceptions are contained', () async {
    attachmentDownloadDirectoryOverride =
        () => Future.error(FileSystemException('SECRET'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(logs.join('\n'), contains('local_check'));
    expect(logs.join('\n'), isNot(contains('SECRET')));
    attachmentDownloadDirectoryOverride = () async => directory.path;
    respond();
    courseMaterialFileOpenerOverride =
        (_) => Future.error(StateError('SECRET'));
    expect(await openCourseMaterialEntry(entry()), isFalse);
    expect(logs.join('\n'), contains('StateError'));
    expect(logs.join('\n'), isNot(contains('SECRET')));
  });
}
