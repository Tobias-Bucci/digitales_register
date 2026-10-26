import 'package:dr/desktop.dart';
import 'package:dr/school_notification_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors flutter_secure_storage_darwin 0.3.2: every query carries
/// kSecAttrAccessible when an accessibility option is set, existence checks
/// use that query, and SecItemAdd collides with an item of another class.
/// Deletion ignores the class. New items without a class are when-unlocked.
class _Keychain {
  final items = <String, ({String value, String accessible})>{};

  bool _matches(String key, Map options) {
    final item = items[key];
    final accessible = options['accessibility'];
    return item != null && (accessible == null || item.accessible == accessible);
  }

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map;
    final key = args['key'] as String?;
    final options = args['options'] as Map;
    switch (call.method) {
      case 'read':
        return _matches(key!, options) ? items[key]!.value : null;
      case 'containsKey':
        return _matches(key!, options);
      case 'delete':
        items.remove(key);
        return null;
      case 'write':
        final value = args['value'] as String;
        if (_matches(key!, options)) {
          items[key] = (value: value, accessible: items[key]!.accessible);
        } else if (items.containsKey(key)) {
          throw PlatformException(
              code: 'Unexpected security result code', details: -25299);
        } else {
          items[key] = (
            value: value,
            accessible: options['accessibility'] as String? ?? 'unlocked'
          );
        }
        return null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _Keychain keychain;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    keychain = _Keychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, keychain.handle);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reproduces the class-specific read that hid the UI login from workers',
      () async {
    // Previous UI storage and previous notification storage.
    await const FlutterSecureStorage().write(key: 'login', value: '{"user":1}');
    const previous = FlutterSecureStorage(
        iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device));
    expect(await previous.read(key: 'login'), isNull);
    await expectLater(previous.write(key: 'login', value: '{"user":1}'),
        throwsA(isA<PlatformException>()));
  });

  test('worker storage reads the UI login and upgrades it after first unlock',
      () async {
    await getFlutterSecureStorage().write(key: 'login', value: '{"user":1}');
    expect(keychain.items['login']!.accessible, 'unlocked');

    const worker = SchoolNotificationKeychain();
    final login = await worker.read(key: 'login');
    expect(login, '{"user":1}');
    await worker.write(key: 'login', value: login);
    expect(keychain.items['login'],
        (value: '{"user":1}', accessible: 'first_unlock_this_device'));

    // Its own records are created readable after the first unlock.
    await worker.write(key: 'school-notification-active', value: 'a');
    expect(keychain.items['school-notification-active']!.accessible,
        'first_unlock_this_device');
  });

  test('UI storage keeps reading and updating an upgraded login', () async {
    const worker = SchoolNotificationKeychain();
    await worker.write(key: 'login', value: '{"user":1}');
    final ui = getFlutterSecureStorage();
    expect(await ui.read(key: 'login'), '{"user":1}');

    await ui.write(key: 'login', value: '{"user":2}');
    expect(keychain.items['login'],
        (value: '{"user":2}', accessible: 'first_unlock_this_device'));
    // The previous fixed-class UI storage would have lost access entirely.
    expect(await const FlutterSecureStorage().read(key: 'login'), isNull);

    await ui.delete(key: 'login');
    expect(await worker.read(key: 'login'), isNull);
  });

  test('an upgrade failure never removes the saved login', () async {
    await getFlutterSecureStorage().write(key: 'login', value: '{"user":1}');
    var failNextAdd = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final options = (call.arguments as Map)['options'] as Map;
      if (call.method == 'delete') failNextAdd = true;
      if (call.method == 'write' &&
          failNextAdd &&
          options['accessibility'] != null) {
        failNextAdd = false;
        throw PlatformException(code: 'interaction_not_allowed');
      }
      return keychain.handle(call);
    });

    await expectLater(
        const SchoolNotificationKeychain()
            .write(key: 'login', value: '{"user":1}'),
        throwsA(isA<PlatformException>()));
    expect(await getFlutterSecureStorage().read(key: 'login'), '{"user":1}');
  });
}
