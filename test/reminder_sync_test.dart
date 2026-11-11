import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reminder_link.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:dr/reminder_sync.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppState _state({
  bool loggedIn = true,
  bool mensa = true,
  int minute = 7 * 60 + 30,
  String language = 'de',
  // One day keeps most tests at a single reminder.
  List<int> weekdays = const [DateTime.wednesday],
}) =>
    AppState((b) => b
      ..loginState.loggedIn = loggedIn
      ..settingsState.languageCode = language
      ..settingsState.mensaReminderEnabled = mensa
      ..settingsState.mensaReminderMinuteOfDay = minute
      ..settingsState.mensaReminderWeekdays = ListBuilder<int>(weekdays));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.load(const Locale('de'));
  });

  group('mensa reminder plan', () {
    test('is empty while the switch is off', () {
      expect(planReminders(_state(mensa: false), l10n), isEmpty);
    });

    test('repeats weekly on the chosen day at the chosen time', () {
      final reminder = planReminders(_state(minute: 13 * 60 + 5), l10n).single;

      expect(reminder.repeats, isTrue);
      expect(reminder.weekday, DateTime.wednesday);
      expect((reminder.at.hour, reminder.at.minute), (13, 5));
      expect(reminder.channel, ReminderChannel.daily);
      expect(reminder.title, 'Mensa-Anmeldung');
      expect(reminder.payload, mensaReminderPayload);
    });

    test('by default Monday to Friday, one reminder per day', () {
      final state = AppState((b) => b
        ..loginState.loggedIn = true
        ..settingsState.mensaReminderEnabled = true);
      final reminders = planReminders(state, l10n);

      expect(reminders.map((r) => r.weekday), [1, 2, 3, 4, 5]);
      expect(reminders.map((r) => r.id).toSet(), hasLength(5));
      expect(reminders.map((r) => r.payload),
          everyElement(mensaReminderPayload));
    });

    test('only the chosen weekdays, each with its own stable id', () {
      final reminders =
          planReminders(_state(weekdays: [7, 1, 3, 3, 9]), l10n);

      expect(reminders.map((r) => r.weekday), [1, 3, 7]);
      expect(
        planReminders(_state(weekdays: [3]), l10n).single.id,
        reminders[1].id,
      );
    });

    test('never uses the id of the old daily reminder', () {
      final ids = planReminders(
        _state(weekdays: [1, 2, 3, 4, 5, 6, 7]),
        l10n,
      ).map((r) => r.id);

      expect(ids, isNot(contains(reminderNotificationId('mensa'))));
    });

    test('keeps its id when the time changes, so it is replaced', () {
      final before = planReminders(_state(minute: 60), l10n).single;
      final after = planReminders(_state(minute: 120), l10n).single;

      expect(after.id, before.id);
      expect(after.fingerprint('Europe/Rome'),
          isNot(before.fingerprint('Europe/Rome')));
    });

    test('another weekday changes the fingerprint', () {
      PlannedReminder on(int weekday) =>
          planReminders(_state(weekdays: [weekday]), l10n).single;

      expect(on(1).fingerprint('Europe/Rome'),
          isNot(on(2).fingerprint('Europe/Rome')));
    });

    test('weekdays are kept unique and valid, Monday first', () {
      expect(normalizeReminderWeekdays([7, 1, 1, 0, 8, 3]), [1, 3, 7]);
      expect(normalizeReminderWeekdays([]), defaultMensaReminderWeekdays);
    });
  });

  group('tapping the mensa reminder', () {
    late List<Uri> opened;
    late int dashboards;
    late int failures;

    Future<void> tap(
      String url, {
      String? payload = mensaReminderPayload,
      Future<bool> Function(Uri uri)? launch,
    }) =>
        openReminderTarget(
          payload,
          mensaUrl: url,
          openDashboard: () => dashboards++,
          linkFailed: () => failures++,
          launch: launch ??
              (uri) async {
                opened.add(uri);
                return true;
              },
        );

    setUp(() {
      opened = [];
      dashboards = 0;
      failures = 0;
    });

    test('without a link it opens the dashboard', () async {
      await tap('');

      expect(opened, isEmpty);
      expect(dashboards, 1);
      expect(failures, 0);
    });

    test('opens the link of the user and nothing else', () async {
      await tap('https://example.org/menu');

      expect(opened, [Uri.parse('https://example.org/menu')]);
      expect(dashboards, 0);
      expect(failures, 0);
    });

    test('opens every link the settings page saves', () async {
      for (final typed in [
        'mensa.example.org',
        '  HTTPS://Mensa.Example.org/Anmeldung/  ',
        'http://mensa.example.org',
        'mensa.example.org/login?next=https://mensa.example.org/menu',
      ]) {
        // The settings page stores what this returns.
        final saved = normalizeReminderLink(typed)!;
        await tap(saved);
        expect(opened.last, Uri.parse(saved));
      }

      expect(opened, hasLength(4));
      expect(failures, 0);
    });

    test('never opens an invalid value and says so', () async {
      for (final url in ['javascript:alert(1)', 'not a link', 'ftp://a.org']) {
        await tap(url);
      }

      expect(opened, isEmpty);
      expect(dashboards, 3);
      expect(failures, 3);
    });

    test('falls back to the dashboard and says so if the link cannot be opened',
        () async {
      await tap('https://example.org', launch: (_) async => false);
      await tap('https://example.org', launch: (_) => throw StateError('no'));

      expect(dashboards, 2);
      expect(failures, 2);
    });

    test('other reminders are left alone', () async {
      await tap('https://example.org', payload: null);
      await tap('https://example.org', payload: 'something-else');

      expect(opened, isEmpty);
      expect(dashboards, 0);
    });
  });

  group('settings persistence', () {
    test('the mensa reminder defaults to off at 7:30 on school days', () {
      final settings = SettingsState();

      expect(settings.mensaReminderEnabled, isFalse);
      expect(settings.mensaReminderMinuteOfDay, 7 * 60 + 30);
      expect(settings.mensaReminderUrl, isEmpty);
      expect(settings.mensaReminderWeekdays, [1, 2, 3, 4, 5]);
    });

    test('survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await settingsPersistenceService.save(SettingsState((b) => b
        ..mensaReminderEnabled = true
        ..mensaReminderMinuteOfDay = 9 * 60 + 15
        ..mensaReminderUrl = 'https://example.org/menu'
        ..mensaReminderWeekdays = ListBuilder<int>([2, 6])));

      final restored = await settingsPersistenceService.load();

      expect(restored!.mensaReminderEnabled, isTrue);
      expect(restored.mensaReminderMinuteOfDay, 9 * 60 + 15);
      expect(restored.mensaReminderUrl, 'https://example.org/menu');
      expect(restored.mensaReminderWeekdays, [2, 6]);
    });

    test('settings saved by an older version get the defaults', () async {
      final saved = serializers.serialize(SettingsState())! as List<Object?>;
      final old = <Object?>[saved.first];
      for (var i = 1; i + 1 < saved.length; i += 2) {
        if (!'${saved[i]}'.contains('Reminder')) {
          old.addAll([saved[i], saved[i + 1]]);
        }
      }
      SharedPreferences.setMockInitialValues(
          {globalSettingsPreferenceKey: jsonEncode(old)});

      final restored = await settingsPersistenceService.load();

      expect(restored, isNotNull);
      expect(restored!.mensaReminderEnabled, isFalse);
      expect(restored.mensaReminderMinuteOfDay, 7 * 60 + 30);
      expect(restored.mensaReminderUrl, isEmpty);
      expect(restored.assessmentReminderMinuteOfDay, 18 * 60);
    });

    test('older settings without the new choices get their defaults',
        () async {
      // Saved by the version before #128: reminders on, nothing chosen yet.
      final saved = serializers.serialize(SettingsState((b) => b
        ..mensaReminderEnabled = true
        ..assessmentRemindersEnabled = true))! as List<Object?>;
      const added = {
        'mensaReminderWeekdays',
        'examRemindersEnabled',
        'testRemindersEnabled',
        'homeworkRemindersEnabled',
      };
      final old = <Object?>[saved.first];
      for (var i = 1; i + 1 < saved.length; i += 2) {
        if (!added.contains(saved[i])) old.addAll([saved[i], saved[i + 1]]);
      }
      expect(old.length, saved.length - 2 * added.length);
      SharedPreferences.setMockInitialValues(
          {globalSettingsPreferenceKey: jsonEncode(old)});

      final restored = (await settingsPersistenceService.load())!;

      expect(restored.mensaReminderEnabled, isTrue);
      expect(restored.mensaReminderWeekdays, [1, 2, 3, 4, 5]);
      expect(restored.assessmentRemindersEnabled, isTrue);
      expect(restored.examRemindersEnabled, isTrue);
      expect(restored.testRemindersEnabled, isTrue);
      expect(restored.homeworkRemindersEnabled, isFalse);
    });
  });

  group('sync with the app state', () {
    late StreamController<AppState> states;
    late List<List<PlannedReminder>> syncs;
    late ReminderSync sync;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    setUp(() {
      states = StreamController<AppState>();
      syncs = [];
      sync = ReminderSync(
        sync: (reminders) async => syncs.add(reminders),
        localizations: (_) async => l10n,
        debounce: Duration.zero,
      );
    });

    tearDown(() async {
      sync.dispose();
      await states.close();
    });

    test('plans after signing in', () async {
      sync.attach(states.stream, _state(loggedIn: false));
      states.add(_state());
      await settle();

      expect(syncs.single, hasLength(1));
    });

    test('turning the switch off removes the reminder', () async {
      sync.attach(states.stream, _state(loggedIn: false));
      states.add(_state());
      await settle();
      states.add(_state(mensa: false));
      await settle();

      expect(syncs.last, isEmpty);
    });

    test('a new time plans again', () async {
      sync.attach(states.stream, _state());
      states.add(_state(minute: 600));
      await settle();

      expect(syncs.single.single.at.hour, 10);
    });

    test('other weekdays plan again', () async {
      sync.attach(states.stream, _state());
      states.add(_state(weekdays: [1, 5]));
      await settle();

      expect(syncs.single.map((r) => r.weekday), [1, 5]);
    });

    test('a new language plans the texts again', () async {
      sync.attach(states.stream, _state());
      states.add(_state(language: 'it'));
      await settle();

      expect(syncs, hasLength(1));
    });

    test('unrelated state changes do not plan', () async {
      final state = _state();
      sync.attach(states.stream, state);
      states.add(state.rebuild((b) => b.noInternet = true));
      await settle();

      expect(syncs, isEmpty);
    });

    test('a burst of changes plans once', () async {
      sync = ReminderSync(
        sync: (reminders) async => syncs.add(reminders),
        localizations: (_) async => l10n,
        debounce: const Duration(milliseconds: 5),
      );
      sync.attach(states.stream, _state());
      states
        ..add(_state(minute: 600))
        ..add(_state(minute: 601))
        ..add(_state(minute: 602));
      await settle();

      expect(syncs.single.single.at.minute, 2);
    });

    test('logging out removes all reminders', () async {
      sync.attach(states.stream, _state(loggedIn: false));
      states.add(_state());
      await settle();
      states.add(_state(loggedIn: false));
      await settle();

      expect(syncs.last, isEmpty);
    });

    test('app start before the automatic sign-in removes nothing', () async {
      sync.attach(states.stream, _state(loggedIn: false));
      await sync.refresh();
      states.add(_state(loggedIn: false, language: 'it'));
      await settle();

      expect(syncs, isEmpty);
    });

    test('returning to the app plans again', () async {
      sync.attach(states.stream, _state());
      await sync.refresh();

      expect(syncs, hasLength(1));
    });

    test('a failing system does not reach the app', () async {
      sync = ReminderSync(
        sync: (_) async => throw StateError('no notifications'),
        localizations: (_) async => l10n,
      );
      sync.attach(states.stream, _state());

      await expectLater(sync.refresh(), completes);
    });
  });
}
