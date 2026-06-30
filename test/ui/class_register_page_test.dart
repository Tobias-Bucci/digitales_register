import 'dart:convert';

import 'package:dr/app_state.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/ui/class_register_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('renders lesson register entries from api payload',
      (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.settingsState.languageCode = 'de',
      ),
    );
    final lesson = ClassRegisterLesson.fromJson({
      'date': '2026-06-12',
      'hour': 1,
      'toHour': 1,
      'timeStart': 24600,
      'timeEnd': 27600,
      'className': '5AT',
      'subject': {'name': 'Projektmanagement'},
      'lessonTypeName': 'Fachunterricht',
      'signedByOne': true,
      'rooms': [
        {'name': 'R 5AT'},
      ],
      'teachers': [
        {'firstName': 'Alexander', 'lastName': 'Larcher'},
      ],
      'lessonContents': [
        {'name': 'Abschlussfeier', 'typeName': 'Fachunterricht'},
      ],
      'homeworkExams': const [],
      'grades': const [],
      'missingStudents': const [],
    });

    await pumpApp(
      tester,
      store: store,
      home: ClassRegisterPage(key: UniqueKey(), loader: () async => [lesson]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Klassenbuch'), findsWidgets);
    expect(find.text('Projektmanagement'), findsOneWidget);
    expect(find.text('5AT'), findsOneWidget);
    expect(find.text('R 5AT'), findsOneWidget);
    expect(find.text('1 Inhalt'), findsOneWidget);
    expect(find.textContaining('Abschlussfeier'), findsOneWidget);
    expect(find.text('Lehrpersonen: Alexander Larcher'), findsOneWidget);
  });

  test('class register snapshots keep parseable payloads and fingerprints', () {
    final payload = [_lessonPayload(subject: 'Projektmanagement')];
    final cached = ClassRegisterPayloadSnapshot.fromPayload(
      payload,
      fetchedAt: DateTime(2026, 6, 12, 8),
    );
    expect(cached.payload, hasLength(1));
    expect(
      ClassRegisterLesson.fromJson(cached.payload.first).subjectName,
      'Projektmanagement',
    );
    final refreshed = ClassRegisterPayloadSnapshot.fromPayload(
      payload,
      fetchedAt: DateTime(2026, 6, 12, 9),
    );

    expect(refreshed.fingerprint, cached.fingerprint);
  });

  test('class register cache serializes and restores snapshots', () {
    final cached = ClassRegisterPayloadSnapshot.fromPayload(
      [_lessonPayload(subject: 'Projektmanagement')],
      fetchedAt: DateTime(2026, 6, 12, 8),
    );
    final jsonRestored = ClassRegisterPayloadSnapshot.tryParse(
      json.encode(cached.toJson()),
    );
    expect(jsonRestored, isNotNull);
    expect(
      ClassRegisterLesson.fromJson(jsonRestored!.payload.first).subjectName,
      'Projektmanagement',
    );
  });
}

Map<String, dynamic> _lessonPayload({required String subject}) {
  return {
    'date': '2026-06-12',
    'hour': 1,
    'toHour': 1,
    'timeStart': 24600,
    'timeEnd': 27600,
    'className': '5AT',
    'subject': {'name': subject},
    'lessonTypeName': 'Fachunterricht',
    'signedByOne': true,
    'rooms': [
      {'name': 'R 5AT'},
    ],
    'teachers': [
      {'firstName': 'Alexander', 'lastName': 'Larcher'},
    ],
    'lessonContents': [
      {'name': 'Abschlussfeier', 'typeName': 'Fachunterricht'},
    ],
    'homeworkExams': const [],
    'grades': const [],
    'missingStudents': const [],
  };
}
