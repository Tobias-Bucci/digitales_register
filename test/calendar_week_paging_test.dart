// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:dr/app_state.dart';
import 'package:dr/serializers.dart';
import 'package:dr/ui/calendar.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

// #180: the calendar maps weeks to pages of a page view and keeps the shown
// week in calendarState.currentMonday.
void main() {
  final today = UtcDateTime(2026, 11, 26, 10);

  setUp(() async {
    await bootstrapTestEnvironment(fixedNow: today);
  });

  tearDown(resetTestState);

  Iterable<UtcDateTime> mondays(UtcDateTime from, UtcDateTime to) sync* {
    for (var monday = toMonday(from);
        !monday.isAfter(to);
        monday = monday.add(const Duration(days: 7))) {
      yield monday;
    }
  }

  group('pages', () {
    test('every Monday is the Monday of its page, a week per page', () {
      for (final monday in mondays(UtcDateTime(2015), UtcDateTime(2040))) {
        expect(monday.weekday, DateTime.monday);
        expect(mondayOf(pageOf(monday)), monday, reason: '$monday');
        expect(
          pageOf(monday.add(const Duration(days: 7))),
          pageOf(monday) + 1,
          reason: '$monday',
        );
      }
    });

    test('every moment of a school day belongs to the page of its Monday', () {
      for (final monday in mondays(UtcDateTime(2025), UtcDateTime(2027))) {
        for (var day = 0; day < 5; day++) {
          for (final time in const [
            Duration.zero,
            Duration(hours: 1),
            Duration(hours: 23, minutes: 59, seconds: 59),
          ]) {
            final moment = monday.add(Duration(days: day) + time);
            expect(pageOf(moment), pageOf(monday), reason: '$moment');
          }
        }
        // As everywhere else, the weekend already shows the next week.
        final saturday = monday.add(const Duration(days: 5, hours: 12));
        expect(pageOf(saturday), pageOf(monday) + 1, reason: '$saturday');
      }
    });

    // The app works with the wall time of the device, whatever its offset.
    // Two weeks around both changes of summer time in Italy and any offset
    // from UTC-12 to UTC+14.
    test('next week is the following page in every time zone and across DST',
        () {
      for (final instant in [
        DateTime.utc(2026, 3, 27, 22),
        DateTime.utc(2026, 10, 23, 22),
        DateTime.utc(2026, 12, 31, 23, 30),
      ]) {
        for (var offset = -12 * 60; offset <= 14 * 60; offset += 30) {
          for (var hour = 0; hour < 72; hour += 3) {
            final wallTime =
                instant.add(Duration(minutes: offset, hours: hour));
            final device = UtcDateTime.makeUtc(wallTime);
            final monday = toMonday(device);
            final next = mondayOf(pageOf(monday) + 1);
            expect(next, monday.add(const Duration(days: 7)),
                reason: '$wallTime');
            expect(next.difference(monday), const Duration(days: 7));
            expect(next.hour + next.minute + next.second, 0);
          }
        }
      }
    });

    test('Europe/Rome wall times on the days of the clock change', () {
      // 02:30 on 29.3.2026 does not exist in Italy, 02:30 on 25.10.2026 twice.
      for (final wall in [
        DateTime(2026, 3, 29, 2, 30),
        DateTime(2026, 3, 29, 3, 30),
        DateTime(2026, 10, 25, 2, 30),
        DateTime(2026, 10, 25, 1, 59),
      ]) {
        final device = UtcDateTime.makeUtc(wall);
        final monday = toMonday(device);
        expect(mondayOf(pageOf(device)), monday, reason: '$wall');
        expect(
            mondayOf(pageOf(monday) + 1), monday.add(const Duration(days: 7)));
      }
    });
  });

  group('calendarMonday', () {
    test('is the Monday at UTC midnight of the week', () {
      expect(
        calendarMonday(UtcDateTime(2026, 11, 25, 15, 30), today: today),
        UtcDateTime(2026, 11, 23),
      );
      expect(
        calendarMonday(UtcDateTime(2026, 11, 23, 0, 0, 0, 0, 1), today: today),
        UtcDateTime(2026, 11, 23),
      );
    });

    test('keeps the week within two school years of the current one', () {
      final range = calendarMondayRange(today);
      expect(range.first, UtcDateTime(2024, 9, 2));
      expect(range.last, UtcDateTime(2029, 8, 27));
      expect(range.first.weekday, DateTime.monday);
      expect(range.last.weekday, DateTime.monday);

      expect(calendarMonday(UtcDateTime(2033, 5, 9), today: today), range.last);
      expect(
          calendarMonday(UtcDateTime(2010, 1, 4), today: today), range.first);
      expect(calendarMonday(UtcDateTime(1970), today: today), range.first);
      expect(calendarMonday(range.last, today: today), range.last);
      expect(calendarMonday(range.first, today: today), range.first);
    });

    test('the school year starts in September', () {
      expect(
        calendarMondayRange(UtcDateTime(2027, 8, 31)).first,
        calendarMondayRange(UtcDateTime(2026, 9, 1)).first,
      );
      expect(
        calendarMondayRange(UtcDateTime(2027, 9, 1)).first,
        UtcDateTime(2025, 9, 1),
      );
    });
  });

  group('currentMonday', () {
    test('a week far away is brought back into the calendar', () async {
      final store = createStore(initialState: AppState());

      await store.actions.calendarActions
          .setCurrentMonday(UtcDateTime(2033, 5, 9));
      expect(
        store.state.calendarState.currentMonday,
        calendarMondayRange(today).last,
      );

      await store.actions.calendarActions
          .setCurrentMonday(UtcDateTime(2010, 1, 4));
      expect(
        store.state.calendarState.currentMonday,
        calendarMondayRange(today).first,
      );
    });

    test('a day with a time is stored as its Monday', () async {
      final store = createStore(initialState: AppState());

      await store.actions.calendarActions
          .setCurrentMonday(UtcDateTime(2026, 12, 2, 23, 59));
      expect(
          store.state.calendarState.currentMonday, UtcDateTime(2026, 11, 30));
    });

    test('is not persisted, so a restart starts at a valid week', () {
      final state = AppState(
        (b) => b.calendarState.currentMonday = UtcDateTime(2033, 5, 9),
      );
      final restored =
          serializers.deserialize(serializers.serialize(state)) as AppState;
      expect(restored.calendarState.currentMonday, isNull);
    });
  });
}
