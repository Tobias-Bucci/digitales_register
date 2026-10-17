import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

class FailingStorage extends Mock implements FlutterSecureStorage {}

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  for (final failure in ['none', 'state-only', 'write', 'write-and-delete']) {
    test('hard logout completes exactly once with storage failure=$failure',
        () async {
      final oldWrapper = MockWrapper();
      when(() => oldWrapper.loginAddress).thenReturn(testLoginAddress);
      when(() => oldWrapper.url).thenReturn(testServerUrl);
      when(() => oldWrapper.logout(hard: true)).thenReturn(null);
      wrapper = oldWrapper;
      if (failure != 'none') {
        final failing = FailingStorage();
        when(() => failing.read(key: 'login')).thenAnswer((_) async =>
            '{"user":"old","pass":"password","url":"https://example.org"}');
        when(() => failing.write(
            key: any(named: 'key'),
            value: any(named: 'value'))).thenAnswer((invocation) async {
          if (failure != 'state-only' ||
              invocation.namedArguments[#key] != 'login') {
            throw StateError('secure storage write');
          }
        });
        when(() => failing.delete(key: 'login')).thenAnswer((_) async {
          if (failure == 'write-and-delete') throw StateError('storage delete');
        });
        secureStorage = failing;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('androidWidgetSnapshotV1', 'old data');
      final store = createStore(
          withMiddleware: true,
          initialState: AppState((b) => b
            ..loginState.loggedIn = true
            ..loginState.username = 'old'
            ..url = testServerUrl
            ..settingsState.noPasswordSaving = false));
      await store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = false));
      verify(() => oldWrapper.logout(hard: true)).called(1);
      expect(store.state.loginState.loggedIn, false);
      expect(store.state.loginState.username, isNull);
      expect(store.state.dashboardState.allDays, isNull);
      expect(prefs.getString('androidWidgetSnapshotV1'), isNull);
      expect(identical(wrapper, oldWrapper), false);
      if (failure == 'write' || failure == 'write-and-delete') {
        verify(() => secureStorage.delete(key: 'login')).called(1);
      }
    });
  }
}
