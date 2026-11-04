import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dr/app_state.dart';
import 'package:dr/i18n/app_localizations.dart';
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
}) =>
    AppState((b) => b
      ..loginState.loggedIn = loggedIn
      ..settingsState.languageCode = language
      ..settingsState.mensaReminderEnabled = mensa
      ..settingsState.mensaReminderMinuteOfDay = minute);

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

    test('repeats daily at the chosen time', () {
      final reminder = planReminders(_state(minute: 13 * 60 + 5), l10n).single;

      expect(reminder.repeatsDaily, isTrue);
      expect((reminder.at.hour, reminder.at.minute), (13, 5));
      expect(reminder.channel, ReminderChannel.daily);
      expect(reminder.title, 'Mensa-Anmeldung');
      expect(reminder.payload, mensaReminderPayload);
    });

    test('keeps its id when the time changes, so it is replaced', () {
      expect(planReminders(_state(minute: 60), l10n).single.id,
          planReminders(_state(minute: 120), l10n).single.id);
    });

    test('opens the sign-up page of the Mensa', () {
      expect(
          mensaReminderUri.toString(), 'https://mensa.franziskanergymnasium.it');
    });
  });

  group('settings persistence', () {
    test('the mensa reminder defaults to off at 7:30', () {
      final settings = SettingsState();

      expect(settings.mensaReminderEnabled, isFalse);
      expect(settings.mensaReminderMinuteOfDay, 7 * 60 + 30);
    });

    test('survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await settingsPersistenceService.save(SettingsState((b) => b
        ..mensaReminderEnabled = true
        ..mensaReminderMinuteOfDay = 9 * 60 + 15));

      final restored = await settingsPersistenceService.load();

      expect(restored!.mensaReminderEnabled, isTrue);
      expect(restored.mensaReminderMinuteOfDay, 9 * 60 + 15);
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
