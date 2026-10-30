import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Wrapper extends Mock implements Wrapper {
  // Downloads capture the session they run in, which asks the wrapper.
  @override
  bool get isRetired => false;
}

const _url = 'https://school.example/v2/api/message/download';
const _loginPage = '<!DOCTYPE html><html><head><title>Login</title></head>'
    '<body><form></form></body></html>';
const _loginRedirect = '\n<script type="text/javascript">\n'
    'window.location = "https://school.digitalesregister.it/v2/login";\n'
    '</script>\n';
const _pdf = [37, 80, 68, 70, 45, 49];

typedef _Reply = ({int status, String type, List<int> bytes});

void main() {
  late Directory base;
  late Directory directory;
  late Dio client;
  late _Wrapper mock;
  late Wrapper previousWrapper;
  late List<_Reply> replies;
  late int requests;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('download-file-');
    previousWrapper = wrapper;
    mock = _Wrapper();
    wrapper = mock;
    when(() => mock.url).thenReturn('https://school.example');
    when(() => mock.user).thenReturn('max');
    // Files are kept in a folder of the account that is signed in.
    directory = Directory(
        '${base.path}/${AccountScope('https://school.example', 'max').fileId}');
    client = Dio();
    replies = [];
    requests = 0;
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final reply = replies[requests < replies.length ? requests : 0];
      requests++;
      handler.resolve(Response<List<int>>(
        requestOptions: options,
        statusCode: reply.status,
        data: reply.bytes,
        headers: Headers.fromMap({
          'content-type': [reply.type]
        }),
      ));
    }));
    when(() => mock.dio).thenReturn(client);
    when(() => mock.ensureLoggedIn()).thenAnswer((_) async => true);
    when(() => mock.ensureLoggedIn(
          isRetryAfterUnexpectedLogout:
              any(named: 'isRetryAfterUnexpectedLogout'),
          forceRelogin: any(named: 'forceRelogin'),
        )).thenAnswer((_) async => true);
    attachmentDownloadDirectoryOverride = () async => base.path;
  });

  tearDown(() async {
    wrapper = previousWrapper;
    attachmentDownloadDirectoryOverride = null;
    client.close(force: true);
    await base.delete(recursive: true);
  });

  File saved(String name) => File('${directory.path}/$name');

  _Reply reply(List<int> bytes,
          {int status = 200, String type = 'application/pdf'}) =>
      (status: status, type: type, bytes: bytes);

  Future<bool> download(String name) => downloadFile(_url, name, const {});

  test('stores a valid document', () async {
    replies = [reply(_pdf)];
    expect(await download('a.pdf'), isTrue);
    expect(await saved('a.pdf').readAsBytes(), _pdf);
    expect(await saved('a.pdf.part').exists(), isFalse);
  });

  test('failed authentication produces no request and no document', () async {
    when(() => mock.ensureLoggedIn()).thenAnswer((_) async => false);
    replies = [reply(_pdf)];
    expect(await download('a.pdf'), isFalse);
    expect(requests, 0);
    expect(await saved('a.pdf').exists(), isFalse);
  });

  for (final (name, body) in [
    ('login page', _loginPage),
    ('login redirect', _loginRedirect),
  ]) {
    test('HTTP 200 $name is rejected after bounded relogin retries', () async {
      replies = [reply(utf8.encode(body), type: 'text/html; charset=utf-8')];
      expect(await download('a.pdf'), isFalse);
      expect(requests, 3);
      expect(await saved('a.pdf').exists(), isFalse);
      verify(() => mock.ensureLoggedIn(
          isRetryAfterUnexpectedLogout: true, forceRelogin: false)).called(1);
      verify(() => mock.ensureLoggedIn(
          isRetryAfterUnexpectedLogout: true, forceRelogin: true)).called(1);
    });
  }

  test('login page is rejected even when the file should be HTML', () async {
    replies = [reply(utf8.encode(_loginPage), type: 'text/html')];
    expect(await download('page.html'), isFalse);
    expect(await saved('page.html').exists(), isFalse);
  });

  test('recovers once the relogin succeeds', () async {
    replies = [
      reply(utf8.encode(_loginPage), type: 'text/html'),
      reply(_pdf),
    ];
    expect(await download('a.pdf'), isTrue);
    expect(requests, 2);
    expect(await saved('a.pdf').readAsBytes(), _pdf);
  });

  test('aborts when the relogin fails', () async {
    when(() => mock.ensureLoggedIn(
          isRetryAfterUnexpectedLogout: true,
          forceRelogin: false,
        )).thenAnswer((_) async => false);
    replies = [reply(utf8.encode(_loginPage), type: 'text/html')];
    expect(await download('a.pdf'), isFalse);
    expect(requests, 1);
    expect(await saved('a.pdf').exists(), isFalse);
  });

  test('HTML or JSON error responses are rejected for other file types',
      () async {
    replies = [
      reply(utf8.encode('<html><body>Error</body></html>'), type: 'text/html')
    ];
    expect(await download('a.pdf'), isFalse);
    replies = [
      reply(utf8.encode('{"error":"denied"}'), type: 'application/json')
    ];
    requests = 0;
    expect(await download('b.docx'), isFalse);
    expect(await saved('a.pdf').exists(), isFalse);
    expect(await saved('b.docx').exists(), isFalse);
  });

  test('non-200 and empty responses are rejected', () async {
    replies = [reply(_pdf, status: 404)];
    expect(await download('a.pdf'), isFalse);
    replies = [reply(const [])];
    requests = 0;
    expect(await download('a.pdf'), isFalse);
    expect(await saved('a.pdf').exists(), isFalse);
  });

  test('valid HTML and JSON documents remain accepted', () async {
    const html = '<html><head><title>Notes</title></head><body></body></html>';
    replies = [reply(utf8.encode(html), type: 'text/html')];
    expect(await download('notes.html'), isTrue);
    expect(await saved('notes.html').readAsString(), html);

    const json = '{"grades":[1,2]}';
    replies = [reply(utf8.encode(json), type: 'application/json')];
    requests = 0;
    expect(await download('data.json'), isTrue);
    expect(await saved('data.json').readAsString(), json);
  });

  group('attachment names cannot leave the download directory', () {
    const hostileNames = [
      '../../../escaped.txt',
      r'..\..\escaped.txt',
      '/etc/passwd',
      r'C:\Windows\escaped.txt',
      r'\server\share\escaped.txt',
      'line\nbreak\u0000.txt',
      '..',
      '.',
      'trailing. . ',
      '',
    ];

    for (final name in hostileNames) {
      test('sanitizes ${jsonEncode(name)} to a single segment', () {
        final safe = safeFileNameSegment(name);
        expect(isSafeFileNameSegment(safe), isTrue);
        expect(safe, isNot(anyOf('.', '..')));
        expect(safe, isNot(contains('/')));
        expect(safe, isNot(contains(r'\')));
        expect(safe, isNot(contains(':')));
        expect(safe.codeUnits.every((c) => c >= 0x20 && c != 0x7F), isTrue);
      });

      if (name.isNotEmpty) {
        test('rejects the raw name ${jsonEncode(name)} for file operations',
            () async {
          expect(isSafeFileNameSegment(name), isFalse);
          replies = [reply(_pdf)];
          expect(await downloadFile(_url, name, const {}), isFalse);
          expect(requests, 0);
          expect(await canOpenFile(name), isFalse);
        });
      }
    }

    test('keeps ordinary names readable', () {
      expect(safeFileNameSegment('Aufgabe 1.pdf'), 'Aufgabe 1.pdf');
    });

    test('backend submission labels stay inside the download directory',
        () async {
      final outside = File(
          '${directory.parent.path}/escaped_${directory.uri.pathSegments.where((s) => s.isNotEmpty).last}.txt');
      final submission = GradeGroupSubmission((b) => b
        ..timestamp = UtcDateTime(2026, 10, 1)
        ..file = 'abc'
        ..originalName = '../${outside.uri.pathSegments.last}'
        ..typeName = 'file'
        ..id = 1
        ..gradeGroupId = 2
        ..userId = 3);
      final message = MessageAttachmentFile((b) => b
        ..type = 'file'
        ..originalName = 'x'
        ..file = r'..\..\escaped.txt'
        ..messageId = 4
        ..id = 5
        ..fileAvailable = true);
      final lesson = LessonContentSubmission((b) => b
        ..originalName = '/etc/escaped.txt'
        ..type = 'file'
        ..id = '6'
        ..lessonContentId = '7'
        ..date = UtcDateTime(2026, 10, 1));

      for (final name in [
        submission.uniqueName,
        message.uniqueName,
        lesson.uniqueName,
      ]) {
        expect(isSafeFileNameSegment(name), isTrue, reason: name);
        replies = [reply(_pdf)];
        requests = 0;
        expect(await download(name), isTrue);
        expect(await canOpenFile(name), isTrue);
        expect(await saved(name).readAsBytes(), _pdf);
      }
      expect(await outside.exists(), isFalse);
      expect(
        directory.listSync().map((e) => e.parent.path),
        everyElement(directory.path),
      );
    });

    test('does not write through a link planted in the download directory',
        () async {
      final target = File('${directory.path}_link_target.txt');
      await target.writeAsString('untouched');
      addTearDown(() async {
        if (await target.exists()) await target.delete();
      });
      try {
        await Link('${directory.path}/a.pdf').create(target.path);
      } on FileSystemException {
        markTestSkipped('Creating links is not permitted here');
        return;
      }
      replies = [reply(_pdf)];
      expect(await download('a.pdf'), isFalse);
      expect(await canOpenFile('a.pdf'), isFalse);
      expect(await target.readAsString(), 'untouched');
    });
  });
}
