// Copyright (C) 2026 Tobias Bucci
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dio/dio.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

const _school = 'https://example.org';

/// A school session whose answers the test releases by hand, so a response can
/// arrive after the app has switched to another account.
class HoldingWrapper extends MockWrapper {
  HoldingWrapper(this.name) {
    user = name;
    pass = 'password-$name';
    url = _school;
  }

  final String name;
  @override
  String? user, pass, url;
  @override
  bool safeMode = false;
  @override
  bool noInternet = false;
  @override
  bool demoMode = false;
  @override
  void Function()? onLogout;

  final List<String> sent = <String>[];
  final Map<String, Completer<dynamic>> _pending = <String, Completer<dynamic>>{};
  final Set<String> _delivered = <String>{};

  int count(String path) => sent.where((p) => p == path).length;

  @override
  String get loginAddress => '$url/v2/api/auth/login';
  @override
  String get baseAddress => '$url/v2/';
  @override
  Future<bool> get loggedIn async => true;
  @override
  Config get config => Config((b) => b
    ..autoLogoutSeconds = 300
    ..currentSemesterMaybe = 1
    ..fullName = 'Test'
    ..imgSource = ''
    ..isStudentOrParent = true
    ..userId = 1);

  /// The next request to [path] waits until [release] or [fail].
  void hold(String path) => _pending[path] = Completer<dynamic>();

  void release(String path, dynamic response) =>
      _pending[path]!.complete(response);

  void fail(String path, Object error) =>
      _pending[path]!.completeError(error);

  @override
  Future<dynamic> send(String path,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) {
    sent.add(path);
    final held = _pending[path];
    if (held != null && _delivered.add(path)) return held.future;
    return Future<dynamic>.value(null);
  }

  @override
  void logout({required bool hard, bool logoutForcedByServer = false}) {
    if (hard) user = pass = url = null;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late HoldingWrapper first;

  setUp(() async {
    await bootstrapTestEnvironment();
    first = HoldingWrapper('a');
    wrapper = first;
    await secureStorage.write(
        key: 'login',
        value: jsonEncode({
          'otherAccounts': [
            {'user': 'b', 'pass': 'password-b', 'url': _school},
          ],
        }));
  });

  tearDown(resetTestState);

  Store<AppState, AppStateBuilder, AppActions> signedInStore() {
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'a'
        ..url = _school),
    );
    addTearDown(store.dispose);
    return store;
  }

  Future<void> switchAccount(Store<AppState, AppStateBuilder, AppActions> s) =>
      s.actions.loginActions.addAccount();

  test('a late profile response cannot fill the next account', () async {
    final store = signedInStore();
    first.hold('api/profile/get');
    final load = store.actions.profileActions.load();
    await settle();
    expect(first.count('api/profile/get'), 1);

    await switchAccount(store);
    first.release('api/profile/get', {'name': 'Alice A'});
    await load;
    await settle();

    expect(store.state.profileState.name, isNull);
  });

  test('a late certificate response cannot fill the next account', () async {
    final store = signedInStore();
    first.hold('student/certificate');
    final load = store.actions.certificateActions.load();
    await settle();

    await switchAccount(store);
    first.release('student/certificate', '<p>certificate of a</p>');
    await load;
    await settle();

    expect(store.state.certificateState.html, isNull);
  });

  test('a late message list cannot fill the next account', () async {
    final store = signedInStore();
    first.hold('api/message/getMyMessages');
    final load = store.actions.messagesActions.load();
    await settle();

    await switchAccount(store);
    first.release('api/message/getMyMessages', <dynamic>[]);
    await load;
    await settle();

    expect(store.state.messagesState.lastFetched, isNull);
  });

  test('a late dashboard response does not make the next account look fresh',
      () async {
    final store = signedInStore();
    const path = 'api/student/dashboard/dashboard';
    first.hold(path);
    final load = store.actions.dashboardActions.load(false);
    await settle();
    expect(first.count(path), 1);

    await switchAccount(store);
    first.release(path, <dynamic>[]);
    await load;
    await settle();
    // The new account's own load must still go out.
    await store.actions.dashboardActions.load(false);
    await settle();

    expect(first.count(path), 2);
  });

  test('a late absences failure is not reported as the next account\'s',
      () async {
    final store = signedInStore();
    const path = 'api/student/dashboard/absences';
    first.hold(path);
    final load = store.actions.absencesActions.load();
    await settle();

    await switchAccount(store);
    first.fail(path, StateError('connection lost'));
    await load;
    await settle();

    expect(store.state.absencesState.loadFailed, isFalse);
  });

  test('a late homework page is neither cached nor stored for the next account',
      () async {
    final store = signedInStore();
    // The request path carries a timestamp: answer whatever arrives first.
    final prefs = await SharedPreferences.getInstance();
    final completer = Completer<dynamic>();
    final wrapperWithAnyPath = _AnyPathWrapper('a', completer.future);
    wrapper = wrapperWithAnyPath;
    final refresh = refreshHomeworkSummaryHtmlPayload();
    await settle();

    await switchAccount(store);
    wrapper = HoldingWrapper('b');
    completer.complete('<html>homework of a</html>');
    final result = await refresh;
    await settle();

    expect(result, isNull);
    expect(
      prefs.getKeys().where((key) => key.startsWith('homeworkSummary:')),
      isEmpty,
    );
  });

  test('the same account signing in again does not revive old work',
      () async {
    final store = signedInStore();
    first.hold('api/profile/get');
    final load = store.actions.profileActions.load();
    await settle();

    // A -> B -> A: the wrapper object and the account are the same again.
    await switchAccount(store);
    await switchAccount(store);
    first.user = 'a';
    first.url = _school;
    first.release('api/profile/get', {'name': 'Alice A'});
    await load;
    await settle();

    expect(store.state.profileState.name, isNull);
  });

  test('an account switch during a mutation sends nothing for the new account',
      () async {
    final store = signedInStore();
    first.hold('api/student/dashboard/save_reminder');
    final add = store.actions.dashboardActions.addReminder(
      AddReminderPayload((b) => b
        ..date = UtcDateTime(2026, 11, 1)
        ..msg = 'private reminder of a'),
    );
    await settle();

    await switchAccount(store);
    first.release('api/student/dashboard/save_reminder', {'id': 1});
    await add;
    await settle();

    expect(first.count('api/student/dashboard/save_reminder'), 1);
    expect(store.state.dashboardState.allDays, isNull);
  });

  group('downloads', () {
    const pdf = [37, 80, 68, 70, 45, 49];
    late Directory directory;
    late _DownloadingWrapper a;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('session-download-');
      attachmentDownloadDirectoryOverride = () async => directory.path;
      a = _DownloadingWrapper('a');
      wrapper = a;
    });

    tearDown(() async {
      attachmentDownloadDirectoryOverride = null;
      courseMaterialFileOpenerOverride = null;
      courseMaterialPlatformOverride = null;
      await directory.delete(recursive: true);
    });

    /// Everything the download wrote, whichever folder it went to.
    List<String> written() => directory
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .toList();

    test('a file download of a left account is not saved', () async {
      final store = signedInStore();
      final download = downloadFile('$_school/file', 'a.pdf', const {})
          .then<Object?>((value) => value, onError: (Object e) => e);
      await a.waitForRequest();

      await switchAccount(store);
      a.answer.complete(pdf);

      expect(await download, isA<StaleSessionException>());
      expect(written(), isEmpty);
    });

    test('a file download retries on its own session, not the next account\'s',
        () async {
      final store = signedInStore();
      final download = downloadFile('$_school/file', 'a.pdf', const {})
          .then<Object?>((value) => value, onError: (Object e) => e);
      await a.waitForRequest();

      // The login page makes the download sign in again and ask once more.
      final b = _DownloadingWrapper('b');
      await switchAccount(store);
      wrapper = b;
      b.answer.complete(pdf);
      a.contentType = 'text/html';
      a.answer.complete(utf8.encode(
          '<!DOCTYPE html><html><head><title>Login</title></head>'
          '<body><form></form></body></html>'));
      await download;

      expect(b.requests, isEmpty);
      expect(written(), isEmpty);
    });

    test('authenticated bytes of a left account are not handed on', () async {
      final store = signedInStore();
      final bytes = fetchAuthenticatedBytes('$_school/avatar.png')
          .then<Object?>((value) => value, onError: (Object e) => e);
      await a.waitForRequest();

      await switchAccount(store);
      a.answer.complete(pdf);

      expect(await bytes, isA<StaleSessionException>());
    });

    test('a course document of a left account is neither saved nor opened',
        () async {
      final store = signedInStore();
      courseMaterialPlatformOverride = TargetPlatform.windows;
      var opened = 0;
      courseMaterialFileOpenerOverride = (_) async {
        opened++;
        return OpenResult(type: ResultType.done, message: 'done');
      };
      final entry = CourseMaterialEntry.fromJson({
        'id': 657,
        'courseContentId': 83,
        'type': 'file',
        'file': 'server.pdf',
        'originalName': 'Blatt.pdf',
        'lastmodified': '2026-10-01 08:00:00',
      });
      final open = openCourseMaterialEntryWithStatus(entry);
      await a.waitForRequest();

      await switchAccount(store);
      a.answer.complete(pdf);

      // Not a failure the next account would be told about.
      expect(await open, CourseMaterialOpenResult.abandoned);
      expect(opened, 0);
      expect(written(), isEmpty);
    });
  });

  test('a queued semester switch of a left account is not sent to the next',
      () async {
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'a'
        ..url = _school
        ..config.replace(first.config)),
    );
    addTearDown(store.dispose);
    first.hold('api/student/all_subjects');
    // The first semester runs and holds the lock; the second has to wait.
    final running = store.actions.gradesActions.load(Semester.first);
    await settle();
    expect(first.count('?semesterWechsel=1'), 1);
    final queued = store.actions.gradesActions.load(Semester.second);
    await settle();

    final next = HoldingWrapper('b');
    wrapper = next;
    first.release('api/student/all_subjects', <dynamic>[]);
    await running;
    await queued;
    await settle();

    expect(next.sent, isEmpty);
    expect(first.count('?semesterWechsel=2'), 0);
  });

  test('a switch while signing in does not mount the saved state', () async {
    final key = escapeKey(getStorageKey('a', first.loginAddress));
    final storage = _HoldingStorage(key)
      ..storage[key] = json.encode(serializers.serialize(AppState(
          (b) => b.settingsState.languageCode = 'lld')));
    secureStorage = storage;
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b..url = _school),
    );
    addTearDown(store.dispose);
    final signIn = store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
      ..username = 'a'
      ..fromStorage = true
      ..offlineOnly = true));
    await storage.reading.future;

    // The user picks another account before the saved state is read.
    wrapper = HoldingWrapper('b');
    storage.release.complete();
    await signIn;
    await settle();

    expect(store.state.settingsState.languageCode, isNot('lld'));
  });

  testWidgets('a response of a left account never shows up as an error',
      (tester) async {
    // With the real error middleware, which would push an error page.
    final store = Store<AppState, AppStateBuilder, AppActions>(
      appReducerBuilder.build(),
      AppState((b) => b
        ..loginState.loggedIn = true
        ..loginState.username = 'a'
        ..url = _school),
      AppActions(),
      middleware: middleware(),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const Scaffold(body: Text('home')),
    ));
    final failures = <String>[];
    await tester.runAsync(() async {
      first.hold('api/profile/get');
      final run = store.actions.profileActions.load();
      await settle();
      // Switching through the store would open the startup dialogs here.
      wrapper = HoldingWrapper('b');
      first.fail('api/profile/get', StateError('late failure'));
      try {
        await run;
      } catch (e) {
        failures.add('$e');
      }
      await settle();
    });
    await tester.pump();

    expect(failures, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(navigatorKey!.currentState!.canPop(), isFalse);
  });
}

/// Answers the first request, whatever its path, with [answer].
class _AnyPathWrapper extends HoldingWrapper {
  _AnyPathWrapper(super.name, this.answer);

  final Future<dynamic> answer;

  @override
  Future<dynamic> send(String path,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) {
    sent.add(path);
    return answer;
  }
}

/// A session whose HTTP answers the test releases by hand.
class _DownloadingWrapper extends HoldingWrapper {
  _DownloadingWrapper(super.name) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      requests.add(options.uri.toString());
      if (!_requested.isCompleted) _requested.complete();
      final bytes = await answer.future;
      handler.resolve(Response<List<int>>(
        requestOptions: options,
        statusCode: 200,
        data: bytes,
        headers: Headers.fromMap({
          'content-type': [contentType]
        }),
      ));
    }));
  }

  final Dio _dio = Dio();
  final Completer<List<int>> answer = Completer<List<int>>();
  final Completer<void> _requested = Completer<void>();
  final List<String> requests = <String>[];
  String contentType = 'application/pdf';

  Future<void> waitForRequest() =>
      _requested.future.timeout(const Duration(seconds: 5));

  @override
  Dio get dio => _dio;

  @override
  Future<bool> ensureLoggedIn({
    bool isRetryAfterUnexpectedLogout = false,
    bool forceRelogin = false,
  }) async =>
      true;
}

/// Secure storage whose read of [heldKey] waits for the test.
class _HoldingStorage extends TestSecureStorage {
  _HoldingStorage(this.heldKey);

  final String heldKey;
  final Completer<void> reading = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (key == heldKey) {
      reading.complete();
      await release.future;
    }
    return storage[key];
  }
}
