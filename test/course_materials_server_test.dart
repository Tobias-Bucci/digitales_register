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
/// body with status 200.
class _SchoolServer implements HttpClientAdapter {
  /// Course answers by subject id: a map, `''` for an empty body or an int
  /// for a failed request with that status.
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
      final answer = courses[args['subjectId']];
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

  test('a subject without a course does not hide the other courses',
      () async {
    final snapshot = await refreshCourseMaterialsPayload();
    expect(
      courseMaterialCoursesFromPayload(snapshot!.payload).map((c) => c.title),
      ['Math course', 'Latin course'],
    );
  });

  test('a course request the server rejects still counts as missing',
      () async {
    server.courses[3] = 500;
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
  });
}
