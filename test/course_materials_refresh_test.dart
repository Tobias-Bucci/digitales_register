import 'package:dr/app_state.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/ui/course_materials_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

const _math = {'classId': 1, 'subjectId': 2, 'subjectName': 'Math'};
const _art = {'classId': 1, 'subjectId': 3, 'subjectName': 'Art'};

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
              'originalName': '$title.pdf',
            },
          ],
        },
      ],
    };

void main() {
  late MockWrapper server;
  late List<Object?> calendar;
  late Object? lessons;
  late Map<int, Object?> courses;

  setUp(() async {
    server = MockWrapper();
    when(() => server.user).thenReturn('synthetic');
    when(() => server.url).thenReturn('https://school.invalid');
    when(() => server.loginAddress)
        .thenReturn('https://school.invalid/v2/api/auth/login');
    when(() => server.demoMode).thenReturn(false);
    when(() => server.noInternet).thenReturn(false);
    when(() => server.send(any(), method: 'GET')).thenAnswer((_) async => '');
    calendar = [
      [_math, _art],
    ];
    lessons = <Object?>[];
    courses = {2: _course(10, 'Math course'), 3: _course(11, 'Art course')};
    when(() => server.send('api/calendar/student', args: any(named: 'args')))
        .thenAnswer((_) async => calendar.isEmpty ? null : calendar.first);
    when(() => server.send('api/lesson/student'))
        .thenAnswer((_) async => lessons);
    when(() => server.send('api/courseContent/getCourse',
        args: any(named: 'args'))).thenAnswer((invocation) async {
      final args = invocation.namedArguments[#args] as Map<String, Object?>;
      return courses[args['subjectId']];
    });
    await bootstrapTestEnvironment(wrapperOverride: server);
  });
  tearDown(resetTestState);

  Future<List<String>> cachedTitles() async {
    final cached = await loadCachedCourseMaterialsPayload();
    return courseMaterialCoursesFromPayload(cached!.payload)
        .map((c) => c.title)
        .toList();
  }

  test('a failing course keeps the complete cached snapshot', () async {
    await refreshCourseMaterialsPayload();
    expect(await cachedTitles(), ['Art course', 'Math course']);

    courses[3] = null;
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
    expect(await cachedTitles(), ['Art course', 'Math course']);
  });

  test('all courses failing keeps the cache instead of an empty success',
      () async {
    await refreshCourseMaterialsPayload();
    courses = {2: null, 3: null};
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
    expect(await cachedTitles(), hasLength(2));
  });

  test('a malformed course response fails without touching the cache',
      () async {
    await refreshCourseMaterialsPayload();
    courses[3] = 'unexpected';
    await expectLater(refreshCourseMaterialsPayload(), throwsA(anything));
    expect(await cachedTitles(), hasLength(2));
  });

  test('a complete refresh may replace the snapshot with no courses', () async {
    await refreshCourseMaterialsPayload();
    calendar = [<Object?>[]];
    final snapshot = await refreshCourseMaterialsPayload();
    expect(snapshot!.payload, isEmpty);
    expect(await cachedTitles(), isEmpty);
  });

  test('a complete refresh may drop a course that no longer exists', () async {
    await refreshCourseMaterialsPayload();
    calendar = [
      [_math],
    ];
    await refreshCourseMaterialsPayload();
    expect(await cachedTitles(), ['Math course']);
  });

  test('a failed discovery request that hides a cached course keeps the cache',
      () async {
    await refreshCourseMaterialsPayload();
    // The calendar fails and only the class register is available.
    calendar = [];
    lessons = [_math];
    await expectLater(refreshCourseMaterialsPayload(),
        throwsA(isA<CourseMaterialsIncompleteException>()));
    expect(await cachedTitles(), hasLength(2));
  });

  test('a failed discovery request that hides nothing still refreshes',
      () async {
    await refreshCourseMaterialsPayload();
    lessons = null;
    courses[2] = _course(10, 'Math course v2');
    await refreshCourseMaterialsPayload();
    expect(await cachedTitles(), ['Art course', 'Math course v2']);
  });

  group('page', () {
    PagePayloadSnapshot<List<Map<String, dynamic>>> snapshot() =>
        PagePayloadSnapshot<List<Map<String, dynamic>>>.fromPayload(
          courseMaterialCoursesToPayload([
            CourseMaterialCourse.fromJson(
              _course(10, 'Math course'),
              CourseMaterialSource.fromJson(_math),
            ),
          ]),
        );

    Future<void> pumpPage(
      WidgetTester tester, {
      PagePayloadSnapshot<List<Map<String, dynamic>>>? cached,
      required Object error,
    }) async {
      final store = createStore(
        initialState: AppState((b) => b..settingsState.languageCode = 'en'),
      );
      await tester.pumpWidget(buildTestApp(
        store: store,
        home: CourseMaterialsPage(
          cachedLoader: () async => cached,
          refreshLoader: () async => throw error,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an incomplete refresh shows saved courses and a warning',
        (tester) async {
      await pumpPage(tester,
          cached: snapshot(),
          error: const CourseMaterialsIncompleteException());
      expect(find.text('Math course'), findsOneWidget);
      expect(
        find.text('Not all courses could be loaded. '
            'Showing the last completely loaded version.'),
        findsOneWidget,
      );
    });

    testWidgets('another refresh failure is not hidden behind saved courses',
        (tester) async {
      await pumpPage(tester,
          cached: snapshot(), error: const CourseMaterialsLoadException());
      expect(find.text('Math course'), findsOneWidget);
      expect(
        find.text('Course materials could not be updated. '
            'Showing the last saved version.'),
        findsOneWidget,
      );
    });

    testWidgets('an incomplete first load is reported as an error',
        (tester) async {
      await pumpPage(tester, error: const CourseMaterialsIncompleteException());
      expect(
          find.text('Course materials could not be loaded.'), findsOneWidget);
      expect(find.text('Not all courses could be loaded.'), findsOneWidget);
    });
  });
}
