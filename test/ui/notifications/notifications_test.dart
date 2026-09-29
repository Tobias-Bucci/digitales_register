import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/notifications_page_container.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/notifications_page.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/test_harness.dart';

void main() {
  setUp(() async {
    await bootstrapTestEnvironment();
  });

  tearDown(resetTestState);

  testWidgets('notification icon shows the unread badge count', (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.notificationState.notifications = ListBuilder<Notification>(
          <Notification>[
            Notification(
              (b) => b
                ..id = 1
                ..title = 'Neu'
                ..timeSent = UtcDateTime(2026, 3, 28),
            ),
          ],
        ),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: Material(child: NotificationIconContainer()),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.notifications), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('single notifications can be marked as read', (tester) async {
    final store = createStore(
      initialState: AppState(
        (b) => b.notificationState.notifications = ListBuilder<Notification>(
          <Notification>[
            Notification(
              (b) => b
                ..id = 0
                ..title = 'title1'
                ..timeSent = UtcDateTime(2020, 1, 2),
            ),
            Notification(
              (b) => b
                ..id = 1
                ..title = 'title2'
                ..timeSent = UtcDateTime(2020, 1, 2),
            ),
          ],
        ),
      ),
    );

    await pumpApp(
      tester,
      store: store,
      home: NotificationPageContainer(),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 200));

    expect(find.text('title1'), findsOneWidget);
    expect(find.byType(NotificationWidget), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.done).first);
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 350));

    expect(find.text('title1'), findsNothing);
    expect(find.byType(NotificationWidget), findsOneWidget);
  });

  testWidgets('mark all as read clears notifications and linked messages',
      (tester) async {
    final mockWrapper = MockWrapper();
    wrapper = mockWrapper;

    final notifications = <Notification>[
      Notification(
        (b) => b
          ..id = 0
          ..title = 'title0'
          ..timeSent = UtcDateTime(2021, 3, 12),
      ),
      Notification(
        (b) => b
          ..id = 2
          ..title = 'title2'
          ..timeSent = UtcDateTime(2021, 3, 12)
          ..objectId = 25
          ..type = 'message',
      ),
      Notification(
        (b) => b
          ..id = 3
          ..title = 'title3'
          ..timeSent = UtcDateTime(2021, 3, 12)
          ..objectId = 50
          ..type = 'message',
      ),
    ];

    when(
      () => mockWrapper.send(
        'api/notification/markAsRead',
        args: <String, Object?>{},
      ),
    ).thenAnswer((_) async => '');
    when(
      () => mockWrapper.send(
        'api/message/markAsRead',
        args: <String, Object?>{'messageId': 25},
      ),
    ).thenAnswer((_) async => '');
    when(
      () => mockWrapper.send(
        'api/message/markAsRead',
        args: <String, Object?>{'messageId': 50},
      ),
    ).thenAnswer((_) async => '');

    final store = createStore(
      initialState: AppState(
        (b) => b.notificationState.notifications = ListBuilder<Notification>(
          notifications,
        ),
      ),
      withMiddleware: true,
    );

    await pumpApp(
      tester,
      store: store,
      home: NotificationPageContainer(),
    );
    await settleFor(tester, duration: const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(Icons.done_all));
    await tester.pump();
    await settleFor(tester, duration: const Duration(milliseconds: 350));

    expect(find.textContaining('title'), findsNothing);
    expect(store.state.notificationState.notifications, BuiltList<Notification>());
  });
}
