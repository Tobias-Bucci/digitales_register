import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

void main() {
  late MockWrapper mockWrapper;

  setUp(() async {
    mockWrapper = MockWrapper();
    when(() => mockWrapper.loginAddress).thenReturn(testLoginAddress);
    when(() => mockWrapper.noInternet).thenReturn(false);
    await bootstrapTestEnvironment(wrapperOverride: mockWrapper);
  });

  tearDown(resetTestState);

  testWidgets(
      'addFutureAbsence treats a JSON string success response as successful',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/student/dashboard/absence_future',
        args: <String, Object?>{
          'futureAbsence': <String, Object?>{
            'startDateObject': '2022-05-06T20:02:55.692Z',
            'startTime': 8,
            'endDateObject': '2022-05-06T20:02:55.692Z',
            'endTime': 10,
            'reason': 'Arzttermin',
            'reason_signature': 'Michael Debertol',
            'startDate': '2022-05-06',
            'endDate': '2022-05-06',
          },
        },
      ),
    ).thenAnswer((_) async => '{"success":true}');
    when(() => mockWrapper.send('api/student/dashboard/absences')).thenAnswer(
      (_) async => <String, Object?>{
        'absences': const <Object>[],
        'futureAbsences': const <Object>[],
        'canEdit': true,
        'statistics': <String, Object?>{
          'counter': 0,
          'counterForSchool': 0,
          'delayed': 0,
          'justified': 0,
          'notJustified': 0,
          'percentage': 0,
        },
      },
    );

    final store = createStore(withMiddleware: true);

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(body: SizedBox()),
    );
    await tester.pump();

    await expectLater(
      store.actions.absencesActions.addFutureAbsence(
        <String, dynamic>{
          'futureAbsence': <String, dynamic>{
            'startDateObject': '2022-05-06T20:02:55.692Z',
            'startTime': 8,
            'endDateObject': '2022-05-06T20:02:55.692Z',
            'endTime': 10,
            'reason': 'Arzttermin',
            'reason_signature': 'Michael Debertol',
            'startDate': '2022-05-06',
            'endDate': '2022-05-06',
          },
        },
      ),
      completes,
    );
    await tester.pump();

    verify(
      () => mockWrapper.send(
        'api/student/dashboard/absence_future',
        args: <String, Object?>{
          'futureAbsence': <String, Object?>{
            'startDateObject': '2022-05-06T20:02:55.692Z',
            'startTime': 8,
            'endDateObject': '2022-05-06T20:02:55.692Z',
            'endTime': 10,
            'reason': 'Arzttermin',
            'reason_signature': 'Michael Debertol',
            'startDate': '2022-05-06',
            'endDate': '2022-05-06',
          },
        },
      ),
    ).called(1);
    verify(() => mockWrapper.send('api/student/dashboard/absences')).called(1);
  });
}
