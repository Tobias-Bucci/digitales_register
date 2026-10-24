import 'package:dr/calendar_load_log.dart';
import 'package:dr/privacy_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal calendar logs summarize a year without per-week spam', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    logCalendarLoad(CalendarLoadEvent.historyStart, weeks: 44);
    for (var week = 0; week < 44; week++) {
      privacyLog('technical_operation');
      logCalendarLoad(CalendarLoadEvent.weekStart);
      logCalendarLoad(CalendarLoadEvent.weekReceived, elapsedMs: 120, days: 6);
      logCalendarLoad(CalendarLoadEvent.historyBatch, days: 24);
      logCalendarLoad(CalendarLoadEvent.cacheHit);
    }
    logCalendarLoad(CalendarLoadEvent.historyComplete,
        weeks: 44, elapsedMs: 4400);
    expect(messages.length, 2);
    expect(messages.last, contains('historyComplete'));
    expect(messages.last, contains('elapsed_ms=4400'));
    logCalendarLoad(CalendarLoadEvent.weekError, elapsedMs: 20000);
    expect(messages.length, 3, reason: 'failures must remain visible');
    privacyLog('private-response-content');
    expect(messages.last, contains('[redacted]'));
    expect(messages.join(), isNot(contains('private-response-content')));
  });
}
