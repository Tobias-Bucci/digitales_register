import 'dart:async';

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:dr/ui/polls/server_poll_page.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../server_notifications/support.dart';
import '../support/test_harness.dart';

const _id = '7c1e5b9a-2d4f-4e8b-9a6c-1f2e3d4c5b6a';

/// Finishes [future] inside the test's fake time; `sync` must not run inside
/// `runAsync`.
Future<void> _drive(WidgetTester tester, Future<Object?> future) async {
  var done = false;
  unawaited(future.whenComplete(() => done = true).catchError((Object _) {
    return null;
  }));
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump();
  }
  expect(done, isTrue, reason: 'future never finished');
}

Future<ServerNotificationRepository> _repository(
    WidgetTester tester, String fixtureName) async {
  final server = FakeServer()..reply(jsonResponse(fixture(fixtureName)));
  final repository = repositoryFor(server, FakeStorage.existingInstall());
  await _drive(tester, repository.sync(selection));
  return repository;
}

Future<void> _pumpDetail(
    WidgetTester tester, ServerNotificationRepository repository) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    theme: ThemeData(colorScheme: AppPalette.light),
    home: ServerNotificationDetailPage(id: _id, repository: repository),
  ));
  await settleFor(tester, duration: const Duration(milliseconds: 600));
}

/// The repository keeps an expiry timer; the test must not end with it.
Future<void> _close(
    WidgetTester tester, ServerNotificationRepository repository) async {
  await tester.pumpWidget(const SizedBox());
  repository.dispose();
  await settleFor(tester);
}

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(() async {
    await resetTestState();
  });

  testWidgets('a poll announcement opens the poll instead of the web page',
      (tester) async {
    final repository = await _repository(tester, 'list-poll');
    await _pumpDetail(tester, repository);

    expect(find.text('Welche Funktion wünschst du dir als Nächstes?'),
        findsOneWidget);
    expect(find.text('Umfrage'), findsOneWidget, reason: 'type label');
    expect(find.byKey(const Key('notification-open-poll')), findsOneWidget);
    // The web link is the same poll in the browser: not offered here too.
    expect(find.textContaining('www.digitalesregister.com'), findsNothing);

    await tester.tap(find.byKey(const Key('notification-open-poll')));
    await settleFor(tester, duration: const Duration(milliseconds: 600));
    expect(find.byType(ServerPollPage), findsOneWidget);
    await _close(tester, repository);
  });

  testWidgets('an unknown poll type keeps the web link', (tester) async {
    final repository = await _repository(tester, 'list-poll-unknown-type');
    await _pumpDetail(tester, repository);

    expect(find.byKey(const Key('notification-open-poll')), findsNothing);
    expect(find.text('www.digitalesregister.com öffnen'), findsOneWidget);
    await _close(tester, repository);
  });
}
