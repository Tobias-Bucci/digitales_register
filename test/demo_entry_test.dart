import 'dart:convert';

import 'package:dr/demo.dart';
import 'package:dr/desktop.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/web_app/demo_entry.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

void main() {
  group('demo path', () {
    for (final path in ['/demo', '/demo/', '/Demo', '/DEMO//']) {
      test('$path opens the demo', () {
        expect(DemoEntry.isDemoPath(path), isTrue);
      });
    }
    for (final path in ['/', '/demos', '/demo/grades', '/login', '']) {
      test('$path does not', () {
        expect(DemoEntry.isDemoPath(path), isFalse);
      });
    }
  });

  group('start', () {
    setUp(() async {
      await bootstrapTestEnvironment();
      DemoEntry.reset();
    });
    tearDown(() async {
      DemoEntry.reset();
      await resetTestState();
    });

    test('never starts in a native build', () {
      expect(DemoEntry.start(Uri.parse('https://example.org/demo'), web: false),
          isFalse);
      expect(DemoEntry.active, isFalse);
      expect(DemoEntry.secureStorage, isNull);
      expect(DemoEntry.takeSignIn(), isFalse);
    });

    test('a normal web start is unchanged', () async {
      final before = await SharedPreferences.getInstance();
      expect(
          DemoEntry.start(Uri.parse('https://app.example.org/grades'),
              web: true),
          isFalse);
      expect(DemoEntry.active, isFalse);
      expect(DemoEntry.takeSignIn(), isFalse);
      expect(await SharedPreferences.getInstance(), same(before));
      expect(getFlutterSecureStorage(), isNot(isA<MemorySecureStorage>()));
    });

    test('/demo keeps storage in memory and asks for one sign-in', () {
      expect(
          DemoEntry.start(Uri.parse('https://app.example.org/demo'), web: true),
          isTrue);
      expect(DemoEntry.active, isTrue);
      expect(getFlutterSecureStorage(), isA<MemorySecureStorage>());
      expect(getFlutterSecureStorage(), same(DemoEntry.secureStorage));
      expect(DemoEntry.takeSignIn(), isTrue);
      expect(DemoEntry.takeSignIn(), isFalse);
    });
  });

  group('start-up at /demo', () {
    const saved = {
      'user': 'real',
      'pass': 'secret',
      'url': 'https://school.digitalesregister.it',
    };

    setUp(() async {
      await bootstrapTestEnvironment(storage: {'login': jsonEncode(saved)});
      await resetDemoStoreForTest();
      DemoEntry.reset();
    });
    tearDown(() async {
      DemoEntry.reset();
      await resetDemoStoreForTest();
      await resetTestState();
    });

    test('signs in to the demo account, never to the saved one', () async {
      final browserStorage = secureStorage as TestSecureStorage;
      DemoEntry.start(Uri.parse('https://app.example.org/demo'), web: true);
      // main() takes the storage after DemoEntry.start.
      secureStorage = getFlutterSecureStorage();
      wrapper = Wrapper();

      final store = createStore(withMiddleware: true);
      await store.actions.load();

      expect(store.state.loginState.loggedIn, isTrue);
      expect(store.state.loginState.username, 'demo');
      expect(wrapper.demoMode, isTrue);
      expect(store.state.loginState.otherAccounts, isEmpty);
      // The browser's own storage was neither read for a login nor changed.
      expect(browserStorage.storage, {'login': jsonEncode(saved)});
    });

    test('without /demo the saved account is used as before', () async {
      final store = createStore(withMiddleware: true);
      await store.actions.load();

      expect(store.state.loginState.username, isNot('demo'));
      expect(wrapper.demoMode, isFalse);
    });
  });
}
