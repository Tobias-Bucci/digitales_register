import 'dart:async';
import 'dart:convert';

import 'package:dr/android_widget_service.dart';
import 'package:dr/app_state.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixtures.dart';

class RecordingWidgetBridge extends AndroidWidgetPlatformBridge {
  final snapshots = <String?>[];
  final planningSnapshots = <String?>[];
  @override
  Future<void> writePlanningSnapshot(String? payload) async {
    planningSnapshots.add(payload);
  }

  @override
  Future<void> refreshWidgets() async {
    snapshots.add((await SharedPreferences.getInstance())
        .getString(androidWidgetSnapshotStorageKey));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockNow = fixtureNow;
  });
  tearDown(() => mockNow = null);
  final loggedIn = AppState((b) => b.loginState
    ..loggedIn = true
    ..username = 'old');

  test('normal flush and repeated clear refresh after deletion', () async {
    final bridge = RecordingWidgetBridge();
    final service = AndroidWidgetSnapshotService(bridge: bridge);
    await service.flush(state: loggedIn);
    expect(bridge.snapshots, hasLength(1));
    await service.clear();
    await service.clear();
    expect(bridge.snapshots, hasLength(3));
    expect(bridge.snapshots.skip(1), everyElement(isNull));
    expect(bridge.planningSnapshots.skip(1), everyElement(isNull));
  });

  test('privacy changes cancel pending content without waiting for debounce',
      () async {
    final bridge = RecordingWidgetBridge();
    final service = AndroidWidgetSnapshotService(
      bridge: bridge,
      debounce: const Duration(days: 1),
    );
    service.scheduleSync(loggedIn);
    service.scheduleSync(loggedIn
        .rebuild((b) => b.settingsState.biometricAppLockEnabled = true));
    // A subsequent flush waits behind the immediate redaction operation.
    await service.flush(
        state: loggedIn
            .rebuild((b) => b.settingsState.biometricAppLockEnabled = true));
    expect(bridge.snapshots, hasLength(1));
    expect(jsonDecode(bridge.snapshots.single!)['meta']['status'], 'appLocked');
    expect(bridge.planningSnapshots, bridge.snapshots);
    await service.clear();
  });
  for (final newFlush in [false, true]) {
    test('blocked old flush, clear, new flush=$newFlush preserves ordering',
        () async {
      final barrier = Completer<SharedPreferences>();
      final entered = Completer<void>();
      var requests = 0;
      final bridge = RecordingWidgetBridge();
      final service = AndroidWidgetSnapshotService(
          bridge: bridge,
          preferences: () {
            if (++requests == 1) {
              entered.complete();
              return barrier.future;
            }
            return SharedPreferences.getInstance();
          });
      final old = service.flush(state: loggedIn);
      await entered.future;
      final concurrent = service.flush(
          state: loggedIn.rebuild((b) => b..settingsState.noDataSaving = true));
      final clear = service.clear();
      final next =
          newFlush ? service.flush(state: AppState()) : Future<void>.value();
      barrier.complete(await SharedPreferences.getInstance());
      await Future.wait([old, concurrent, clear, next]);
      final prefs = await SharedPreferences.getInstance();
      expect(bridge.snapshots[2], isNull);
      expect(bridge.planningSnapshots, bridge.snapshots);
      if (newFlush) {
        final payload = prefs.getString(androidWidgetSnapshotStorageKey)!;
        expect(jsonDecode(payload)['meta']['status'], 'loggedOut');
        expect(bridge.snapshots, hasLength(4));
      } else {
        expect(prefs.getString(androidWidgetSnapshotStorageKey), isNull);
        expect(bridge.snapshots, hasLength(3));
      }
    });
  }
  test('failed old write does not poison subsequent clear', () async {
    var calls = 0;
    final service = AndroidWidgetSnapshotService(preferences: () async {
      if (++calls == 1) throw StateError('storage');
      return SharedPreferences.getInstance();
    });
    final old = service.flush(state: loggedIn);
    final clear = service.clear();
    await expectLater(old, throwsStateError);
    await clear;
    expect(
        (await SharedPreferences.getInstance())
            .getString(androidWidgetSnapshotStorageKey),
        isNull);
  });

  test('app-group clear still runs when app preference access fails', () async {
    final bridge = RecordingWidgetBridge();
    final service = AndroidWidgetSnapshotService(
      bridge: bridge,
      preferences: () async => throw StateError('storage unavailable'),
    );
    await expectLater(service.clear(), throwsStateError);
    expect(bridge.planningSnapshots, [null]);
    expect(bridge.snapshots, [null]);
  });
}
