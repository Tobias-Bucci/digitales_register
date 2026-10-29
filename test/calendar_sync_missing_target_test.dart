import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

const _school = CalendarSyncCalendar(
  id: 12,
  displayName: 'Synthetic school calendar',
  accountName: 'school@example.invalid',
  ownerAccount: 'school@example.invalid',
  isPrimary: false,
);
const _other = CalendarSyncCalendar(
  id: 55,
  displayName: 'Synthetic other calendar',
  accountName: 'other@example.invalid',
  ownerAccount: 'other@example.invalid',
  isPrimary: true,
);
const _missingLabel =
    'The selected calendar is no longer available. Please choose a new '
    'target calendar.';

void main() {
  late List<CalendarSyncCalendar> writable;
  late List<CalendarSyncUpsertRequest> writes;
  late List<int> deletes;

  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 9));
    isAndroidOverride = () => true;
    writable = [_other];
    writes = [];
    deletes = [];
    CalendarSyncService.requestPermissionOverride = () async => true;
    CalendarSyncService.getWritableCalendarsOverride = () async => writable;
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 55;
    CalendarSyncService.upsertEventOverride = (request) async {
      writes.add(request);
      return 900 + writes.length;
    };
    CalendarSyncService.deleteEventOverride = (id) async => deletes.add(id);
  });
  tearDown(resetTestState);

  AppState enabledState({int? calendarId = 12}) => AppState(
        (b) => b
          ..settingsState.languageCode = 'en'
          ..settingsState.calendarSyncEnabled = true
          ..settingsState.calendarSyncCalendarId = calendarId
          ..dashboardState.allDays = ListBuilder<Day>([
            buildDay(
              date: UtcDateTime(2026, 4, 10),
              homework: [
                buildHomework(
                  id: 77,
                  title: 'Synthetic private school task',
                  type: HomeworkType.homework,
                ),
              ],
            ),
          ]),
      );

  group('reconcile', () {
    test('never writes to another calendar when the selected one is missing',
        () async {
      expect(await CalendarSyncService.reconcile(enabledState()), isFalse);
      expect(writes, isEmpty);
      expect(deletes, isEmpty);
      expect(
          await CalendarSyncService.isSelectedCalendarMissing(enabledState()),
          isTrue);
    });

    test('a calendar losing write access stops the sync of tracked events',
        () async {
      writable = [_school, _other];
      expect(await CalendarSyncService.reconcile(enabledState()), isTrue);
      expect(writes.single.calendarId, 12);

      // The account of calendar 12 is removed; the dashboard item changes.
      writable = [_other];
      writes.clear();
      final changed = enabledState()
          .rebuild((b) => b.dashboardState.allDays = ListBuilder<Day>([
                buildDay(date: UtcDateTime(2026, 4, 10), homework: [
                  buildHomework(
                      id: 77,
                      title: 'Changed task',
                      type: HomeworkType.homework),
                ]),
              ]));
      expect(await CalendarSyncService.reconcile(changed), isFalse);
      expect(writes, isEmpty);
      expect(deletes, isEmpty);
    });

    test('no writable calendar at all writes nothing', () async {
      writable = [];
      expect(await CalendarSyncService.reconcile(enabledState()), isFalse);
      expect(writes, isEmpty);
    });

    test('a new valid selection resumes the sync', () async {
      expect(await CalendarSyncService.reconcile(enabledState()), isFalse);
      expect(await CalendarSyncService.reconcile(enabledState(calendarId: 55)),
          isTrue);
      expect(writes.single.calendarId, 55);
      expect(
          await CalendarSyncService.isSelectedCalendarMissing(
              enabledState(calendarId: 55)),
          isFalse);
    });

    test('without an explicit selection the default calendar is used',
        () async {
      expect(
          await CalendarSyncService.reconcile(enabledState(calendarId: null)),
          isTrue);
      expect(writes.single.calendarId, 55);
      expect(
          await CalendarSyncService.isSelectedCalendarMissing(
              enabledState(calendarId: null)),
          isFalse);
    });

    test('a queued reconcile for another account uses its own selection',
        () async {
      writable = [_school];
      final first = CalendarSyncService.reconcile(enabledState());
      // The second account selected calendar 55, which is not available.
      final second =
          CalendarSyncService.reconcile(enabledState(calendarId: 55));
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(writes.map((w) => w.calendarId), [12]);
    });
  });

  testWidgets('changing the language reports the missing calendar',
      (tester) async {
    final store =
        createStore(initialState: enabledState(), withMiddleware: true);
    await pumpApp(tester, store: store, home: const Scaffold());
    await tester
        .runAsync(() => store.actions.settingsActions.setLanguage('en'));
    await tester.pump();
    expect(
      find.text('The selected calendar is no longer available. Nothing is '
          'synchronized until you choose a new target calendar in the '
          'settings.'),
      findsOneWidget,
    );
    expect(writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await store.dispose();
  });

  group('settings', () {
    Future<void> openPicker(WidgetTester tester, AppState state) async {
      tester.view.physicalSize = const Size(1400, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = createStore(initialState: state);
      await pumpApp(tester, store: store, home: SettingsPageContainer());
      await tester.pumpAndSettle();
      final details =
          find.byKey(const Key('settings-calendar-sync-details-tile'));
      await tester.scrollUntilVisible(details, 400);
      expect(find.descendant(of: details, matching: find.text(_missingLabel)),
          findsOneWidget);
      await tester.tap(details);
      await tester.pumpAndSettle();
      final picker = find.byKey(const Key('calendar-sync-calendar-picker'));
      expect(find.descendant(of: picker, matching: find.text(_missingLabel)),
          findsOneWidget);
      await tester.tap(picker);
      await tester.pumpAndSettle();
    }

    testWidgets('the picker does not confirm a missing calendar',
        (tester) async {
      await openPicker(tester, enabledState());
      expect(find.byType(RadioListTile<int>), findsOneWidget);
      final select = find.widgetWithText(ElevatedButton, 'Select');
      expect(tester.widget<ElevatedButton>(select).onPressed, isNull);
      await tester.tap(select);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(RadioListTile<int>), findsOneWidget);
    });

    testWidgets('choosing a calendar replaces the missing selection',
        (tester) async {
      await openPicker(tester, enabledState());
      await tester.tap(find.text('Synthetic other calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Select'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RadioListTile<int>), findsNothing);
      expect(find.text(_missingLabel), findsNothing);
      expect(find.textContaining('Synthetic other calendar'), findsWidgets);
    });
  });
}
