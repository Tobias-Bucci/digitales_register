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

import 'dart:convert';
import 'dart:io';

import 'package:built_redux/built_redux.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/login_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/study_data_migration.dart';
import 'package:dr/study_data_service.dart';
import 'package:dr/ui/legacy_study_data_tile.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

const _school = 'https://a.school.example';

class _AccountWrapper extends MockWrapper {
  _AccountWrapper(this.url, this.user, {this.demoMode = false});

  @override
  String? url;
  @override
  String? user;
  @override
  bool demoMode;
  @override
  bool safeMode = false;
  @override
  bool noInternet = false;

  @override
  String get loginAddress => '$url/v2/api/auth/login';
  @override
  String get baseAddress => '$url/v2/';
  @override
  void logout({required bool hard, bool logoutForcedByServer = false}) {}
}

void main() {
  late Directory root;
  late File legacyFile;

  late StudyData legacy;

  setUp(() async {
    await bootstrapTestEnvironment();
    root = await Directory.systemTemp.createTemp('study-flow-');
    assessmentAttachmentsRootOverride = () async => root;
    legacyFile = File('${root.path}/111_a.pdf')..writeAsStringSync('pdf');
    legacy = StudyData(
      notes: const {'assessment-7': 'private old note'},
      progress: const {'assessment-7': 'a'},
      attachments: {
        'assessment-7': encodeAssessmentAttachments([
          AssessmentAttachment(name: 'secret-name.pdf', path: legacyFile.path)
        ])
      },
    );
    SharedPreferences.setMockInitialValues({
      'tutorial.v3.seen': true,
      globalSettingsPreferenceKey: jsonEncode(serializers.serialize(
          legacy.applyTo(SettingsState((b) => b..languageCode = 'en')))),
    });
  });

  tearDown(() async {
    assessmentAttachmentsRootOverride = null;
    await root.delete(recursive: true);
    await resetTestState();
  });

  Store<AppState, AppStateBuilder, AppActions> newStore() {
    final store = createStore(
      withMiddleware: true,
      initialState: AppState((b) => b.settingsState.languageCode = 'en'),
    );
    addTearDown(store.dispose);
    return store;
  }

  Future<void> signIn(
    WidgetTester tester,
    Store<AppState, AppStateBuilder, AppActions> store,
    String user, {
    bool demo = false,
  }) async {
    await tester.runAsync(() async {
      wrapper = _AccountWrapper(demo ? '' : _school, user, demoMode: demo);
      await store.actions.setUrl(demo ? '' : _school);
      await store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
        ..username = user
        ..fromStorage = true
        ..offlineOnly = true));
    });
    // The question is asked once the first frame is out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> signOut(
    WidgetTester tester,
    Store<AppState, AppStateBuilder, AppActions> store,
  ) async {
    await tester
        .runAsync(() => store.actions.loginActions.logout(LogoutPayload((b) => b
          ..hard = true
          ..forced = false)));
    await tester.pump();
  }

  Future<void> start(
    WidgetTester tester,
    Store<AppState, AppStateBuilder, AppActions> store,
  ) =>
      pumpApp(
        tester,
        store: store,
        home: const Scaffold(body: SizedBox()),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('login')),
        ),
      );

  String? raw(String key) => (secureStorage as TestSecureStorage).storage[key];

  /// Real file operations only finish on the real event loop and their
  /// continuations only run on a pump, so it takes turns until [until] holds.
  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      if (until != null && until()) break;
      if (until == null && i >= 11) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the first sign-in puts the old notes aside and asks once',
      (tester) async {
    final store = newStore();
    await start(tester, store);

    await signIn(tester, store, 'max');

    // Nobody got the notes; they wait in the quarantine, unchanged.
    expect(store.state.settingsState.hasStudyData, isFalse);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    expect(raw(studyDataMigrationMarkerKey), 'quarantined');
    expect(find.text('Older study notes without an account'), findsOneWidget);
    // Numbers only: neither the note nor the file name is shown.
    expect(find.textContaining('1 exam (1 note, 1 file)'), findsOneWidget);
    expect(find.textContaining('private old note'), findsNothing);
    expect(find.textContaining('secret-name'), findsNothing);

    // "Later" is the default: nothing happens to the notes.
    await tester.tap(find.text('Later'));
    await settle(tester);
    expect(find.text('Older study notes without an account'), findsNothing);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    expect(store.state.settingsState.hasStudyData, isFalse);

    // The next sign-in does not ask again, in this or another account.
    await signOut(tester, store);
    await signIn(tester, store, 'anna');
    expect(find.text('Older study notes without an account'), findsNothing);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
  });

  testWidgets('closing the question keeps the notes', (tester) async {
    final store = newStore();
    await start(tester, store);
    await signIn(tester, store, 'max');

    // Tapping outside the dialog.
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);

    expect(find.text('Older study notes without an account'), findsNothing);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
  });

  testWidgets('assigning from the question dispatches the assignment',
      (tester) async {
    final store = newStore();
    final dispatched = _recordActions(store);
    await start(tester, store);
    await signIn(tester, store, 'max');

    await tester.tap(find.text('Assign to this account'));
    await settle(tester);

    expect(dispatched, ['AppActions-assignLegacyStudyData']);
    expect(find.text('Older study notes without an account'), findsNothing);
  });

  testWidgets('discarding needs a second confirmation', (tester) async {
    final store = newStore();
    final dispatched = _recordActions(store);
    await start(tester, store);
    await signIn(tester, store, 'max');

    await tester.tap(find.text('Discard …'));
    await settle(tester);
    expect(find.text('Delete older study notes for good?'), findsOneWidget);
    // The second question names numbers only, too.
    expect(find.textContaining('(1 note, 1 file)'), findsOneWidget);
    expect(find.textContaining('private old note'), findsNothing);
    // Backing out keeps everything and discards nothing.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(dispatched, isEmpty);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    expect(legacyFile.existsSync(), isTrue);

    // Closing the second question by tapping outside is backing out, too.
    final summary = (await tester.runAsync(studyDataMigration.summary))!;
    unawaitedShow(store, summary);
    await settle(tester);
    await tester.tap(find.text('Discard …'));
    await settle(tester);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    expect(dispatched, isEmpty);

    // Only the confirmation discards.
    unawaitedShow(store, summary);
    await settle(tester);
    await tester.tap(find.text('Discard …'));
    await settle(tester);
    await tester.tap(find.text('Delete for good'));
    await settle(tester);
    expect(dispatched, ['AppActions-discardLegacyStudyData']);
  });

  testWidgets('the settings show a line with numbers while notes are kept',
      (tester) async {
    final store = newStore();
    final dispatched = _recordActions(store);
    await tester.pumpWidget(buildTestApp(
      store: store,
      home: Scaffold(body: LegacyStudyDataTile(actions: store.actions)),
    ));
    await signIn(tester, store, 'max');
    await tester.tap(find.text('Later'));
    await settle(tester);

    expect(find.text('Older study notes without an account'), findsOneWidget);
    expect(
        find.text('1 exam (1 note, 1 file). Tap to assign or delete them.'),
        findsOneWidget);
    expect(find.textContaining('private old note'), findsNothing);

    await tester.tap(find.byType(LegacyStudyDataTile));
    await settle(tester);
    expect(find.text('Assign to this account'), findsOneWidget);
    await tester.tap(find.text('Assign to this account'));
    await settle(tester);
    expect(dispatched, ['AppActions-assignLegacyStudyData']);

    // The line follows the quarantine.
    await tester.runAsync(() => studyDataMigration.discard());
    legacyStudyDataRevision.value++;
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('the demo account is not asked and gets nothing', (tester) async {
    final store = newStore();
    await start(tester, store);

    await signIn(tester, store, 'demo', demo: true);

    expect(find.text('Older study notes without an account'), findsNothing);
    expect(store.state.settingsState.hasStudyData, isFalse);
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    // Assigning from the demo account is refused.
    await tester.runAsync(() => store.actions.assignLegacyStudyData());
    await tester.pump();
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    expect(raw(studyDataKeyFor(AccountScope.demo())), isNull);
  });

  testWidgets('an unreadable keystore keeps the notes and asks nothing yet',
      (tester) async {
    final storage = _FailingStorage();
    secureStorage = storage;
    final store = newStore();
    await start(tester, store);

    await signIn(tester, store, 'max');

    expect(find.text('Older study notes without an account'), findsNothing);
    expect(storage.storage, isEmpty);
    expect(
        await tester
            .runAsync(() => settingsPersistenceService.legacyStudyData()),
        legacy);

    // The next start finds the keystore again.
    storage.failing = false;
    await signOut(tester, store);
    await signIn(tester, store, 'max');
    expect(StudyData.decode(raw(studyDataLegacyKey)!), legacy);
    expect(find.text('Older study notes without an account'), findsOneWidget);
  });
}

/// Records the assignment and discarding that the question asks for, without
/// carrying them out.
List<String> _recordActions(
    Store<AppState, AppStateBuilder, AppActions> store) {
  final dispatched = <String>[];
  store.actions.assignLegacyStudyData.setDispatcher((action) async {
    dispatched.add(action.name);
  });
  store.actions.discardLegacyStudyData.setDispatcher((action) async {
    dispatched.add(action.name);
  });
  return dispatched;
}

void unawaitedShow(Store<AppState, AppStateBuilder, AppActions> store,
    LegacyStudySummary summary) {
  // ignore: discarded_futures
  showLegacyStudyDataDialog(store.actions, summary);
}

class _FailingStorage extends TestSecureStorage {
  bool failing = true;

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
    if (failing && key != 'login') throw StateError('keystore unavailable');
    return storage[key];
  }
}
