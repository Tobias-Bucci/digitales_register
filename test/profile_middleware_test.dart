import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
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
      'sendNotificationEmails keeps the previous state when the server logs out unexpectedly',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/profile/updateNotificationSettings',
        args: <String, Object?>{'notificationsEnabled': false},
      ),
    ).thenThrow(UnexpectedLogoutException());

    final store = createStore(
      initialState: AppState(
        (b) {
          b.profileState.sendNotificationEmails = true;
        },
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(body: SizedBox()),
    );
    await tester.pump();

    await expectLater(
      store.actions.profileActions.sendNotificationEmails(false),
      completes,
    );
    await tester.pump();

    expect(store.state.profileState.sendNotificationEmails, isTrue);
    verify(
      () => mockWrapper.send(
        'api/profile/updateNotificationSettings',
        args: <String, Object?>{'notificationsEnabled': false},
      ),
    ).called(1);
  });

  testWidgets('updateCodiceFiscale stores the value and reloads the profile',
      (tester) async {
    when(
      () => mockWrapper.send(
        'api/profile/updateCodiceFiscale',
        args: <String, Object?>{
          'codiceFiscale': 'BCCTBS07S23B220B',
        },
      ),
    ).thenAnswer(
      (_) async => <String, Object?>{
        'error': null,
        'message': 'Steuernummer wurde geändert',
      },
    );
    when(() => mockWrapper.send('api/profile/get'))
        .thenAnswer((_) async => <String, Object?>{
              'name': 'Anna Rossi',
              'email': 'anna@example.com',
              'username': 'anna',
              'roleName': 'Schüler/in',
              'notificationsEnabled': false,
              'codiceFiscale': 'BCCTBS07S23B220B',
            });

    final store = createStore(withMiddleware: true);

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(body: SizedBox()),
    );
    await tester.pump();

    await expectLater(
      store.actions.profileActions.updateCodiceFiscale('BCCTBS07S23B220B'),
      completes,
    );
    await tester.pump();

    expect(store.state.profileState.codiceFiscale, 'BCCTBS07S23B220B');
    verify(
      () => mockWrapper.send(
        'api/profile/updateCodiceFiscale',
        args: <String, Object?>{
          'codiceFiscale': 'BCCTBS07S23B220B',
        },
      ),
    ).called(1);
    verify(() => mockWrapper.send('api/profile/get')).called(1);
  });

  testWidgets('pickAndUploadProfilePicture uploads bytes and reloads profile',
      (tester) async {
    final previousPicker = pickProfilePicture;
    pickProfilePicture = () async => const SelectedProfilePicture(
          bytes: <int>[1, 2, 3, 4],
          contentType: 'image/png',
          fileName: 'avatar.png',
        );
    addTearDown(() {
      pickProfilePicture = previousPicker;
    });

    when(
      () => mockWrapper.sendBytes(
        'api/profile/uploadProfilePicture',
        bytes: <int>[1, 2, 3, 4],
        contentType: 'image/png',
        fileName: 'avatar.png',
      ),
    ).thenAnswer(
      (_) async => <String, Object?>{
        'error': null,
        'name': 'uploaded-picture',
      },
    );
    when(() => mockWrapper.send('api/profile/get'))
        .thenAnswer((_) async => <String, Object?>{
              'name': 'Anna Rossi',
              'email': 'anna@example.com',
              'username': 'anna',
              'roleName': 'Schüler/in',
              'notificationsEnabled': false,
              'picture': 'uploaded-picture',
            });

    final store = createStore(withMiddleware: true);

    await pumpApp(
      tester,
      store: store,
      home: const Scaffold(body: SizedBox()),
    );
    await tester.pump();

    await expectLater(
      store.actions.profileActions.pickAndUploadProfilePicture(),
      completes,
    );
    await tester.pump();

    expect(store.state.profileState.picture, 'uploaded-picture');
    verify(
      () => mockWrapper.sendBytes(
        'api/profile/uploadProfilePicture',
        bytes: <int>[1, 2, 3, 4],
        contentType: 'image/png',
        fileName: 'avatar.png',
      ),
    ).called(1);
    verify(() => mockWrapper.send('api/profile/get')).called(1);
  });
}
