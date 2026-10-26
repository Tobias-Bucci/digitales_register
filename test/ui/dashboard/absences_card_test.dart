import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/dashboard_overview.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  AbsencesState populated() {
    final start = appClock.now.add(const Duration(days: 3));
    return AbsencesState(
      (b) => b
        ..statistic.counter = 9
        ..statistic.notJustified = 2
        ..statistic.delayed = 1
        ..statistic.counterForSchool = 3
        ..statistic.percentage = '4,5'
        ..futureAbsences = ListBuilder<FutureAbsence>([
          FutureAbsence(
            (f) => f
              ..justified = AbsenceJustified.justified
              ..reason = 'Arzt'
              ..startDate = start
              ..endDate = start
              ..startHour = 1
              ..endHour = 3,
          ),
        ]),
    );
  }

  testWidgets('shows counters, rate and the next planned absence',
      (tester) async {
    await pumpApp(
      tester,
      store: createStore(),
      home: Scaffold(body: DashboardAbsencesCard(state: populated())),
    );
    await settleFor(tester);

    expect(find.text('9 Absenzen'), findsOneWidget);
    expect(find.text('2 nicht entschuldigt'), findsOneWidget);
    expect(find.text('1 Verspätung'), findsOneWidget);
    expect(find.text('3 für die Schule'), findsOneWidget);
    expect(find.text('4,5 % abwesend'), findsOneWidget);
    expect(find.textContaining('Geplant:'), findsOneWidget);
    expect(find.textContaining('Arzt'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state', (tester) async {
    await pumpApp(
      tester,
      store: createStore(),
      home: Scaffold(
        body: DashboardAbsencesCard(
          state: AbsencesState(
            (b) => b
              ..statistic.counter = 0
              ..statistic.notJustified = 0,
          ),
        ),
      ),
    );
    await settleFor(tester);

    expect(find.text('0 Absenzen'), findsOneWidget);
    expect(find.text('Bisher immer da – weiter so!'), findsOneWidget);
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
  });

  for (final language in AppLanguage.values) {
    for (final (name, mode, amoled) in [
      ('light', ThemeMode.light, false),
      ('dark', ThemeMode.dark, false),
      ('amoled', ThemeMode.dark, true),
    ]) {
      testWidgets('fits a narrow half-width card (${language.code}, $name)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpApp(
          tester,
          store: createStore(
            initialState: AppState(
              (b) => b.settingsState.languageCode = language.code,
            ),
          ),
          themeMode: mode,
          darkTheme: themeController.buildTheme(
            brightness: Brightness.dark,
            amoledMode: amoled,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 150,
                child: DashboardAbsencesCard(state: populated()),
              ),
            ),
          ),
        );
        await settleFor(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
