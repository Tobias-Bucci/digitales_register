import 'dart:async';
import 'dart:ui';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_clock.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:dr/reminder_sync.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

Homework _test(int id, {String subject = 'Deutsch', String title = 'Test'}) =>
    buildHomework(
      id: id,
      title: title,
      subtitle: 'Textanalyse',
      label: subject,
      type: HomeworkType.gradeGroup,
    );

Day _day(UtcDateTime date, List<Homework> homework) =>
    buildDay(date: date, homework: homework);

AppState _state(
  List<Day> days, {
  bool enabled = true,
  List<int> reminderDays = const [3, 2, 1],
  int minute = 18 * 60,
  String user = 'student',
  String url = 'https://school.example',
}) =>
    AppState((b) => b
      ..url = url
      ..loginState.loggedIn = true
      ..loginState.username = user
      ..dashboardState.allDays = ListBuilder<Day>(days)
      ..settingsState.assessmentRemindersEnabled = enabled
      ..settingsState.assessmentReminderDays = ListBuilder<int>(reminderDays)
      ..settingsState.assessmentReminderMinuteOfDay = minute);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l10n;
  final monday = DateTime(2026, 4, 13, 12);
  final examDate = UtcDateTime(2026, 4, 20);

  List<PlannedReminder> plan(AppState state, {DateTime? now}) =>
      planReminders(state, l10n, now: now ?? monday);

  setUpAll(() async {
    l10n = await AppLocalizations.load(const Locale('de'));
  });

  group('reminder days', () {
    test('accepts positive whole numbers', () {
      expect(validateReminderDay('4', [3, 2, 1]), isNull);
      expect(validateReminderDay(' 4 ', [3, 2, 1]), isNull);
      expect(validateReminderDay('$maxAssessmentReminderDay', []), isNull);
    });

    test('rejects everything else', () {
      for (final input in ['', ' ', '0', '-1', '1.5', '2,5', 'abc', '1 2']) {
        expect(validateReminderDay(input, []), ReminderDayError.invalid,
            reason: input);
      }
    });

    test('rejects days that are too far away', () {
      expect(validateReminderDay('${maxAssessmentReminderDay + 1}', []),
          ReminderDayError.tooLarge);
      expect(validateReminderDay('99999999999999999999999', []),
          ReminderDayError.tooLarge);
    });

    test('rejects duplicates', () {
      expect(validateReminderDay('2', [3, 2, 1]), ReminderDayError.duplicate);
      expect(validateReminderDay('02', [3, 2, 1]), ReminderDayError.duplicate);
    });

    test('are kept unique, valid and with the furthest first', () {
      expect(normalizeReminderDays([1, 7, 3, 3, 0, -2, 99]), [7, 3, 1]);
    });
  });

  group('reminder times', () {
    test('counts back calendar days and uses the fixed time', () {
      expect(
        [3, 2, 1].map((days) => assessmentReminderTime(examDate, days, 18 * 60)),
        [
          DateTime(2026, 4, 17, 18),
          DateTime(2026, 4, 18, 18),
          DateTime(2026, 4, 19, 18),
        ],
      );
    });

    test('crosses month and year boundaries', () {
      expect(assessmentReminderTime(UtcDateTime(2026, 3, 1), 1, 18 * 60),
          DateTime(2026, 2, 28, 18));
      expect(assessmentReminderTime(UtcDateTime(2027, 1, 1), 2, 18 * 60),
          DateTime(2026, 12, 30, 18));
    });

    test('uses hours and minutes of the chosen time', () {
      expect(assessmentReminderTime(examDate, 1, 6 * 60 + 45),
          DateTime(2026, 4, 19, 6, 45));
    });

    test('keeps the time across a change of daylight saving', () {
      final at = assessmentReminderTime(UtcDateTime(2026, 3, 30), 3, 18 * 60);

      expect((at.day, at.hour), (27, 18));
    });
  });

  group('plan', () {
    test('covers every assessment without any setting per test', () {
      final reminders = plan(_state([
        _day(examDate, [_test(1), _test(2, subject: 'Englisch')]),
        _day(UtcDateTime(2026, 4, 24), [_test(3, subject: 'Physik')]),
      ]));

      expect(reminders, hasLength(9));
      expect(reminders.map((r) => r.id).toSet(), hasLength(9));
      expect(reminders.every((r) => r.channel == ReminderChannel.assessment),
          isTrue);
    });

    test('is empty while the switch is off', () {
      expect(plan(_state([_day(examDate, [_test(1)])], enabled: false)), isEmpty);
    });

    test('ignores entries that are no assessments', () {
      expect(
        plan(_state([
          _day(examDate, [buildHomework(id: 1, label: 'Deutsch')]),
        ])),
        isEmpty,
      );
    });

    test('includes assessments the user noted with /test', () {
      final reminders = plan(_state([
        _day(examDate, [
          buildHomework(id: 1, title: 'Erinnerung', subtitle: '/test Referat'),
        ]),
      ]));

      expect(reminders, hasLength(3));
    });

    test('a test deleted on the server has no reminders', () {
      final deleted = _day(examDate, []).rebuild(
          (b) => b.deletedHomework.add(_test(1).rebuild((h) => h.deleted = true)));

      expect(plan(_state([deleted])), isEmpty);
    });

    test('does not plan what has passed', () {
      final state = _state([_day(examDate, [_test(1)])]);

      expect(
        plan(state, now: DateTime(2026, 4, 18, 19)).map((r) => r.at),
        [DateTime(2026, 4, 19, 18)],
      );
      expect(plan(state, now: DateTime(2026, 4, 19, 18)), isEmpty);
      expect(plan(state, now: DateTime(2026, 4, 20, 8)), isEmpty);
      expect(plan(state, now: DateTime(2026, 5, 1)), isEmpty);
    });

    test('a reminder at this very evening is still planned before 18:00', () {
      final state = _state([_day(examDate, [_test(1)])]);

      expect(plan(state, now: DateTime(2026, 4, 19, 17, 59)), hasLength(1));
    });

    test('follows the configured days', () {
      final reminders = plan(_state(
        [_day(examDate, [_test(1)])],
        reminderDays: [5],
      ));

      expect(reminders.single.at, DateTime(2026, 4, 15, 18));
    });

    test('uses the chosen time', () {
      final reminder = plan(_state(
        [_day(examDate, [_test(1)])],
        reminderDays: [1],
        minute: 7 * 60 + 5,
      )).single;

      expect(reminder.at, DateTime(2026, 4, 19, 7, 5));
    });

    test('whether a time has passed depends on the chosen time', () {
      final days = [_day(examDate, [_test(1)])];
      final now = DateTime(2026, 4, 19, 12);

      expect(plan(_state(days, minute: 11 * 60), now: now), isEmpty);
      expect(plan(_state(days, minute: 13 * 60), now: now), hasLength(1));
    });

    test('a new time keeps the ids, so that it replaces the reminders', () {
      final days = [_day(examDate, [_test(1)])];
      final before = plan(_state(days));
      final after = plan(_state(days, minute: 7 * 60));

      expect(after.map((r) => r.id), before.map((r) => r.id));
      expect(after.first.fingerprint(), isNot(before.first.fingerprint()));
    });

    test('a moved test keeps its ids, so that it replaces its reminders', () {
      final before = plan(_state([_day(examDate, [_test(1)])]));
      final after = plan(_state([
        _day(UtcDateTime(2026, 4, 22), [_test(1)]),
      ]));

      expect(after.map((r) => r.id), before.map((r) => r.id));
      expect(after.first.fingerprint(), isNot(before.first.fingerprint()));
    });

    test('a changed subject changes the text of the same reminder', () {
      final before = plan(_state([_day(examDate, [_test(1)])])).first;
      final after = plan(_state([
        _day(examDate, [_test(1, subject: 'Latein')]),
      ])).first;

      expect(after.id, before.id);
      expect(after.body, 'Latein');
    });

    test('planning twice gives the same reminders, so nothing is rescheduled',
        () {
      final state = _state([_day(examDate, [_test(1)])]);

      expect(plan(state).map((r) => r.fingerprint()),
          plan(state).map((r) => r.fingerprint()));
    });

    test('an entry that appears twice is reminded of once', () {
      final reminders = plan(_state([
        _day(examDate, [_test(1), _test(1)]),
      ]));

      expect(reminders, hasLength(3));
    });

    test('accounts do not share reminders', () {
      final days = [_day(examDate, [_test(1)])];

      expect(plan(_state(days)).first.id,
          isNot(plan(_state(days, user: 'sibling')).first.id));
    });

    test('names the type and the subject, but no teacher text', () {
      final reminders = plan(_state([_day(examDate, [_test(1)])]));

      expect(reminders.map((r) => r.title),
          ['In 3 Tagen: Test', 'In 2 Tagen: Test', 'Morgen: Test']);
      expect(reminders.first.body, 'Deutsch');
      expect(reminders.first.body, isNot(contains('Textanalyse')));
    });

    test('stays understandable without a subject', () {
      final reminder = plan(_state(
        [
          _day(examDate, [
            buildHomework(id: 1, title: ' ', type: HomeworkType.gradeGroup),
          ]),
        ],
        reminderDays: [1],
      )).single;

      expect(reminder.title, 'Morgen: Prüfung');
      expect(reminder.body, 'Details findest du im Register.');
    });

    test('is translated', () async {
      final italian = await AppLocalizations.load(const Locale('it'));
      final reminder = planReminders(
        _state([_day(examDate, [_test(1)])], reminderDays: [2]),
        italian,
        now: monday,
      ).single;

      expect(reminder.title, 'Tra 2 giorni: Test');
    });

    test('the made-up dates of the demo guest are not reminded of', () {
      appClock.setDemoMode(true);
      addTearDown(() => appClock.setDemoMode(false));

      expect(plan(_state([_day(examDate, [_test(1)])])), isEmpty);
    });
  });

  group('settings persistence', () {
    test('defaults to off with three, two and one days at 18:00', () {
      final settings = SettingsState();

      expect(settings.assessmentRemindersEnabled, isFalse);
      expect(settings.assessmentReminderDays, [3, 2, 1]);
      expect(settings.assessmentReminderMinuteOfDay, 18 * 60);
    });

    test('survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await settingsPersistenceService.save(SettingsState((b) => b
        ..assessmentRemindersEnabled = true
        ..assessmentReminderDays = ListBuilder<int>([7, 1])
        ..assessmentReminderMinuteOfDay = 6 * 60 + 45));

      final restored = await settingsPersistenceService.load();

      expect(restored!.assessmentRemindersEnabled, isTrue);
      expect(restored.assessmentReminderDays, [7, 1]);
      expect(restored.assessmentReminderMinuteOfDay, 6 * 60 + 45);
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

    // Far ahead, as this path uses the real clock.
    final future = UtcDateTime(DateTime.now().year + 1, 6, 15);

    test('newly loaded tests are planned', () async {
      sync.attach(states.stream, _state(const []));
      states.add(_state([_day(future, [_test(1)])]));
      await settle();

      expect(syncs.single, hasLength(3));
    });

    test('a test that disappears is removed', () async {
      sync.attach(states.stream, _state([_day(future, [_test(1)])]));
      states.add(_state(const []));
      await settle();

      expect(syncs.single, isEmpty);
    });

    test('changed days plan again', () async {
      final days = [_day(future, [_test(1)])];
      sync.attach(states.stream, _state(days));
      states.add(_state(days, reminderDays: [1]));
      await settle();

      expect(syncs.single, hasLength(1));
    });

    test('a changed time plans again', () async {
      final days = [_day(future, [_test(1)])];
      sync.attach(states.stream, _state(days));
      states.add(_state(days, minute: 7 * 60));
      await settle();

      expect(syncs.single.first.at.hour, 7);
    });

    test('another account plans again', () async {
      final days = [_day(future, [_test(1)])];
      sync.attach(states.stream, _state(days));
      states.add(_state(days, user: 'sibling'));
      await settle();

      expect(syncs, hasLength(1));
    });
  });
}
