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

import 'package:built_collection/built_collection.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
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

  testWidgets('justifyAbsence sends absence group payload and reloads data',
      (tester) async {
    final absenceGroup = AbsenceGroup(
      (b) => b
        ..date = UtcDateTime(2026, 4, 13)
        ..note = null
        ..reason = null
        ..reasonSignature = null
        ..reasonTimestamp = null
        ..reasonUser = null
        ..justified = AbsenceJustified.notYetJustified
        ..selfdeclId = null
        ..selfdeclInput = null
        ..hours = 2
        ..minutes = 0
        ..absences = ListBuilder<Absence>(<Absence>[
          Absence(
            (b) => b
              ..id = 44509
              ..minutes = 50
              ..minutesCameTooLate = 0
              ..minutesLeftTooEarly = 0
              ..date = UtcDateTime(2026, 4, 13)
              ..hour = 9
              ..justified = AbsenceJustified.notYetJustified
              ..note = null
              ..reason = null
              ..reasonSignature = null
              ..reasonTimestamp = null
              ..reasonUser = null
              ..selfdeclId = null
              ..selfdeclInput = null,
          ),
          Absence(
            (b) => b
              ..id = 44533
              ..minutes = 50
              ..minutesCameTooLate = 0
              ..minutesLeftTooEarly = 0
              ..date = UtcDateTime(2026, 4, 13)
              ..hour = 8
              ..justified = AbsenceJustified.notYetJustified
              ..note = null
              ..reason = null
              ..reasonSignature = null
              ..reasonTimestamp = null
              ..reasonUser = null
              ..selfdeclId = null
              ..selfdeclInput = null,
          ),
        ]),
    );

    when(
      () => mockWrapper.send(
        'api/student/dashboard/absence_reason',
        args: any(named: 'args'),
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
      store.actions.absencesActions.justifyAbsence(
        <String, dynamic>{
          'absenceGroup': absenceGroup,
          'reason': 'Bauchschmerzen',
          'signature': 'Tobias Bucci',
        },
      ),
      completes,
    );
    await tester.pump();

    final captured = verify(
      () => mockWrapper.send(
        'api/student/dashboard/absence_reason',
        args: captureAny(named: 'args'),
      ),
    ).captured.single as Map<String, dynamic>;

    expect(captured['absenceGroup']['group'][0]['id'], 44509);
    expect(captured['absenceGroup']['group'][1]['id'], 44533);
    expect(captured['absenceGroup']['reason'], 'Bauchschmerzen');
    expect(captured['absenceGroup']['reason_signature'], 'Tobias Bucci');
    expect(captured['absenceGroup']['date'], '2026-04-13');
    expect(captured['absenceGroup']['selfdecl_id'], 0);
    expect(captured['absenceGroup']['selfdecl_input'], '');
    expect(captured['absenceGroup']['formattedDateObject']['startHour'], 8);
    expect(captured['absenceGroup']['formattedDateObject']['endHour'], 9);
    expect(captured['absenceGroup']['details'], '2 Einheiten');

    verify(() => mockWrapper.send('api/student/dashboard/absences')).called(1);
  });
}
