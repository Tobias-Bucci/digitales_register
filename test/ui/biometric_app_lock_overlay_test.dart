import 'dart:async';

import 'package:dr/biometric_app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProtectedIntent extends Intent {
  const _ProtectedIntent();
}

final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dr/biometric_app_lock');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<bool> authentication;
  late FocusNode fieldNode;
  late FocusNode buttonNode;
  late TextEditingController text;
  late int keysReceived;
  late int shortcutsInvoked;
  late int buttonPresses;

  setUp(() {
    biometricAppLockController.syncEnabled(false);
    authentication = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') return authentication.future;
      return 'success';
    });
    fieldNode = FocusNode();
    buttonNode = FocusNode();
    text = TextEditingController();
    keysReceived = 0;
    shortcutsInvoked = 0;
    buttonPresses = 0;
  });

  tearDown(() async {
    if (!authentication.isCompleted) authentication.complete(false);
    await Future<void>.delayed(Duration.zero);
    biometricAppLockController.syncEnabled(false);
    messenger.setMockMethodCallHandler(channel, null);
    fieldNode.dispose();
    buttonNode.dispose();
    text.dispose();
  });

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BiometricAppLockOverlay(
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _ProtectedIntent(),
            },
            child: Actions(
              actions: {
                _ProtectedIntent: CallbackAction<_ProtectedIntent>(
                  onInvoke: (_) => shortcutsInvoked++,
                ),
              },
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent) keysReceived++;
                  return KeyEventResult.ignored;
                },
                child: Column(
                  children: [
                    TextField(focusNode: fieldNode, controller: text),
                    TextButton(
                      focusNode: buttonNode,
                      onPressed: () => buttonPresses++,
                      child: const Text('protected action'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    fieldNode.requestFocus();
    await tester.pump();
    expect(fieldNode.hasFocus, isTrue);
  }

  // The prompt answers through the mocked platform channel, which completes
  // outside the fake clock; the post-unlock focus restore runs a frame later.
  Future<void> settleAuthentication(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
  }

  Future<void> lock(WidgetTester tester) async {
    biometricAppLockController.syncEnabled(true);
    await tester.pump();
    expect(biometricAppLockController.isLocked, isTrue);
  }

  testWidgets('locked app drops focus and blocks keys, shortcuts and traversal',
      (tester) async {
    await pumpOverlay(tester);
    await lock(tester);

    expect(fieldNode.hasFocus, isFalse);
    expect(buttonNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(fieldNode.hasFocus, isFalse);
      expect(buttonNode.hasFocus, isFalse);
    }

    expect(keysReceived, 0);
    expect(shortcutsInvoked, 0);
    expect(buttonPresses, 0);
    expect(text.text, isEmpty);

    // Programmatic focus requests are refused while locked as well.
    buttonNode.requestFocus();
    await tester.pump();
    expect(buttonNode.hasFocus, isFalse);
  }, variant: _android);

  testWidgets('unlock button stays usable by keyboard and restores focus',
      (tester) async {
    await pumpOverlay(tester);
    await lock(tester);

    final unlock = find.widgetWithIcon(FilledButton, Icons.lock_open_rounded);
    expect(unlock, findsOneWidget);
    // Traversal reaches the unlock control, which can then be activated.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final unlockFocus = Focus.of(tester
        .element(find.descendant(of: unlock, matching: find.byType(Icon))));
    expect(unlockFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(biometricAppLockController.isAuthenticating, isTrue);

    authentication.complete(true);
    await settleAuthentication(tester);
    expect(biometricAppLockController.isLocked, isFalse);
    expect(fieldNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(keysReceived, 1);
  }, variant: _android);

  testWidgets('cancelled authentication keeps the protected content isolated',
      (tester) async {
    await pumpOverlay(tester);
    await lock(tester);

    await tester.tap(find.byIcon(Icons.lock_open_rounded));
    await tester.pump();
    authentication.complete(false);
    await settleAuthentication(tester);

    expect(biometricAppLockController.isLocked, isTrue);
    expect(fieldNode.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(keysReceived, 0);
    expect(text.text, isEmpty);

    // A later lock/resume cycle unlocks normally and restores focus.
    authentication = Completer<bool>();
    await tester.tap(find.byIcon(Icons.lock_open_rounded));
    await tester.pump();
    authentication.complete(true);
    await settleAuthentication(tester);
    expect(biometricAppLockController.isLocked, isFalse);
    expect(fieldNode.hasFocus, isTrue);
  }, variant: _android);
}
