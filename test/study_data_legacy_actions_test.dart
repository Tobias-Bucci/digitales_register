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
import 'package:dr/wrapper.dart';
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
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() async {
    await bootstrapTestEnvironment();
    root = await Directory.systemTemp.createTemp('study-actions-');
    assessmentAttachmentsRootOverride = () async => root;
    legacyFile = File('${root.path}/111_a.pdf')..writeAsStringSync('pdf');
    final legacy = StudyData(
      notes: const {
        'assessment-7': 'old note 7',
        'assessment-9': 'old note 9',
      },
      attachments: {
        'assessment-7': encodeAssessmentAttachments(
            [AssessmentAttachment(name: 'a.pdf', path: legacyFile.path)])
      },
    );
    SharedPreferences.setMockInitialValues({
      'tutorial.v3.seen': true,
      globalSettingsPreferenceKey: jsonEncode(serializers.serialize(
          legacy.applyTo(SettingsState((b) => b..languageCode = 'en')))),
    });
    store = createStore(withMiddleware: true);
    addTearDown(store.dispose);
  });

  tearDown(() async {
    assessmentAttachmentsRootOverride = null;
    await root.delete(recursive: true);
    await resetTestState();
  });

  Future<void> signIn(String user, {bool demo = false}) async {
    wrapper = _AccountWrapper(demo ? '' : _school, user, demoMode: demo);
    await store.actions.setUrl(demo ? '' : _school);
    await store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
      ..username = user
      ..fromStorage = true
      ..offlineOnly = true));
  }

  Future<void> signOut() =>
      store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = false));

  String? raw(String key) => (secureStorage as TestSecureStorage).storage[key];

  Future<StudyData> saved(String user) =>
      studyDataService.load(AccountScope(_school, user));

  SettingsState settings() => store.state.settingsState;

  group('assigning', () {
    test('gives the signed-in account the notes and files', () async {
      await signIn('max');

      await store.actions.assignLegacyStudyData();

      expect(settings().assessmentStudyNotes.toMap(),
          {'assessment-7': 'old note 7', 'assessment-9': 'old note 9'});
      final doc = await saved('max');
      expect(doc.notes, settings().assessmentStudyNotes.toMap());
      final file =
          decodeAssessmentAttachments(doc.attachments['assessment-7']).single;
      final resolved = await resolveAssessmentAttachmentFile(
          file, AccountScope(_school, 'max'));
      expect(resolved!.readAsStringSync(), 'pdf');
      expect(legacyFile.existsSync(), isFalse);
      expect(raw(studyDataLegacyKey), isNull);
      expect(raw(studyDataMigrationMarkerKey), 'done');
    });

    test('is not shown to the next account', () async {
      await signIn('max');
      await store.actions.assignLegacyStudyData();
      await signOut();

      await signIn('anna');

      expect(settings().hasStudyData, isFalse);
      expect((await saved('anna')).isEmpty, isTrue);
    });

    test('keeps what the account has typed, and what is typed afterwards',
        () async {
      await signIn('max');
      await store.actions.settingsActions.setAssessmentStudyNote(
          const MapEntry('assessment-7', 'typed by max'));

      await store.actions.assignLegacyStudyData();
      await store.actions.settingsActions.setAssessmentStudyNote(
          const MapEntry('assessment-1', 'typed later'));

      final doc = await saved('max');
      expect(doc.notes, {
        'assessment-7': 'typed by max',
        'assessment-9': 'old note 9',
        'assessment-1': 'typed later',
      });
      expect(settings().assessmentStudyNotes.toMap(), doc.notes);
      // The note it has an entry for stays in the quarantine, with its file.
      expect(StudyData.decode(raw(studyDataLegacyKey)!).notes,
          {'assessment-7': 'old note 7'});
    });

    test('is not undone by a save that waited behind it', () async {
      await signIn('max');
      final release = Completer<void>();
      final running = statePersistenceService.flush(
        state: store.state,
        deletedData: false,
        server: wrapper.loginAddress,
        writer: (key, value) => release.future,
        keyFactory: getStorageKey,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Both wait for the write that is still running, in this order.
      final assign = store.actions.assignLegacyStudyData();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final edit = store.actions.settingsActions.setAssessmentStudyNote(
          const MapEntry('assessment-1', 'typed meanwhile'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release.complete();
      await Future.wait([running, assign, edit]);

      final doc = await saved('max');
      expect(doc.notes, {
        'assessment-7': 'old note 7',
        'assessment-9': 'old note 9',
        'assessment-1': 'typed meanwhile',
      });
      expect(settings().assessmentStudyNotes.toMap(), doc.notes);
    });

    test('is refused for the demo account', () async {
      await signIn('demo', demo: true);

      await store.actions.assignLegacyStudyData();

      expect(settings().hasStudyData, isFalse);
      expect(raw(studyDataKeyFor(AccountScope.demo())), isNull);
      expect(StudyData.decode(raw(studyDataLegacyKey)!).notes, hasLength(2));
    });

    test('is refused while the notes of the account could not be read',
        () async {
      final key = studyDataKeyFor(AccountScope(_school, 'max'));
      final storage = _FailingStorage(key)..storage[key] = '{"version":1}';
      secureStorage = storage;
      await signIn('max');

      await store.actions.assignLegacyStudyData();

      expect(settings().hasStudyData, isFalse);
      expect(storage.storage[key], '{"version":1}');
      expect(StudyData.decode(raw(studyDataLegacyKey)!).notes, hasLength(2));
    });

    test('does not change anything when the keystore fails halfway', () async {
      final storage = _FailingWriteStorage();
      secureStorage = storage;
      await signIn('max');
      final before = Map.of(storage.storage);
      storage.failWrites = true;

      await store.actions.assignLegacyStudyData();

      expect(storage.storage, before);
      expect(settings().hasStudyData, isFalse);
      expect(legacyFile.existsSync(), isTrue);
    });

    test('moved files go with the account when it is removed', () async {
      await signIn('max');
      await store.actions.assignLegacyStudyData();
      final folder =
          await assessmentAttachmentFolder(AccountScope(_school, 'max'));
      expect(folder.listSync(), isNotEmpty);

      await store.actions.settingsActions.deleteDataOnLogout(true);
      await signOut();

      expect(folder.existsSync(), isFalse);
      expect((await saved('max')).isEmpty, isTrue);
    });
  });

  group('discarding', () {
    test('deletes the older notes and files and nothing else', () async {
      await signIn('max');
      await store.actions.settingsActions
          .setAssessmentStudyNote(const MapEntry('assessment-1', 'own note'));

      await store.actions.discardLegacyStudyData();

      expect(raw(studyDataLegacyKey), isNull);
      expect(raw(studyDataMigrationMarkerKey), 'done');
      expect(legacyFile.existsSync(), isFalse);
      expect((await saved('max')).notes, {'assessment-1': 'own note'});
      expect(settings().assessmentStudyNotes.toMap(),
          {'assessment-1': 'own note'});
      expect((await settingsPersistenceService.legacyStudyData())!.isEmpty,
          isTrue);
    });
  });

  test('older notes do not come back after the migration is done', () async {
    await signIn('max');
    await store.actions.discardLegacyStudyData();
    await signOut();
    // Something writes the shared settings again, with the notes of an
    // account in the store.
    await signIn('anna');
    await store.actions.settingsActions
        .setAssessmentStudyNote(const MapEntry('assessment-1', 'note of anna'));
    await store.actions.settingsActions.amoledMode(true);

    final shared = (await SharedPreferences.getInstance())
        .getString(globalSettingsPreferenceKey)!;
    expect(shared, isNot(contains('old note')));
    expect(shared, isNot(contains('note of anna')));
  });
}

class _FailingStorage extends TestSecureStorage {
  _FailingStorage(this.failingKey);

  final String failingKey;

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
    if (key == failingKey) throw StateError('keystore unavailable');
    return storage[key];
  }
}

class _FailingWriteStorage extends TestSecureStorage {
  bool failWrites = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    if (failWrites) throw StateError('keystore unavailable');
    storage[key] = value!;
  }
}
