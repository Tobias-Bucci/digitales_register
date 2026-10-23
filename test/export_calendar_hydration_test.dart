import 'package:dr/app_state.dart';
import 'package:dr/actions/calendar_actions.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_harness.dart';

class _CalendarSession extends Wrapper {
  int requests = 0;
  bool failOneWeek = false;
  @override
  Future<dynamic> send(String url,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    requests++;
    if (failOneWeek && requests == 2) return null;
    return <String, dynamic>{args['startDate']! as String: <String, dynamic>{}};
  }
}

void main() {
  tearDown(resetTestState);
  for (final failure in [false, true]) {
    test('calendar year reduces one batch; incomplete=$failure', () async {
      final session = _CalendarSession()..failOneWeek = failure;
      await bootstrapTestEnvironment(wrapperOverride: session);
      final state = AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'test');
      final payloads = <CalendarLoadedPayload>[];
      final complete = await loadExportCalendarYear(
          state: () => state,
          onLoaded: (data) async {
            payloads.add(data);
          });
      expect(complete, !failure);
      expect(payloads.length, 1,
          reason: 'avoid rebuilding the full growing calendar for every week');
      expect(payloads.single.data.length, session.requests - (failure ? 1 : 0));
      expect(payloads.single.completedSchoolYear, failure ? isNull : isNotNull);
    });
  }
}
