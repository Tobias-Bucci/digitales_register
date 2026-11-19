import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/middleware/middleware.dart' as middleware;
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

class _OnlineWrapper extends Wrapper {
  @override
  Future<bool> refreshNoInternet() async => noInternet = false;
}

const _configPage = '''
<script>var currentUserId=1;
var config = { auto_logout_seconds: 300, };</script>
<img id="navigationProfilePicture" src="profile.png">Test User<
''';

Map<String, Object?> _course(int id, String title) => {
      'id': id,
      'course': {'id': id, 'title': title},
      'topics': [
        {
          'id': id * 10,
          'courseContentId': id,
          'title': 'Topic',
          'entries': [
            {
              'id': id * 100,
              'courseContentId': id,
              'type': 'file',
              'file': 'f.pdf',
              'title': '$title file',
              'originalName': '$title.pdf',
            },
          ],
        },
      ],
    };

/// Answers like the school server: a subject without a course gets an empty
/// body with status 200 (until autumn 2026) or, since then, status 403 with
/// a JSON object that only holds an `error` message (#150).
class _SchoolServer implements HttpClientAdapter {
  /// Course answers by subject id: a map, `''` for an empty body, `'403'`
  /// for the refusal of a subject without a course, or an int for a failed
  /// request with that status.
  final requestedSubjects = <Object?>[];

  final courses = <int, Object>{
    2: _course(10, 'Math course'),
    3: '',
    4: _course(12, 'Latin course'),
  };

  ResponseBody _json(Object? data) =>
      ResponseBody.fromString(jsonEncode(data), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path;
    if (path.endsWith('api/auth/login')) {
      return ResponseBody.fromString(jsonEncode({'loggedIn': true}), 200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'set-cookie': ['session=test; Path=/'],
          });
    }
    if (path.endsWith('/v2/')) {
      return ResponseBody.fromString(_configPage, 200, headers: {
        Headers.contentTypeHeader: ['text/html'],
      });
    }
    if (path.contains('api/calendar/student')) {
      return _json([
        for (final subjectId in courses.keys)
          {'classId': 1, 'subjectId': subjectId, 'subjectName': 'S$subjectId'},
      ]);
    }
    if (path.contains('api/lesson/student')) return _json(<Object?>[]);
    if (path.contains('api/courseContent/getCourse')) {
      final args = options.data as Map;
      requestedSubjects.add(args['subjectId']);
      final answer = courses[args['subjectId']];
      if (answer == '403') {
        // Synthetic message: only the shape of the real answer matters.
        return ResponseBody.fromString(jsonEncode({'error': 'synthetic'}), 403,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            });
      }
      if (answer is int) {
        return ResponseBody.fromString('', answer);
      }
      if (answer == '') {
        return ResponseBody.fromString('', 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      }
      return _json(answer);
    }
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _SchoolServer server;

  setUp(() async {
    await bootstrapTestEnvironment();
    server = _SchoolServer();
    final session = _OnlineWrapper()..safeMode = false;
    session.dio.httpClientAdapter = server;
    middleware.wrapper = session;
    addTearDown(() => session.logout(hard: true));
    await session.login('user', 'password', null, testServerUrl,
        logout: () {},
        configLoaded: () => null,
        relogin: () {},
        addProtocolItem: (_) {});
  });
  tearDown(resetTestState);

  test('a subject without a course does not hide the other courses', () async {
    final snapshot = await refreshCourseMaterialsPayload();
    expect(
      courseMaterialCoursesFromPayload(snapshot!.payload).map((c) => c.title),
      ['Math course', 'Latin course'],
    );
  });

  test('a course request the server rejects still counts as missing', () async {
    server.courses[3] = 500;
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
  });

  test('a subject the server refuses with 403 does not hide the others',
      () async {
    server.courses[3] = '403';
    final snapshot = await refreshCourseMaterialsPayload();
    expect(
      courseMaterialCoursesFromPayload(snapshot!.payload).map((c) => c.title),
      ['Math course', 'Latin course'],
    );
    // Every subject was asked, not only the ones before the refusal.
    expect(server.requestedSubjects.toSet(), {2, 3, 4});
    final cached = await loadCachedCourseMaterialsPayload();
    expect(cached!.payload, hasLength(2));
  });

  test('only refused subjects make an empty list, not an error', () async {
    server.courses
      ..clear()
      ..[3] = '403'
      ..[5] = '403';
    final snapshot = await refreshCourseMaterialsPayload();
    expect(snapshot!.payload, isEmpty);
  });

  test('a refused course that the saved snapshot holds keeps the snapshot',
      () async {
    await refreshCourseMaterialsPayload();
    server.courses[2] = '403';
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
    final cached = await loadCachedCourseMaterialsPayload();
    expect(
      courseMaterialCoursesFromPayload(cached!.payload).map((c) => c.title),
      ['Math course', 'Latin course'],
    );
  });

  test('a stale empty snapshot does not hide a successful load', () async {
    server.courses
      ..clear()
      ..[3] = '403';
    expect((await refreshCourseMaterialsPayload())!.payload, isEmpty);
    server.courses[2] = _course(10, 'Math course');
    await refreshCourseMaterialsPayload();
    final cached = await loadCachedCourseMaterialsPayload();
    expect(
      courseMaterialCoursesFromPayload(cached!.payload).map((c) => c.title),
      ['Math course'],
    );
  });

  test('a refused request elsewhere still fails as before', () async {
    server.courses[3] = 401;
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
  });
}
