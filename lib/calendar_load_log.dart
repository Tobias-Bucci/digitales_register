import 'package:flutter/foundation.dart';

/// Closed, local debug events: never include dates, accounts or response data.
enum CalendarLoadEvent {
  weekStart,
  weekReceived,
  weekApplied,
  weekFailed,
  weekError,
  cacheHit,
  coalesced,
  cancelled,
  historyStart,
  historyBatch,
  historyComplete,
  historyIncomplete,
  backgroundError,
}

void logCalendarLoad(CalendarLoadEvent event,
    {int? elapsedMs, int? weeks, int? days}) {
  if (!kDebugMode) return;
  const verbose = bool.fromEnvironment('VERBOSE_CALENDAR_LOGS');
  if (!verbose &&
      const {
        CalendarLoadEvent.weekStart,
        CalendarLoadEvent.weekReceived,
        CalendarLoadEvent.cacheHit,
        CalendarLoadEvent.coalesced,
        CalendarLoadEvent.historyBatch,
      }.contains(event)) {
    return;
  }
  debugPrint('[Register][calendar] ${event.name}'
      '${elapsedMs == null ? '' : ' elapsed_ms=$elapsedMs'}'
      '${weeks == null ? '' : ' weeks=$weeks'}'
      '${days == null ? '' : ' days=$days'}');
}
