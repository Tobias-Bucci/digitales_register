import 'package:dr/reminder_notifications.dart';
import 'package:dr/reminder_schedule.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiver/testing/async.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class _Scheduled {
  _Scheduled(this.date, this.repeat, this.mode, this.title);
  final tz.TZDateTime date;
  final DateTimeComponents? repeat;
  final AndroidScheduleMode mode;
  final String? title;
}

/// Behaves like the system: scheduling an id replaces it, cancelling removes it.
class _Native extends Fake implements FlutterLocalNotificationsPlugin {
  final scheduled = <int, _Scheduled>{};
  final cancelled = <int>[];
  final shown = <int>[];
  var scheduleCalls = 0;

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduleCalls++;
    scheduled[id] = _Scheduled(
        scheduledDate, matchDateTimeComponents, androidScheduleMode, title);
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      [
        for (final id in scheduled.keys)
          PendingNotificationRequest(id, null, null, null),
      ];

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async =>
      shown.add(id);
}

PlannedReminder _once(int id, DateTime at, {String title = 'Reminder'}) =>
    PlannedReminder(
      id: id,
      channel: ReminderChannel.assessment,
      channelName: 'Channel',
      at: at,
      title: title,
      body: 'Body',
    );

PlannedReminder _daily({int hour = 7, int minute = 30}) => PlannedReminder(
      id: 1000,
      channel: ReminderChannel.daily,
      channelName: 'Channel',
      at: DateTime(2000, 1, 1, hour, minute),
      title: 'Daily',
      body: 'Body',
      repeats: true,
    );

/// Like the Mensa reminder: one per weekday, each with its own id.
PlannedReminder _weekly(int weekday, {int hour = 7, int minute = 30}) =>
    PlannedReminder(
      id: 2000 + weekday,
      channel: ReminderChannel.daily,
      channelName: 'Channel',
      at: DateTime(2000, 1, 1, hour, minute),
      title: 'Weekly',
      body: 'Body',
      repeats: true,
      weekday: weekday,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Native native;
  late DateTime now;
  String? zone;

  ReminderNotificationService create(ReminderBackend backend) =>
      ReminderNotificationService(
        native: native,
        backend: backend,
        clock: () => now,
        deviceTimeZone: () async => zone,
        initializer: () async {},
        permission: () async => true,
        permissionRequest: () async => true,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    native = _Native();
    now = DateTime(2026, 3, 10, 12);
    zone = 'Europe/Rome';
  });

  group('system scheduling', () {
    late ReminderNotificationService service;
    setUp(() => service = create(ReminderBackend.systemRepeating));

    test('schedules a one-time reminder at the exact moment, without exact alarms',
        () async {
      final at = DateTime(2026, 3, 12, 18);
      await service.sync([_once(1, at)]);

      final scheduled = native.scheduled[1]!;
      expect(scheduled.date.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
      expect(scheduled.repeat, isNull);
      expect(scheduled.mode, AndroidScheduleMode.inexactAllowWhileIdle);
    });

    test('does not plan a time that has passed', () async {
      await service.sync([_once(1, now), _once(2, DateTime(2026, 3, 9, 18))]);

      expect(native.scheduled, isEmpty);
    });

    test('leaves unchanged reminders alone', () async {
      final reminders = [_once(1, DateTime(2026, 3, 12, 18)), _daily()];
      await service.sync(reminders);
      await service.sync(reminders);

      expect(native.scheduleCalls, 2);
      expect(native.cancelled, isEmpty);
    });

    test('a reminder lost by the system is scheduled again', () async {
      final reminders = [_once(1, DateTime(2026, 3, 12, 18))];
      await service.sync(reminders);
      native.scheduled.clear();
      await service.sync(reminders);

      expect(native.scheduled.keys, [1]);
    });

    test('a moved reminder replaces the old one instead of adding a second',
        () async {
      await service.sync([_once(1, DateTime(2026, 3, 12, 18))]);
      await service.sync([_once(1, DateTime(2026, 3, 13, 18))]);

      expect(native.cancelled, [1]);
      expect(native.scheduled.keys, [1]);
      expect(native.scheduled[1]!.date.day, 13);
    });

    test('a changed text is handed to the system again', () async {
      final at = DateTime(2026, 3, 12, 18);
      await service.sync([_once(1, at)]);
      await service.sync([_once(1, at, title: 'Promemoria')]);

      expect(native.scheduled[1]!.title, 'Promemoria');
    });

    test('a removed reminder is cancelled', () async {
      await service.sync([
        _once(1, DateTime(2026, 3, 12, 18)),
        _once(2, DateTime(2026, 3, 13, 18)),
      ]);
      await service.sync([_once(2, DateTime(2026, 3, 13, 18))]);

      expect(native.cancelled, [1]);
      expect(native.scheduled.keys, [2]);
    });

    test('an empty plan removes everything, also after a restart', () async {
      await service.sync([_once(1, DateTime(2026, 3, 12, 18)), _daily()]);
      await create(ReminderBackend.systemRepeating).sync([]);

      expect(native.scheduled, isEmpty);
    });

    test('a reminder that already fired stays on screen', () async {
      await service.sync([_once(1, DateTime(2026, 3, 10, 18))]);
      now = DateTime(2026, 3, 10, 19);
      await service.sync([]);

      expect(native.cancelled, isEmpty);
    });

    test('corrupt bookkeeping does not stop reminders', () async {
      SharedPreferences.setMockInitialValues(
          {reminderStoragePreferenceKey: 'not json'});
      await service.sync([_once(1, DateTime(2026, 3, 12, 18))]);

      expect(native.scheduled.keys, [1]);
    });

    test('keeps the soonest reminders within the limit of the system', () async {
      await service.sync([
        for (var i = 0; i < maxPendingReminders + 5; i++)
          _once(i, DateTime(2026, 7, 1).subtract(Duration(days: i))),
      ]);

      expect(native.scheduled.length, maxPendingReminders);
      expect(native.scheduled.containsKey(maxPendingReminders + 4), isTrue);
      expect(native.scheduled.containsKey(0), isFalse);
    });
  });

  group('daily reminder', () {
    test('repeats by wall clock in the zone of the device', () async {
      await create(ReminderBackend.systemRepeating).sync([_daily()]);

      final scheduled = native.scheduled[1000]!;
      expect(scheduled.repeat, DateTimeComponents.time);
      expect(scheduled.date.location.name, 'Europe/Rome');
      expect(scheduled.date.day, 11);
    });

    test('uses Italian time when the device reports no usable zone', () async {
      zone = 'Not/AZone';
      await create(ReminderBackend.systemRepeating).sync([_daily()]);

      expect(native.scheduled[1000]!.date.location.name, 'Europe/Rome');
    });

    test('a changed time zone is handed to the system again', () async {
      final service = create(ReminderBackend.systemRepeating);
      await service.sync([_daily()]);
      zone = 'Europe/London';
      await service.sync([_daily()]);

      expect(native.scheduled[1000]!.date.location.name, 'Europe/London');
    });

    test('a changed time replaces the repeating notification', () async {
      final service = create(ReminderBackend.systemRepeating);
      await service.sync([_daily()]);
      await service.sync([_daily(hour: 13)]);

      expect(native.scheduled.length, 1);
      expect(native.scheduled[1000]!.date.hour, 13);
    });

    test('is planned ahead where the system cannot repeat it', () async {
      final service = create(ReminderBackend.systemOneTime);
      await service.sync([_daily()]);

      expect(native.scheduled.length, dailyReminderOccurrences);
      expect(native.scheduled.values.every((s) => s.repeat == null), isTrue);

      final before = native.scheduled.keys.toSet();
      now = now.add(const Duration(days: 2));
      // The system forgets a one-time notification once it was shown.
      native.scheduled.removeWhere((_, s) => s.date.isBefore(now));
      await service.sync([_daily()]);

      expect(native.scheduled.length, dailyReminderOccurrences);
      expect(native.scheduled.keys.toSet().intersection(before).length,
          dailyReminderOccurrences - 2);
    });
  });

  group('weekly reminder', () {
    // The tests start on Tuesday, 10 March 2026, at noon.

    test('repeats on its weekday by wall clock in the zone of the device',
        () async {
      await create(ReminderBackend.systemRepeating)
          .sync([_weekly(DateTime.monday), _weekly(DateTime.wednesday)]);

      final monday = native.scheduled[2001]!;
      final wednesday = native.scheduled[2003]!;
      expect(monday.repeat, DateTimeComponents.dayOfWeekAndTime);
      expect(wednesday.repeat, DateTimeComponents.dayOfWeekAndTime);
      expect((monday.date.weekday, monday.date.day, monday.date.hour),
          (DateTime.monday, 16, 7));
      expect((wednesday.date.weekday, wednesday.date.day),
          (DateTime.wednesday, 11));
      expect(monday.date.location.name, 'Europe/Rome');
    });

    test('the daily reminder of older versions is cancelled', () async {
      await create(ReminderBackend.systemRepeating).sync([_daily()]);
      expect(native.scheduled.keys, [1000]);

      // The first sync after the update, in a new app process.
      await create(ReminderBackend.systemRepeating).sync([
        for (final day in [1, 2, 3, 4, 5]) _weekly(day),
      ]);

      expect(native.cancelled, [1000]);
      expect(native.scheduled.keys.toSet(), {2001, 2002, 2003, 2004, 2005});
    });

    test('a removed weekday is cancelled, the others stay alone', () async {
      final service = create(ReminderBackend.systemRepeating);
      await service.sync([_weekly(1), _weekly(2)]);
      final calls = native.scheduleCalls;
      await service.sync([_weekly(1)]);

      expect(native.cancelled, [2002]);
      expect(native.scheduleCalls, calls);
    });

    test('a changed time replaces the notification of that weekday', () async {
      final service = create(ReminderBackend.systemRepeating);
      await service.sync([_weekly(1)]);
      await service.sync([_weekly(1, hour: 9)]);

      expect(native.scheduled[2001]!.date.hour, 9);
      expect(native.scheduled.length, 1);
    });

    test('only its weekdays are planned where the system cannot repeat',
        () async {
      await create(ReminderBackend.systemOneTime)
          .sync([_weekly(DateTime.monday), _weekly(DateTime.wednesday)]);

      expect(native.scheduled.length, 4);
      expect(native.scheduled.values.every((s) => s.repeat == null), isTrue);
      expect(
        native.scheduled.values.map((s) => s.date.toLocal().day).toSet(),
        {11, 16, 18, 23},
      );
    });

    test('is shown only on its weekdays while the app is running', () {
      FakeAsync().run((async) {
        final start = DateTime(2026, 3, 10, 12);
        final clock = async.getClock(start);
        final service = ReminderNotificationService(
          native: native,
          backend: ReminderBackend.whileRunning,
          clock: clock.now,
          initializer: () async {},
          permission: () async => true,
          permissionRequest: () async => true,
        );
        service.sync([_weekly(DateTime.thursday)]);
        async.flushMicrotasks();

        // Wednesday morning passes without a reminder.
        async.elapse(const Duration(hours: 20));
        expect(native.shown, isEmpty);
        // Thursday 7:30.
        async.elapse(const Duration(days: 1));
        expect(native.shown, hasLength(1));
        // Nothing else until the next Thursday.
        async.elapse(const Duration(days: 5));
        expect(native.shown, hasLength(1));
        service.dispose();
      });
    });
  });

  group('without system scheduling', () {
    test('shows a reminder while the app is running, once', () {
      FakeAsync().run((async) {
        final start = DateTime(2026, 3, 10, 12);
        final clock = async.getClock(start);
        final service = ReminderNotificationService(
          native: native,
          backend: ReminderBackend.whileRunning,
          clock: clock.now,
          initializer: () async {},
          permission: () async => true,
          permissionRequest: () async => true,
        );
        service.sync([_once(1, start.add(const Duration(hours: 1)))]);
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 59));
        expect(native.shown, isEmpty);
        async.elapse(const Duration(minutes: 2));
        expect(native.shown, [1]);
        async.elapse(const Duration(days: 1));
        expect(native.shown, [1]);
        expect(native.scheduled, isEmpty);
      });
    });

    test('a removed reminder is not shown', () {
      FakeAsync().run((async) {
        final start = DateTime(2026, 3, 10, 12);
        final service = ReminderNotificationService(
          native: native,
          backend: ReminderBackend.whileRunning,
          clock: async.getClock(start).now,
          initializer: () async {},
          permission: () async => true,
          permissionRequest: () async => true,
        );
        service.sync([_once(1, start.add(const Duration(hours: 1)))]);
        async.flushMicrotasks();
        service.sync([]);
        async.flushMicrotasks();

        async.elapse(const Duration(hours: 2));
        expect(native.shown, isEmpty);
      });
    });
  });

  group('schedule calculation', () {
    test('the next occurrence is today only while the time is still ahead', () {
      final morning = DateTime(2026, 3, 10, 7);
      expect(nextDailyOccurrence(morning, 7, 30), DateTime(2026, 3, 10, 7, 30));
      expect(nextDailyOccurrence(morning, 7, 0), DateTime(2026, 3, 11, 7));
      expect(nextDailyOccurrence(morning, 6, 0), DateTime(2026, 3, 11, 6));
    });

    test('the next occurrence crosses month and year boundaries', () {
      expect(nextDailyOccurrence(DateTime(2026, 12, 31, 20), 7, 30),
          DateTime(2027, 1, 1, 7, 30));
    });

    test('occurrences keep the wall clock across a change of daylight saving',
        () {
      final occurrences = _daily().occurrences(DateTime(2026, 3, 27, 12), 4);

      expect(occurrences.map((o) => (o.at.day, o.at.hour, o.at.minute)), [
        (28, 7, 30),
        (29, 7, 30),
        (30, 7, 30),
        (31, 7, 30),
      ]);
    });

    test('the next weekly occurrence is on the weekday, later today or ahead',
        () {
      final tuesday = DateTime(2026, 3, 10, 12);
      expect(nextWeeklyOccurrence(tuesday, DateTime.tuesday, 13, 0),
          DateTime(2026, 3, 10, 13));
      expect(nextWeeklyOccurrence(tuesday, DateTime.tuesday, 7, 30),
          DateTime(2026, 3, 17, 7, 30));
      expect(nextWeeklyOccurrence(tuesday, DateTime.wednesday, 7, 30),
          DateTime(2026, 3, 11, 7, 30));
      expect(nextWeeklyOccurrence(tuesday, DateTime.monday, 7, 30),
          DateTime(2026, 3, 16, 7, 30));
      expect(nextWeeklyOccurrence(DateTime(2026, 12, 30, 20), DateTime.friday,
              7, 30),
          DateTime(2027, 1, 1, 7, 30));
    });

    test('weekly occurrences fall on the weekday only', () {
      final occurrences =
          _weekly(DateTime.sunday).occurrences(DateTime(2026, 3, 27, 12), 14);

      expect(occurrences.map((o) => (o.at.day, o.at.weekday, o.at.hour)), [
        (29, DateTime.sunday, 7),
        (5, DateTime.sunday, 7),
      ]);
    });

    test('ids are stable and differ per key', () {
      expect(reminderNotificationId(['a', 1]), reminderNotificationId(['a', 1]));
      expect(reminderNotificationId(['a', 1]),
          isNot(reminderNotificationId(['a', 2])));
      expect(reminderNotificationId('a'), lessThan(1 << 31));
    });
  });
}
