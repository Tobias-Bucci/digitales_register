import 'package:built_collection/built_collection.dart';
import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/data.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/dashboard_event_banner.dart';
import 'package:dr/ui/server_notifications/server_notification_center.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/test_harness.dart';

final _today = UtcDateTime(2026, 3, 2);
final _long =
    List.filled(30, 'Die Anmeldung ist im Sekretariat möglich.').join(' ');

Notification _news(int id, {String? title}) => buildNotification(
      id: id,
      title: title ?? 'Elternsprechtag $id',
      subTitle: _long,
      timeSent: UtcDateTime(2026, 3, 1, 9 + id),
    );

AppState _state(List<Notification> notifications, {required bool offline}) =>
    AppState((b) {
      b.dashboardState.allDays = ListBuilder<Day>([buildDay(date: _today)]);
      b.notificationState
        ..notifications = ListBuilder<Notification>(notifications)
        ..lastFetched = _today;
      b.loginState
        ..loggedIn = true
        ..username = 'anna';
      b.url = 'https://school.example';
      b.noInternet = offline;
    });

void main() {
  setUp(bootstrapTestEnvironment);
  tearDown(resetTestState);

  Future<Store<AppState, AppStateBuilder, AppActions>> pump(
      WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = createStore(
      initialState: state,
      newDesign: true,
      withMiddleware: true,
    );
    await pumpApp(tester, store: store, home: DaysContainer());
    await settleFor(tester);
    return store;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('a single inline notification opens its full text',
      (tester) async {
    await pump(tester, _state([_news(1)], offline: true));

    await tester.tap(find.byType(EventBanner));
    await settleFor(tester, duration: const Duration(seconds: 1));

    expect(find.byType(SchoolNotificationDetailView), findsOneWidget);
    expect(find.text(_long), findsOneWidget);

    // Back leads to the center and from there to the dashboard. (pageBack
    // looks for an English tooltip, and the app speaks German here.)
    await tester.tap(find.byType(BackButton));
    await settleFor(tester, duration: const Duration(seconds: 1));
    expect(find.byType(ServerNotificationCenterPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settleFor(tester, duration: const Duration(seconds: 1));
    expect(find.byType(EventBanner), findsOneWidget);
    await finish(tester);
  });

  testWidgets('with several, the tapped one is opened', (tester) async {
    await pump(
      tester,
      _state([_news(2, title: 'Neuer'), _news(1, title: 'Älter')],
          offline: true),
    );

    // The banner shows the newest one.
    await tester.tap(find.byType(EventBanner));
    await settleFor(tester, duration: const Duration(seconds: 1));

    final detail = tester.widget<SchoolNotificationDetailView>(
        find.byType(SchoolNotificationDetailView));
    expect(detail.notification.id, 2);
    await finish(tester);
  });

  testWidgets('opening it marks it read and the badge goes down',
      (tester) async {
    final mock = MockWrapper();
    wrapper = mock;
    when(() => mock.send(any(), args: any(named: 'args')))
        .thenAnswer((_) async => '');
    when(() => mock.url).thenReturn('https://school.example');
    when(() => mock.loginAddress).thenReturn('https://school.example');
    when(() => mock.user).thenReturn('anna');
    when(() => mock.demoMode).thenReturn(false);
    when(() => mock.noInternet).thenReturn(false);

    final store =
        await pump(tester, _state([_news(1), _news(2)], offline: false));
    final bell = find.byKey(const Key('server-notification-bell'));
    expect(find.descendant(of: bell, matching: find.text('2')), findsOneWidget);

    await tester.tap(find.byType(EventBanner));
    await settleFor(tester, duration: const Duration(seconds: 1));

    expect(find.byType(SchoolNotificationDetailView), findsOneWidget);
    expect(store.state.notificationState.notifications!.map((n) => n.id), [1]);
    verify(() => mock.send('api/notification/markAsRead',
        args: <String, Object?>{'id': 2})).called(1);

    await tester.tap(find.byType(BackButton));
    await settleFor(tester, duration: const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await settleFor(tester, duration: const Duration(seconds: 1));
    expect(find.descendant(of: bell, matching: find.text('1')), findsOneWidget);
    await finish(tester);
  });
}
