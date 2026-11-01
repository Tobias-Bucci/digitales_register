import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/container/settings_page.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/platform_adapter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/test_harness.dart';

const _school = CalendarSyncCalendar(
  id: 12,
  displayName: 'Synthetic school calendar',
  accountName: 'school@example.invalid',
  ownerAccount: 'school@example.invalid',
  isPrimary: true,
);

void main() {
  late List<CalendarSyncCalendar> writable;
  late List<CalendarSyncUpsertRequest> writes;
  // The visible events of the device calendar.
  late Set<int> calendar;
  late List<List<int>> queries;
  late int nextId;
  late Future<List<int>?> Function(List<int> ids) query;

  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: UtcDateTime(2026, 4, 9));
    isAndroidOverride = () => true;
    writable = [_school];
    writes = [];
    calendar = {};
    queries = [];
    nextId = 901;
    query = (ids) async => ids.where(calendar.contains).toList();
    CalendarSyncService.requestPermissionOverride = () async => true;
    CalendarSyncService.getWritableCalendarsOverride = () async => writable;
    CalendarSyncService.getDefaultCalendarIdOverride = () async => 12;
    CalendarSyncService.upsertEventOverride = (request) async {
      writes.add(request);
      final id = request.eventId ?? nextId++;
      calendar.add(id);
      return id;
    };
    CalendarSyncService.deleteEventOverride = (id) async => calendar.remove(id);
    CalendarSyncService.findExistingEventsOverride = (calendarId, ids) {
      expect(calendarId, 12);
      queries.add(ids);
      return query(ids);
    };
  });
  tearDown(resetTestState);

  Homework task(int id, [String title = 'Synthetic task']) =>
      buildHomework(id: id, title: title, type: HomeworkType.homework);

  AppState stateWith(List<Homework> homework) => AppState(
        (b) => b
          ..settingsState.languageCode = 'en'
          ..settingsState.calendarSyncEnabled = true
          ..settingsState.calendarSyncCalendarId = 12
          ..dashboardState.allDays = ListBuilder<Day>([
            buildDay(date: UtcDateTime(2026, 4, 10), homework: homework),
          ]),
      );

  final twoTasks = stateWith([task(77), task(78)]);

  /// Syncs [state] once and returns the event ids per homework id.
  Future<Map<int, int>> syncOnce(AppState state) async {
    expect(await CalendarSyncService.reconcile(state), isTrue);
    // The fake calendar numbers new events 901, 902, ... in write order.
    final ids = {
      for (final (index, write) in writes.indexed)
        int.parse(RegExp(r'reminder:(\d+)')
            .firstMatch(write.description)!
            .group(1)!): 901 + index,
    };
    writes.clear();
    queries.clear();
    return ids;
  }

  group('reconcile', () {
    test('an event deleted in the calendar is reported, not recreated (C04)',
        () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);

      expect(await CalendarSyncService.reconcile(twoTasks), isFalse);
      expect(writes, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 1);
      expect(
          queries,
          [
            [ids[77], ids[78]]
          ],
          reason: 'one query for all unchanged entries');

      // Later reconciles still do not create it on their own.
      expect(await CalendarSyncService.reconcile(twoTasks), isFalse);
      expect(writes, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 1);
    });

    test('all tracked events present is a plain success', () async {
      await syncOnce(twoTasks);
      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(writes, isEmpty);
      expect(queries, hasLength(1));
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('only the explicit action creates the missing event again', () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      expect(await CalendarSyncService.reconcile(twoTasks), isFalse);

      expect(await CalendarSyncService.recreateMissingEvents(twoTasks), isTrue);
      final recreated = writes.single;
      expect(recreated.eventId, isNull, reason: 'inserted, not updated');
      expect(recreated.description, contains('reminder:77'));
      expect(CalendarSyncService.missingEventCount.value, 0);

      writes.clear();
      queries.clear();
      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(writes, isEmpty);
      expect(queries.single, containsAll([ids[78], 903]));
    });

    test('a failing check counts as unknown and changes nothing', () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      query = (_) async => throw PlatformException(code: 'missing_permission');

      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(await CalendarSyncService.recreateMissingEvents(twoTasks), isTrue);
      expect(writes, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('a check without an answer counts as unknown', () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      query = (_) async => null;

      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(writes, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('a calendar plugin without the query counts as unknown', () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      // No override and no native handler: the method channel call fails.
      CalendarSyncService.findExistingEventsOverride = null;

      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(writes, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('missing, changed and new entries are handled each on their own',
        () async {
      final three = stateWith([task(77), task(78), task(79)]);
      final ids = await syncOnce(three);
      calendar.remove(ids[77]);
      final changed = stateWith([
        task(77),
        task(78),
        task(79, 'Changed task'),
        task(80, 'New task'),
      ]);

      expect(await CalendarSyncService.reconcile(changed), isFalse);
      expect(queries.single, [ids[77], ids[78]],
          reason: 'only unchanged entries are checked');
      expect(writes.map((w) => (w.eventId, w.title.contains('Changed'))), [
        (ids[79], true),
        (null, false),
      ]);
      expect(writes.last.description, contains('reminder:80'));
      expect(CalendarSyncService.missingEventCount.value, 1);

      writes.clear();
      expect(await CalendarSyncService.recreateMissingEvents(changed), isTrue);
      expect(writes.single.description, contains('reminder:77'));
      expect(writes.single.eventId, isNull);
    });

    test('a missing target calendar still writes and checks nothing (#74)',
        () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      writable = [];

      expect(await CalendarSyncService.reconcile(twoTasks), isFalse);
      expect(
          await CalendarSyncService.recreateMissingEvents(twoTasks), isFalse);
      expect(writes, isEmpty);
      expect(queries, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('outside Android nothing is checked', () async {
      await syncOnce(twoTasks);
      isAndroidOverride = () => false;
      expect(await CalendarSyncService.reconcile(twoTasks), isTrue);
      expect(queries, isEmpty);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });

    test('removing the tracked events clears the count', () async {
      final ids = await syncOnce(twoTasks);
      calendar.remove(ids[77]);
      expect(await CalendarSyncService.reconcile(twoTasks), isFalse);
      expect(await CalendarSyncService.deleteTrackedEvents(), isTrue);
      expect(CalendarSyncService.missingEventCount.value, 0);
    });
  });

  group('settings', () {
    Future<void> detectMissing(WidgetTester tester) async {
      await tester.runAsync(() async {
        final ids = await syncOnce(twoTasks);
        calendar.remove(ids[77]);
        await CalendarSyncService.reconcile(twoTasks);
      });
    }

    testWidgets('missing events are shown with an explicit action',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await detectMissing(tester);
      final store = createStore(initialState: twoTasks, withMiddleware: true);
      await pumpApp(tester, store: store, home: SettingsPageContainer());
      await tester.pumpAndSettle();

      final tile = find.byKey(const Key('settings-calendar-sync-missing-tile'));
      await tester.scrollUntilVisible(tile, 400);
      expect(
          find.descendant(
              of: tile,
              matching: find.text('1 event is missing from the calendar')),
          findsOneWidget);
      expect(writes, isEmpty);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-sync-missing-events')),
          findsOneWidget);
      await tester
          .tap(find.byKey(const Key('calendar-sync-recreate-missing-events')));
      // The action loads the localized texts, which needs real time.
      for (var i = 0; i < 50 && writes.isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.runAsync(() => CalendarSyncService.reconcile(twoTasks));
      await tester.pumpAndSettle();

      expect(writes.single.description, contains('reminder:77'));
      expect(
          find.byKey(const Key('calendar-sync-missing-events')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    });

    testWidgets('nothing is shown when no event is missing', (tester) async {
      tester.view.physicalSize = const Size(1400, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => syncOnce(twoTasks));
      await tester.runAsync(() => CalendarSyncService.reconcile(twoTasks));
      final store = createStore(initialState: twoTasks);
      await pumpApp(tester, store: store, home: SettingsPageContainer());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byKey(const Key('settings-calendar-sync-details-tile')), 400);
      expect(find.byKey(const Key('settings-calendar-sync-missing-tile')),
          findsNothing);
    });

    testWidgets('a reconcile started in the settings reports missing events',
        (tester) async {
      await detectMissing(tester);
      final store = createStore(initialState: twoTasks, withMiddleware: true);
      await pumpApp(tester, store: store, home: const Scaffold());
      await tester
          .runAsync(() => store.actions.settingsActions.setLanguage('en'));
      await tester.pump();
      expect(
        find.text('1 synced event is missing from the calendar. You can '
            'recreate it in the settings.'),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await store.dispose();
    });
  });

  test('the missing events use singular and plural forms', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const expected = <AppLanguage, List<String>>{
      AppLanguage.de: [
        '0 Termine fehlen im Kalender',
        '1 Termin fehlt im Kalender',
        '2 Termine fehlen im Kalender',
      ],
      AppLanguage.en: [
        '0 events are missing from the calendar',
        '1 event is missing from the calendar',
        '2 events are missing from the calendar',
      ],
      AppLanguage.it: [
        'Mancano 0 appuntamenti nel calendario',
        'Manca 1 appuntamento nel calendario',
        'Mancano 2 appuntamenti nel calendario',
      ],
      AppLanguage.lld: [
        "0 apuntamënć n'é nia plü tl calendere",
        "1 apuntamënt n'é nia plü tl calendere",
        "2 apuntamënć n'é nia plü tl calendere",
      ],
    };
    for (final language in AppLanguage.values) {
      final l10n = await AppLocalizations.load(language.locale);
      for (final count in [0, 1, 2]) {
        expect(
            l10n.missingCalendarEventsLabel(count), expected[language]![count],
            reason: '${language.code}, $count');
      }
      for (final key in [
        'calendarSync.missingEvents.one',
        'calendarSync.missingEvents.other',
        'settings.calendarSync.missing.body',
        'settings.calendarSync.missing.recreate',
      ]) {
        expect(l10n.text(key, args: {'count': '2'}), isNot(key),
            reason: '${language.code}, $key');
      }
      expect(
          l10n.text('calendarSync.missingEvents.other', args: {'count': '2'}),
          contains('2'));
    }
  });
}
