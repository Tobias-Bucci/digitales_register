import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression for #23 (Crashlytics 9c741071): a calendar provider on
  // Android 9 named the IS_PRIMARY column after its SQL expression, so the
  // lookup by name threw and calendar sync could not list any calendar.
  test('Android calendar list reads columns by projection position', () {
    final source = File('android/app/src/main/kotlin/it/bucci/'
            'digitalesregister/MainActivity.kt')
        .readAsStringSync();
    expect(source,
        isNot(contains('getColumnIndexOrThrow(CalendarContract.Calendars.')));
    for (final column in [
      '_ID',
      'CALENDAR_DISPLAY_NAME',
      'ACCOUNT_NAME',
      'OWNER_ACCOUNT',
      'IS_PRIMARY',
      'VISIBLE',
      'CALENDAR_ACCESS_LEVEL',
    ]) {
      expect(source,
          contains('projection.indexOf(CalendarContract.Calendars.$column)'));
    }
  });
}
