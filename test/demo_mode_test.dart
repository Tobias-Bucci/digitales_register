import 'package:dr/app_clock.dart';
import 'package:dr/demo.dart';
import 'package:dr/ui/homework_summary_page.dart';
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

  test('demo login after a failed offline sign-in is not offline', () async {
    final wrapper = Wrapper()..noInternet = true;

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
    expect(wrapper.noInternet, isFalse);
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
    final reloadedItems = (reloadedToday['items'] as List<dynamic>?)!
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

  test('the demo answers the homework summary with the coming weeks', () async {
    appClock.setDemoMode(true);
    addTearDown(() => appClock.setDemoMode(false));

    final html = await getDemoResponse(
      'vorstand/homework&klasse?_=1760083200000',
      const <String, Object?>{},
    );

    expect(html, isA<String>());
    final document = HomeworkSummaryDocument.parse(html as String);
    expect(document.title, isNotEmpty);
    expect(document.weeks, hasLength(4));
    final entries = [for (final week in document.weeks) ...week.entries];
    // The default demo day (10 October 2025) has homework and exams ahead.
    expect(entries, isNotEmpty);
    expect(entries.every((entry) => entry.subjectText.isNotEmpty), isTrue);
    expect(entries.every((entry) => entry.primaryText.isNotEmpty), isTrue);
  });

  test('archiving a demo message survives reloading the message list',
      () async {
    final messages = await getDemoResponse(
      'api/message/getMyMessages',
      const <String, Object?>{},
    ) as List<dynamic>;
    final id = (messages.first as Map)['id'];
    final response = await getDemoResponse(
      'api/message/archiveMessage',
      <String, Object?>{'messageId': id, 'archiveType': 1},
    ) as Map;
    expect(response['success'], isTrue);

    final reloaded = await getDemoResponse(
      'api/message/getMyMessages',
      const <String, Object?>{},
    ) as List<dynamic>;
    final archived = reloaded.cast<Map>().firstWhere((m) => m['id'] == id);
    expect(archived['label_archived'], isTrue);
    expect(archived['label_incoming'], isFalse);
    expect(archived['label_all'], isTrue);
    expect(archived['archiveMessageEnabled'], 2);

    await getDemoResponse('api/message/archiveMessage',
        <String, Object?>{'messageId': id, 'archiveType': 2});
    final restoredMessages = await getDemoResponse(
      'api/message/getMyMessages',
      const <String, Object?>{},
    ) as List<dynamic>;
    final restored =
        restoredMessages.cast<Map>().firstWhere((m) => m['id'] == id);
    expect(restored['label_archived'], isFalse);
    expect(restored['label_incoming'], isTrue);
    expect(restored['archiveMessageEnabled'], 1);
  });

  test('assessment settings persist, filter, and reset with the demo cache',
      () async {
    await setDemoAssessmentSettings(const DemoAssessmentSettings(
      range: DemoAssessmentRange.firstSemester,
      customCount: 3,
    ));
    expect(
      (await getDemoAssessmentSettings()).range,
      DemoAssessmentRange.firstSemester,
    );

    final calendar = await getDemoResponse(
      'api/calendar/student',
      <String, Object?>{'startDate': '2026-03-02'},
    ) as Map<String, dynamic>;
    final exams = calendar.values
        .cast<Map<String, dynamic>>()
        .expand((day) =>
            ((day['1'] as Map<String, dynamic>)['1'] as Map<String, dynamic>)
                .values)
        .cast<Map<String, dynamic>>()
        .expand((entry) =>
            (entry['lesson'] as Map<String, dynamic>)['homeworkExams'] as List)
        .where((entry) => (entry as Map<String, dynamic>)['warning'] == true);
    expect(exams, isEmpty);

    await clearDemoCache();
    expect(
      (await getDemoAssessmentSettings()).range,
      DemoAssessmentRange.fullYear,
    );
  });
}
