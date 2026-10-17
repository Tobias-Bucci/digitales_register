import 'dart:convert';

import 'package:dr/middleware/middleware.dart';
import 'package:dr/stored_login.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/test_harness.dart';

class RepairFailingStorage extends Mock implements FlutterSecureStorage {}

void main() {
  const valid = {
    'user': 'kept',
    'pass': 'secret',
    'url': 'https://example.org'
  };
  test('valid primary and secondary accounts survive validation', () {
    expect(
        decodeStoredLogin(jsonEncode({
          ...valid,
          'otherAccounts': [valid]
        })),
        {
          ...valid,
          'otherAccounts': [valid]
        });
  });
  for (final invalid in <Object?>[
    {},
    {'user': null},
    {'user': 5},
    {'user': 'missing credentials'},
    'text',
    4,
    null,
  ]) {
    test('isolates invalid secondary account $invalid', () {
      final result = decodeStoredLogin(jsonEncode({
        ...valid,
        'otherAccounts': [invalid, valid],
      }));
      expect(result['user'], 'kept');
      expect(result['otherAccounts'], [valid]);
    });
  }
  for (final invalid in ['[]', 'null', '5', '"text"', '{']) {
    test('recovers invalid root $invalid', () {
      expect(decodeStoredLogin(invalid), isEmpty);
    });
  }
  test('invalid primary does not discard secondary; wrong list is isolated',
      () {
    expect(
        decodeStoredLogin(jsonEncode({
          'user': 5,
          'otherAccounts': [valid]
        })),
        {
          'otherAccounts': [valid]
        });
    expect(decodeStoredLogin(jsonEncode({...valid, 'otherAccounts': 'bad'})),
        valid);
  });
  test('startup repairs corrupt account list and reaches login route',
      () async {
    await bootstrapTestEnvironment(storage: {
      'login': jsonEncode({
        'otherAccounts': [5, valid]
      }),
    });
    addTearDown(resetTestState);
    final store = createStore(withMiddleware: true);
    await store.actions.load();
    expect(store.state.loginState.otherAccounts.toList(), ['kept']);
    expect(store.state.loginState.loggedIn, false);
    expect(
        jsonDecode((await secureStorage.read(key: 'login'))!)['otherAccounts'],
        [valid]);
  });
  test('failed repair write preserves recovered secondary accounts in memory',
      () async {
    await bootstrapTestEnvironment();
    addTearDown(resetTestState);
    final failing = RepairFailingStorage();
    when(() => failing.read(key: 'login')).thenAnswer((_) async => jsonEncode({
          'otherAccounts': [5, valid]
        }));
    when(() => failing.write(key: 'login', value: any(named: 'value')))
        .thenThrow(StateError('repair write'));
    secureStorage = failing;
    final store = createStore(withMiddleware: true);
    await store.actions.load();
    expect(store.state.loginState.otherAccounts.toList(), ['kept']);
    expect(store.state.loginState.loggedIn, false);
  });
}
