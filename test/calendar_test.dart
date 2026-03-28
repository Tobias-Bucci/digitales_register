import 'package:dr/ui/calendar.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendar paging helpers', () {
    test('pageOf and mondayOf are inverse operations for Mondays', () {
      final monday = UtcDateTime(2019, 4, 15);

      expect(pageOf(mondayOf(124564)), 124564);
      expect(mondayOf(pageOf(monday)), monday);
    });

    test('mondayOf always returns the monday of the represented page', () {
      final page = pageOf(UtcDateTime(2026, 3, 26));

      expect(mondayOf(page), UtcDateTime(2026, 3, 23));
    });
  });
}
