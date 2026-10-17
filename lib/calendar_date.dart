/// Calendar coordinates, preserving the supplied year/month/day without timezone
/// conversion. UTC is only used to make day arithmetic independent of DST.
DateTime calendarDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

int calendarDaysBetween(DateTime end, DateTime start) =>
    calendarDate(end).difference(calendarDate(start)).inDays;
