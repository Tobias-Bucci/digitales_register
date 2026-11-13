import 'dart:async';
import 'dart:math' as math;

import 'package:dr/app_language_controller.dart';
import 'package:dr/i18n/app_language.dart';
import 'package:dr/server_notifications/server_notification_api.dart';
import 'package:dr/server_notifications/server_notification_config.dart';
import 'package:dr/server_notifications/server_notification_poller.dart';
import 'package:dr/server_notifications/server_notification_repository.dart';
import 'package:dr/server_notifications/server_notification_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// A generator stuck at one value, so that jitter can be pinned down.
class FixedRandom implements math.Random {
  FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

const transient =
    ServerNotificationFailure(ServerNotificationFailureKind.transient);

class Harness {
  Harness(this.async, {double random = 1});

  final FakeAsync async;
  int calls = 0;
  final List<FutureOr<int?> Function()> script = [];
  FutureOr<int?> Function()? always;
  final List<Object> reported = [];
  late final ServerNotificationPoller poller = ServerNotificationPoller(
    fetch: () async {
      calls++;
      if (script.isNotEmpty) return script.removeAt(0)();
      return always == null ? 300 : always!();
    },
    now: () => DateTime.utc(2026).add(async.elapsed),
    random: FixedRandom(1),
    onUnexpectedError: (error, _) => reported.add(error),
  );

  void wait(Duration duration) => async.elapse(duration);
}

void run(void Function(FakeAsync async, Harness harness) body) {
  fakeAsync((async) {
    final harness = Harness(async);
    body(async, harness);
    harness.poller.stop();
    async.flushMicrotasks();
  });
}

void main() {
  group('polling lifecycle', () {
    test('fetches at start and then every interval', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 299));
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 1));
        expect(h.calls, 2);
        h.wait(const Duration(seconds: 300));
        expect(h.calls, 3);
      });
    });

    test('one poller: a second start changes nothing', () {
      run((async, h) {
        h.poller
          ..start()
          ..start()
          ..start();
        async.flushMicrotasks();
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 300));
        expect(h.calls, 2);
      });
    });

    test('calls never overlap', () {
      run((async, h) {
        final slow = Completer<int?>();
        h.script.add(() => slow.future);
        h.poller.start();
        async.flushMicrotasks();
        h.poller
          ..refresh()
          ..refresh()
          ..setActive(false)
          ..setActive(true);
        h.wait(const Duration(hours: 2));
        expect(h.calls, 1, reason: 'still in flight');
        slow.complete(300);
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 300));
        expect(h.calls, 2);
      });
    });

    test('nothing runs in the background', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        h.poller.setActive(false);
        expect(h.poller.hasTimer, isFalse);
        h.wait(const Duration(hours: 5));
        expect(h.calls, 1);
      });
    });

    test('a fetch that ends in the background schedules nothing', () {
      run((async, h) {
        final slow = Completer<int?>();
        h.script.add(() => slow.future);
        h.poller.start();
        async.flushMicrotasks();
        h.poller.setActive(false);
        slow.complete(300);
        async.flushMicrotasks();
        expect(h.poller.hasTimer, isFalse);
      });
    });

    test('resume refreshes stale data at once', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        h.poller.setActive(false);
        h.wait(const Duration(minutes: 2));
        h.poller.setActive(true);
        async.flushMicrotasks();
        expect(h.calls, 2);
      });
    });

    test('resume within the freshness window fetches nothing extra', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 20));
        h.poller
          ..setActive(false)
          ..setActive(true);
        async.flushMicrotasks();
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 279));
        expect(h.calls, 1, reason: 'the regular interval still counts');
        h.wait(const Duration(seconds: 1));
        expect(h.calls, 2);
      });
    });

    test('quick switching between apps cannot cause a storm', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        for (var i = 0; i < 50; i++) {
          h.poller.setActive(false);
          h.wait(const Duration(seconds: 1));
          h.poller.setActive(true);
          h.wait(const Duration(seconds: 1));
        }
        expect(h.calls, lessThanOrEqualTo(3));
      });
    });

    test('starting hidden waits for the foreground', () {
      run((async, h) {
        h.poller
          ..setActive(false)
          ..start();
        async.flushMicrotasks();
        expect(h.calls, 0);
        h.poller.setActive(true);
        async.flushMicrotasks();
        expect(h.calls, 1);
      });
    });

    test('stop cleans up the timer', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        expect(async.pendingTimers, isNotEmpty);
        h.poller.stop();
        expect(h.poller.hasTimer, isFalse);
        h.wait(const Duration(hours: 1));
        expect(h.calls, 1);
      });
    });

    test('a manual refresh has a minimum distance', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        h.poller.refresh();
        async.flushMicrotasks();
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 16));
        h.poller.refresh();
        async.flushMicrotasks();
        expect(h.calls, 2);
      });
    });

    test('a manual refresh completes with its fetch', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 16));
        final answer = Completer<int?>();
        h.script.add(() => answer.future);
        var done = false;
        unawaited(h.poller.refresh().then((_) => done = true));
        async.flushMicrotasks();
        expect(h.calls, 2);
        expect(done, isFalse, reason: 'the fetch is still running');
        answer.complete(300);
        async.flushMicrotasks();
        expect(done, isTrue);
      });
    });

    test('a refresh that may not fetch completes at once', () {
      run((async, h) {
        h.poller.start();
        async.flushMicrotasks();
        var done = false;
        unawaited(h.poller.refresh().then((_) => done = true));
        async.flushMicrotasks();
        expect(h.calls, 1, reason: 'within the minimum distance');
        expect(done, isTrue);
      });
    });

    test('a changed selection fetches at once, or right after a running one',
        () {
      run((async, h) {
        final slow = Completer<int?>();
        h.script.add(() => slow.future);
        h.poller.start();
        async.flushMicrotasks();
        h.poller.selectionChanged();
        slow.complete(300);
        async.flushMicrotasks();
        expect(h.calls, 2);
        h.poller.selectionChanged();
        async.flushMicrotasks();
        expect(h.calls, 3);
      });
    });
  });

  group('interval handling', () {
    test('uses the server suggestion, including its jitter', () {
      run((async, h) {
        h.script.add(() => 303);
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 302));
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 1));
        expect(h.calls, 2);
      });
    });

    test('a too eager server cannot speed the client up', () {
      run((async, h) {
        h.always = () => 1;
        h.poller.start();
        async.flushMicrotasks();
        expect(h.poller.interval, const Duration(seconds: 60));
        h.wait(const Duration(minutes: 10));
        expect(h.calls, 11);
      });
    });

    test('a too slow server cannot silence the client', () {
      run((async, h) {
        h.always = () => 1 << 30;
        h.poller.start();
        async.flushMicrotasks();
        expect(h.poller.interval, const Duration(hours: 1));
      });
    });

    test('304 keeps the current interval', () {
      run((async, h) {
        h.script
          ..add(() => 120)
          ..add(() => null);
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 120));
        expect(h.calls, 2);
        expect(h.poller.interval, const Duration(seconds: 120));
      });
    });

    test('the default is five minutes', () {
      expect(const ServerNotificationPollPolicy().defaultInterval,
          const Duration(minutes: 5));
    });
  });

  group('backoff', () {
    test('grows exponentially, with jitter, up to a limit', () {
      const policy = ServerNotificationPollPolicy();
      expect(policy.backoff(1, 1), const Duration(seconds: 30));
      expect(policy.backoff(2, 1), const Duration(seconds: 60));
      expect(policy.backoff(3, 1), const Duration(seconds: 120));
      expect(policy.backoff(1, 0), const Duration(seconds: 15));
      expect(policy.backoff(40, 1), const Duration(minutes: 30));
      expect(policy.backoff(40, 0), const Duration(minutes: 15));
    });

    test('retries transient failures, and success resets', () {
      run((async, h) {
        h.script
          ..add(() => throw transient)
          ..add(() => throw transient)
          ..add(() => 300);
        h.poller.start();
        async.flushMicrotasks();
        expect(h.poller.failures, 1);
        h.wait(const Duration(seconds: 30));
        expect(h.calls, 2);
        h.wait(const Duration(seconds: 59));
        expect(h.calls, 2);
        h.wait(const Duration(seconds: 1));
        expect(h.calls, 3);
        expect(h.poller.failures, 0);
        h.wait(const Duration(seconds: 300));
        expect(h.calls, 4);
      });
    });

    test('a server that stays down gets few requests', () {
      run((async, h) {
        h.always = () => throw transient;
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(hours: 2));
        expect(h.calls, lessThan(10));
      });
    });

    test('backoff also holds for resume and manual refresh', () {
      run((async, h) {
        h.script.add(() => throw transient);
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 5));
        h.poller
          ..refresh()
          ..setActive(false)
          ..setActive(true)
          ..selectionChanged();
        async.flushMicrotasks();
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 25));
        expect(h.calls, 2);
      });
    });

    test('unknown errors are survived like transient ones', () {
      run((async, h) {
        h.script.add(() => throw StateError('bug'));
        h.poller.start();
        async.flushMicrotasks();
        expect(h.poller.failures, 1);
        expect(h.poller.hasTimer, isTrue);
        expect(h.reported, [isA<StateError>()], reason: 'a bug is reported');
      });
    });

    test('expected failures are not reported', () {
      run((async, h) {
        h.script
          ..add(() => throw transient)
          ..add(() => throw const ServerNotificationFailure(
              ServerNotificationFailureKind.permanent,
              status: 400));
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(minutes: 1));
        expect(h.calls, 2);
        expect(h.reported, isEmpty);
      });
    });

    test('a permanent failure waits an hour', () {
      run((async, h) {
        h.script.add(() => throw const ServerNotificationFailure(
            ServerNotificationFailureKind.permanent));
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(minutes: 59));
        expect(h.calls, 1);
        h.wait(const Duration(minutes: 1));
        expect(h.calls, 2);
      });
    });
  });

  group('429 and Retry-After', () {
    ServerNotificationFailure limited(int seconds) => ServerNotificationFailure(
          ServerNotificationFailureKind.rateLimited,
          retryAfter: Duration(seconds: seconds),
          status: 429,
        );

    test('waits at least Retry-After, plus a spread', () {
      run((async, h) {
        h.script.add(() => throw limited(600));
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 600));
        expect(h.calls, 1);
        h.wait(const Duration(seconds: 60));
        expect(h.calls, 2);
      });
    });

    test('resume and refresh cannot jump the queue', () {
      run((async, h) {
        h.script.add(() => throw limited(600));
        h.poller.start();
        async.flushMicrotasks();
        h.poller.setActive(false);
        h.wait(const Duration(seconds: 300));
        h.poller
          ..setActive(true)
          ..refresh();
        async.flushMicrotasks();
        expect(h.calls, 1);
      });
    });

    test('a short Retry-After does not shorten the backoff', () {
      run((async, h) {
        h.script.add(() => throw limited(1));
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(seconds: 29));
        expect(h.calls, 1);
      });
    });

    test('an absurd Retry-After is bounded', () {
      run((async, h) {
        h.script.add(() => throw limited(1 << 30));
        h.poller.start();
        async.flushMicrotasks();
        h.wait(const Duration(hours: 26));
        expect(h.calls, 1, reason: '24 hours, plus up to 10 %');
        h.wait(const Duration(minutes: 25));
        expect(h.calls, 2);
      });
    });
  });

  group('service', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    ServerNotificationService service(
      FakeServer server, {
      String? platform = 'android',
      String version = '1.17.4+55',
      bool enabled = true,
    }) =>
        ServerNotificationService(
          repository: ServerNotificationRepository(storage: FakeStorage()),
          baseUri: baseUri,
          platform: platform,
          enabledByBuild: enabled,
          appVersion: () async => version,
          client: server.client,
        );

    test('a build without the feature does nothing', () async {
      final server = FakeServer();
      final subject = service(server, enabled: false);
      await subject.start();
      expect(subject.enabled, isFalse);
      expect(server.requests, isEmpty);
    });

    test('a failure while starting is reported and leaves the app as it is',
        () async {
      final server = FakeServer();
      final reported = <Object>[];
      final subject = ServerNotificationService(
        repository: ServerNotificationRepository(storage: FakeStorage()),
        baseUri: baseUri,
        platform: 'android',
        enabledByBuild: true,
        appVersion: () async => throw StateError('no package info'),
        client: server.client,
      )..onUnexpectedError = (error, _) => reported.add(error);
      await subject.start();
      expect(reported, [isA<StateError>()]);
      expect(subject.poller.hasTimer, isFalse);
      expect(server.requests, isEmpty);
    });

    test('a bug during a fetch reaches the service hook', () async {
      final reported = <Object>[];
      final subject = ServerNotificationService(
        repository: _ThrowingRepository(),
        baseUri: baseUri,
        platform: 'android',
        enabledByBuild: true,
        appVersion: () async => '2.0.0',
      )..onUnexpectedError = (error, _) => reported.add(error);
      await subject.start();
      await pumpEventQueue();
      expect(reported, [isA<StateError>()]);
      subject.dispose();
    });

    test('a version the server would refuse fetches nothing', () async {
      final server = FakeServer();
      final subject = service(server, version: 'unknown');
      await subject.start();
      expect(subject.poller.hasTimer, isFalse);
      expect(server.requests, isEmpty);
    });

    test('inactive keeps polling, hidden and paused do not', () async {
      final server = FakeServer()..replyList([]);
      final subject = service(server);
      await subject.start();
      await pumpEventQueue();
      expect(server.requests, hasLength(1));
      expect(subject.poller.hasTimer, isTrue);

      // A desktop window without focus is still visible.
      subject.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(subject.poller.hasTimer, isTrue);

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        subject.didChangeAppLifecycleState(AppLifecycleState.resumed);
        expect(subject.poller.hasTimer, isTrue, reason: 'back: $state');
        subject.didChangeAppLifecycleState(state);
        expect(subject.poller.hasTimer, isFalse, reason: '$state');
      }
      subject.poller.stop();
    });

    test('fetches without any consent and sends the version bare', () async {
      final server = FakeServer()..replyList([]);
      final subject = service(server);
      await subject.start();
      // The poller's first fetch runs on its own.
      await pumpEventQueue();
      expect(server.requests, hasLength(1));
      expect(
          server.requests.single.url.queryParameters['app_version'], '1.17.4');
      subject.poller.stop();
    });

    test('a language change refetches with the new language', () async {
      final server = FakeServer()
        ..replyList([])
        ..replyList([]);
      final subject = service(server)..setLanguage('de');
      await subject.start();
      await pumpEventQueue();
      subject.setLanguage('it');
      await pumpEventQueue();
      expect(server.requests, hasLength(2));
      expect(server.requests.last.url.queryParameters['lang'], 'it');
      subject.poller.stop();
    });

    group('language (#120)', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        await appLanguageController.setLanguage(AppLanguage.it);
      });
      tearDown(() => appLanguageController.setLanguage(AppLanguage.de));

      test('without the popup host, the app language is sent', () async {
        final server = FakeServer()..replyList([]);
        final subject = service(server);
        await subject.start();
        await pumpEventQueue();
        expect(server.requests.single.url.queryParameters['lang'], 'it');
        subject.poller.stop();
      });

      test('a host that reports late still gets its language fetched',
          () async {
        final server = FakeServer()
          ..replyList([])
          ..replyList([]);
        final subject = service(server);
        await subject.start();
        await pumpEventQueue();
        // The first report differs from what was fetched: fetch again.
        subject.setLanguage('en');
        await pumpEventQueue();
        expect(server.requests, hasLength(2));
        expect(server.requests.last.url.queryParameters['lang'], 'en');
        subject.poller.stop();
      });

      test('a report of the language already fetched fetches nothing',
          () async {
        final server = FakeServer()..replyList([]);
        final subject = service(server);
        await subject.start();
        await pumpEventQueue();
        subject.setLanguage('it');
        await pumpEventQueue();
        expect(server.requests, hasLength(1));
        subject.poller.stop();
      });

      test(
          'Ladin asks for German, and switching between them refetches '
          'nothing', () async {
        final server = FakeServer()
          ..replyList([])
          ..replyList([]);
        final subject = service(server)..setLanguage('lld');
        await subject.start();
        await pumpEventQueue();
        expect(server.requests.single.url.queryParameters['lang'], 'de');
        subject.setLanguage('de');
        await pumpEventQueue();
        expect(server.requests, hasLength(1));
        subject.setLanguage('it');
        await pumpEventQueue();
        expect(server.requests.last.url.queryParameters['lang'], 'it');
        subject.poller.stop();
      });

      test('the mapping of every app language', () {
        expect(
          {
            for (final language in AppLanguage.values)
              language.code: serverNotificationLanguage(language.code),
          },
          {'de': 'de', 'it': 'it', 'lld': 'de', 'en': 'en'},
        );
      });
    });
  });
}

class _ThrowingRepository extends ServerNotificationRepository {
  _ThrowingRepository() : super(storage: FakeStorage());

  @override
  Future<int?> sync(ServerNotificationSelection selection) async =>
      throw StateError('bug');
}
