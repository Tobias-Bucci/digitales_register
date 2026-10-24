import 'dart:async';

import 'package:dr/biometric_app_lock.dart';
import 'package:dr/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dr/biometric_app_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<bool> authentication;
  late int promptCount;
  late int refreshCount;
  late LifecycleObserver observer;

  setUp(() async {
    await bootstrapTestEnvironment();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    biometricAppLockController.syncEnabled(false);
    biometricAppLockController.syncEnabled(true);
    authentication = Completer<bool>();
    promptCount = 0;
    refreshCount = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') {
        promptCount++;
        return authentication.future;
      }
      return 'success';
    });
    observer = LifecycleObserver(() => refreshCount++, () {});
  });

  tearDown(() async {
    biometricAppLockController.syncEnabled(false);
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    await resetTestState();
  });

  test('overlapping resumes share one prompt and dispatch one refresh',
      () async {
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(promptCount, 1);
    expect(refreshCount, 0);
    authentication.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(refreshCount, 1);
  });

  test('canceled biometric prompt does not refresh the account', () async {
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    authentication.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(refreshCount, 0);
    expect(biometricAppLockController.isLocked, isTrue);
  });

  test('returning to the background during authentication does not refresh',
      () async {
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    observer.didChangeAppLifecycleState(AppLifecycleState.paused);
    authentication.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(refreshCount, 0);
  });
}
