import 'package:dr/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removes the polling data of older versions and nothing else', () async {
    SharedPreferences.setMockInitialValues({
      'backgroundNotificationLogs': '[]',
      'pushNotificationsEnabled': true,
      'appLanguage': 'de',
    });
    await removeLegacyNotificationData();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'appLanguage'});
  });
}
