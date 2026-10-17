import 'dart:async';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fixtures.dart';
import '../support/test_harness.dart';

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  for (final confirm in [false, true]) {
    testWidgets('reminder server delete survives unmount: confirm=$confirm',
        (tester) async {
      final mockWrapper = MockWrapper();
      final response = Completer<Map<String, Object?>>();
      when(() => mockWrapper.noInternet).thenReturn(false);
      when(() => mockWrapper.send(
            'api/student/dashboard/delete_reminder',
            args: {'id': 7},
          )).thenAnswer((_) => response.future);
      wrapper = mockWrapper;
      final store = createStore(
        initialState: AppState((b) {
          b.settingsState.askWhenDelete = confirm;
          b.dashboardState.allDays = ListBuilder([
            buildDay(date: UtcDateTime(2050), homework: [
              buildHomework(
                  id: 7, type: HomeworkType.homework, deleteable: true),
            ]),
          ]);
        }),
        withMiddleware: true,
      );
      await pumpApp(tester, store: store, home: DaysContainer());
      await settleFor(tester);
      await tester.tap(find.byIcon(Icons.close));
      if (confirm) {
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Löschen'));
      } else {
        // A second click must share the pending operation.
        await tester.tap(find.byIcon(Icons.close));
      }
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      verify(() => mockWrapper.send(
            'api/student/dashboard/delete_reminder',
            args: {'id': 7},
          )).called(1);
      expect(store.state.dashboardState.allDays!.single.homework, isEmpty);
      response.complete({'success': true});
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final favorites in [false, true]) {
    for (final unmount in [false, true]) {
      testWidgets('settings delete: favorites=$favorites, unmount=$unmount',
          (tester) async {
        tester.view.physicalSize = const Size(1400, 2800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = createStore(initialState: AppState((b) {
          b.settingsState.languageCode = AppLanguage.en.code;
          b.settingsState.ignoreForGradesAverage = ListBuilder(['Math', 'Art']);
          b.settingsState.favoriteSubjects = ListBuilder(['Math', 'Art']);
        }));
        final saves = <List<String>>[];
        final action = favorites
            ? store.actions.settingsActions.favoriteSubjects
            : store.actions.settingsActions.ignoreSubjectsForAverage;
        action.setDispatcher((action) {
          saves.add((action.payload as BuiltList<String>).toList());
        });
        await pumpApp(tester, store: store, home: SettingsPageContainer());
        await settleFor(tester);
        final tile = find.byKey(Key(favorites
            ? 'settings-favorite-subjects-tile'
            : 'settings-grades-tile'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        final remove = find.descendant(
          of: find.widgetWithText(ListTile, 'Math'),
          matching: find.byIcon(Icons.close),
        );
        await tester.tap(remove);
        await tester.tap(remove);
        await tester.pump();
        if (unmount) {
          await tester.pumpWidget(const SizedBox());
        }
        await tester.pumpAndSettle();
        expect(saves, [
          ['Art']
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
