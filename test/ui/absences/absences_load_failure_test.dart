import 'dart:async';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absences_page_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/test_harness.dart';

const _absencesUrl = 'api/student/dashboard/absences';

Map<String, Object?> _snapshot() => <String, Object?>{
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
    };

void main() {
  late MockWrapper mockWrapper;
  late List<Object? Function()> responses;

  setUp(() async {
    mockWrapper = MockWrapper();
    when(() => mockWrapper.loginAddress).thenReturn(testLoginAddress);
    when(() => mockWrapper.noInternet).thenReturn(false);
    responses = [];
    when(() => mockWrapper.send(_absencesUrl))
        .thenAnswer((_) async => responses.removeAt(0)());
    await bootstrapTestEnvironment(wrapperOverride: mockWrapper);
  });

  tearDown(resetTestState);

  Future<Store<AppState, AppStateBuilder, AppActions>> pumpPage(
      WidgetTester tester, String language,
      {required List<Object? Function()> answers}) async {
    responses.addAll(answers);
    final store = createStore(
      initialState: AppState((b) => b.settingsState.languageCode = language),
      withMiddleware: true,
    );
    addTearDown(store.dispose);
    await pumpApp(tester, store: store, home: const AbsencesPageContainer());
    unawaited(store.actions.absencesActions.load());
    await settleFor(tester);
    return store;
  }

  testWidgets('initial failure shows an error with retry instead of a spinner',
      (tester) async {
    await pumpPage(tester, 'en', answers: [
      () => null,
      _snapshot,
    ]);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Absences could not be loaded.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settleFor(tester);

    verify(() => mockWrapper.send(_absencesUrl)).called(2);
    expect(find.text('Absences could not be loaded.'), findsNothing);
    expect(find.text('No absences yet'), findsOneWidget);
    expect(
        find.text('Absences could not be refreshed. Showing the last '
            'loaded data.'),
        findsNothing);
  });

  testWidgets('a parser failure is reported the same way', (tester) async {
    await pumpPage(tester, 'en', answers: [
      () => <String, Object?>{'statistics': 'malformed'},
    ]);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Absences could not be loaded.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a later refresh failure keeps the data and shows a warning',
      (tester) async {
    when(() => mockWrapper.send('api/student/dashboard/absence_future',
        args: any(named: 'args'))).thenAnswer((_) async => '{"success":true}');
    final store = await pumpPage(tester, 'en', answers: [
      _snapshot,
      () => throw StateError('synthetic refresh failure'),
      _snapshot,
    ]);
    expect(find.text('No absences yet'), findsOneWidget);

    // Recording an absence refreshes the list, which fails this time.
    await store.actions.absencesActions
        .addFutureAbsence(<String, dynamic>{'futureAbsence': {}});
    await settleFor(tester);

    expect(find.text('No absences yet'), findsOneWidget);
    expect(
        find.text('Absences could not be refreshed. Showing the last '
            'loaded data.'),
        findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settleFor(tester);
    expect(
        find.text('Absences could not be refreshed. Showing the last '
            'loaded data.'),
        findsNothing);
    expect(find.text('No absences yet'), findsOneWidget);
  });

  for (final (language, message, retry) in [
    ('de', 'Absenzen konnten nicht geladen werden.', 'Erneut versuchen'),
    ('it', 'Impossibile caricare le assenze.', 'Riprova'),
    ('lld', 'Al ne se nia podü ciarié les assënzes.', "Pröia d'agof"),
  ]) {
    testWidgets('load failure is localized in $language', (tester) async {
      await pumpPage(tester, language, answers: [() => null]);
      expect(find.text(message), findsOneWidget);
      expect(find.text(retry), findsOneWidget);
    });
  }
}
