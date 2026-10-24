import 'package:biometric_storage/biometric_storage.dart';
import 'package:dr/biometric_app_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dr/biometric_app_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late BiometricAppLockController controller;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = <MethodCall>[];
    controller = BiometricAppLockController();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'canAuthenticate' => 'success',
        'authenticate' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reports availability through the android prompt', () async {
    expect(
      await controller.checkAvailability(),
      CanAuthenticateResponse.success,
    );
    expect(calls.single.method, 'canAuthenticate');
  });

  test('enabling the lock authenticates and leaves the app unlocked', () async {
    await controller.enable();

    expect(controller.isEnabled, isTrue);
    expect(controller.isLocked, isFalse);
    expect(
      calls.map((call) => call.method),
      <String>['canAuthenticate', 'authenticate'],
    );
    final arguments = calls.last.arguments as Map<Object?, Object?>;
    expect(arguments['title'], isNotEmpty);
    expect(arguments['negativeButton'], isNotEmpty);
  });

  test('a successful prompt unlocks the app', () async {
    await controller.enable();
    controller.lock();
    expect(controller.isLocked, isTrue);

    expect(await controller.authenticateIfNeeded(), isTrue);
    expect(controller.isLocked, isFalse);
  });

  test('a canceled prompt keeps the app locked', () async {
    await controller.enable();
    controller.lock();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        throw PlatformException(code: 'canceled');
      }
      return 'success';
    });

    expect(await controller.authenticateIfNeeded(), isFalse);
    expect(controller.isLocked, isTrue);
  });

  test('a canceled setup leaves the lock disabled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'authenticate') {
        throw PlatformException(code: 'canceled');
      }
      return 'success';
    });

    await expectLater(
      controller.enable(),
      throwsA(isA<BiometricAppLockSetupException>()),
    );
    expect(controller.isEnabled, isFalse);
  });

  // Only an explicit `true` from the platform prompt may authenticate; a `false`
  // or missing result must not be mistaken for success.
  for (final result in <Object?>[false, null]) {
    final label = result == null ? 'null' : 'false';

    test('enabling the lock fails when the prompt returns $label', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'canAuthenticate' => 'success',
          'authenticate' => result,
          _ => null,
        };
      });

      await expectLater(
        controller.enable(),
        throwsA(isA<BiometricAppLockSetupException>()),
      );
      expect(controller.isEnabled, isFalse);
      expect(controller.isLocked, isFalse);
    });

    test('a prompt returning $label keeps the app locked', () async {
      await controller.enable();
      controller.lock();
      expect(controller.isLocked, isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'canAuthenticate' => 'success',
          'authenticate' => result,
          _ => null,
        };
      });

      expect(await controller.authenticateIfNeeded(), isFalse);
      expect(controller.isLocked, isTrue);
    });
  }
}
