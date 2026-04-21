import 'package:dr/demo.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
    await resetDemoStoreForTest();
  });

  tearDown(() async {
    await resetDemoStoreForTest();
    await resetTestState();
  });

  test('demo login works with blank school and demo credentials', () async {
    final wrapper = Wrapper();

    await wrapper.login(
      'demo',
      'demo',
      null,
      '',
      logout: () {},
      configLoaded: () {},
      relogin: () {},
      addProtocolItem: (_) {},
    );

    expect(wrapper.demoMode, isTrue);
    expect(await wrapper.loggedIn, isTrue);
    expect(wrapper.user, 'demo');
    expect(wrapper.url, '');
  });

  test('demo reminders are stored locally and returned by dashboard', () async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final saved = await getDemoResponse(
      'api/student/dashboard/save_reminder',
      <String, Object?>{
        'date': today,
        'text': 'Mathematik wiederholen',
      },
    ) as Map<String, Object?>;

    final dashboard = await getDemoResponse(
      'api/student/dashboard/dashboard',
      <String, Object?>{'viewFuture': true},
    ) as List<dynamic>;

    final todayEntry = dashboard
        .cast<Map<String, Object?>>()
        .firstWhere((entry) => entry['date'] == today);
    final items =
        (todayEntry['items'] as List<dynamic>?)!.cast<Map<String, Object?>>();
    expect(
      items.any((item) => item['subtitle'] == 'Mathematik wiederholen'),
      isTrue,
    );

    final deleteResult = await getDemoResponse(
      'api/student/dashboard/delete_reminder',
      <String, Object?>{'id': saved['id']},
    ) as Map<String, Object?>;
    expect(deleteResult['success'], isTrue);

    final reloadedDashboard = await getDemoResponse(
      'api/student/dashboard/dashboard',
      <String, Object?>{'viewFuture': true},
    ) as List<dynamic>;
    final reloadedToday = reloadedDashboard
        .cast<Map<String, Object?>>()
        .firstWhere((entry) => entry['date'] == today);
    final reloadedItems =
        (reloadedToday['items'] as List<dynamic>?)!
            .cast<Map<String, Object?>>();
    expect(
      reloadedItems.any((item) => item['subtitle'] == 'Mathematik wiederholen'),
      isFalse,
    );
  });

  test('demo messages and certificate are available', () async {
    final messages = await getDemoResponse(
      'api/message/getMyMessages',
      const <String, Object?>{},
    ) as List<dynamic>;
    final certificate = await getDemoResponse(
      'student/certificate',
      const <String, Object?>{},
    ) as String;

    expect(messages, isNotEmpty);
    expect((messages.first as Map<String, Object?>)['subject'], isNotEmpty);
    expect(certificate, contains('Demo-Zeugnis'));
    expect(certificate, contains('Durchschnitt'));
  });
}
