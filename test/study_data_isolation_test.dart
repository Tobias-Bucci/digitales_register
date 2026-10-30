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

import 'package:built_collection/built_collection.dart';
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

const _schoolA = 'https://a.school.example';
const _schoolB = 'https://b.school.example';
const _exam = 'assessment-7';

/// A session of [user] at [url] that never talks to a server.
class _AccountWrapper extends MockWrapper {
  _AccountWrapper(this.url, this.user);

  @override
  String? url;
  @override
  String? user;
  @override
  bool demoMode = false;
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
  late Directory attachmentsRoot;
  late Store<AppState, AppStateBuilder, AppActions> store;

  setUp(() async {
    await bootstrapTestEnvironment();
    studyDataService.retryDelay = Duration.zero;
    attachmentsRoot = await Directory.systemTemp.createTemp('study-files-');
    assessmentAttachmentsRootOverride = () async => attachmentsRoot;
    store = createStore(withMiddleware: true);
    addTearDown(store.dispose);
  });

  tearDown(() async {
    assessmentAttachmentsRootOverride = null;
    await attachmentsRoot.delete(recursive: true);
    await resetTestState();
  });

  Future<void> signIn(String url, String user) async {
    wrapper = _AccountWrapper(url, user);
    await store.actions.setUrl(url);
    await store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
      ..username = user
      ..fromStorage = true
      ..offlineOnly = true));
  }

  Future<void> signOut() =>
      store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = false));

  Future<void> writeNotes(String note, {String exam = _exam}) async {
    await store.actions.settingsActions
        .setAssessmentStudyNote(MapEntry(exam, note));
    await store.actions.settingsActions
        .setAssessmentStudyProgress(MapEntry(exam, 'a,b'));
    await store.actions.settingsActions.setAssessmentStudyPhases(
        MapEntry(exam, '[{"id":"x","title":"Phase of $note"}]'));
    await store.actions.settingsActions.setAssessmentStudyAttachments(MapEntry(
        exam,
        encodeAssessmentAttachments([
          AssessmentAttachment(name: '$note.pdf', path: 'stored_$note.pdf')
        ])));
  }

  SettingsState settings() => store.state.settingsState;

  Future<StudyData> saved(String url, String user) =>
      studyDataService.load(AccountScope(url, user));

  group('learning notes belong to the account that wrote them', () {
    test('another user of the same school sees none of them', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();

      await signIn(_schoolA, 'anna');

      expect(settings().assessmentStudyNotes, isEmpty);
      expect(settings().assessmentStudyProgress, isEmpty);
      expect(settings().assessmentStudyAttachments, isEmpty);
      expect(settings().assessmentStudyPhases, isEmpty);
    });

    test('the same user name at another school sees none of them', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();

      await signIn(_schoolB, 'max');

      expect(settings().assessmentStudyNotes, isEmpty);
      expect(settings().assessmentStudyAttachments, isEmpty);
    });

    test('the owner finds them again, unchanged by the others', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();

      await signIn(_schoolA, 'anna');
      // The same exam id: another account's note must not be touched.
      await writeNotes('note of anna');
      await store.actions.settingsActions
          .setAssessmentStudyNote(const MapEntry(_exam, ''));
      await signOut();

      await signIn(_schoolA, 'max');

      expect(settings().assessmentStudyNotes[_exam], 'note of max');
      expect(settings().assessmentStudyProgress[_exam], 'a,b');
      expect(settings().assessmentStudyPhases[_exam],
          contains('Phase of note of max'));
      expect(
          decodeAssessmentAttachments(
                  settings().assessmentStudyAttachments[_exam])
              .single
              .name,
          'note of max.pdf');
      final anna = await saved(_schoolA, 'anna');
      expect(anna.notes, isEmpty);
      expect(anna.progress[_exam], 'a,b');
    });

    test('each account has a document of its own', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();
      await signIn(_schoolB, 'max');
      await writeNotes('note at b');

      final keys = secureStorage is TestSecureStorage
          ? (secureStorage as TestSecureStorage).storage.keys
          : const <String>[];
      expect(keys.where((key) => key.startsWith('study-data-v1-')).toSet(), {
        'study-data-v1-${AccountScope(_schoolA, 'max').fileId}',
        'study-data-v1-${AccountScope(_schoolB, 'max').fileId}',
      });
      expect((await saved(_schoolA, 'max')).notes[_exam], 'note of max');
      expect((await saved(_schoolB, 'max')).notes[_exam], 'note at b');
    });

    test('they are not part of the settings shared by all accounts', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await store.actions.settingsActions.amoledMode(true);

      final prefs = await SharedPreferences.getInstance();
      final shared = prefs.getString(globalSettingsPreferenceKey)!;
      expect(shared, isNot(contains('note of max')));
      expect(shared, isNot(contains('stored_note of max.pdf')));
      expect(
          (serializers.deserialize(jsonDecode(shared) as Object)
                  as SettingsState)
              .amoledMode,
          isTrue);
    });

    test('they are not part of the saved state of the account either',
        () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await store.actions.saveState();

      final blob = (secureStorage as TestSecureStorage)
          .storage
          .entries
          .where((entry) => entry.key.contains('server_url'))
          .map((entry) => entry.value)
          .join();
      expect(blob, isNotEmpty);
      expect(blob, isNot(contains('note of max')));
      expect(blob, isNot(contains('stored_note of max.pdf')));
    });

    test('they are gone from the store when the account is left', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();

      expect(settings().hasStudyData, isFalse);
    });

    test('an edit before they are loaded is not saved over them', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await signOut();
      // Nobody is signed in: no document may be written.
      await store.actions.settingsActions
          .setAssessmentStudyNote(const MapEntry(_exam, 'stray note'));

      expect((await saved(_schoolA, 'max')).notes[_exam], 'note of max');
      expect(
          (secureStorage as TestSecureStorage)
              .storage
              .values
              .any((value) => value.contains('stray note')),
          isFalse);
    });
  });

  group('the notes that older versions kept for all accounts', () {
    Future<void> storeLegacyNotes() async {
      SharedPreferences.setMockInitialValues({
        'tutorial.v3.seen': true,
        globalSettingsPreferenceKey: jsonEncode(serializers.serialize(
            SettingsState((b) => b
              ..languageCode = 'en'
              ..assessmentStudyNotes =
                  MapBuilder<String, String>({_exam: 'old note'})
              ..assessmentStudyProgress =
                  MapBuilder<String, String>({_exam: 'x'})))),
      });
    }

    Future<String> sharedBlob() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(globalSettingsPreferenceKey)!;
    }

    test('are not shown to whoever signs in', () async {
      await storeLegacyNotes();
      await signIn(_schoolA, 'max');

      expect(settings().assessmentStudyNotes, isEmpty);
      expect(settings().assessmentStudyProgress, isEmpty);
    });

    test('stay untouched in the shared settings until they are put aside',
        () async {
      await storeLegacyNotes();
      // Saving settings keeps the notes that are stored there as they are.
      await settingsPersistenceService.save(SettingsState((b) => b
        ..amoledMode = true
        ..assessmentStudyNotes =
            MapBuilder<String, String>({_exam: 'note of an account'})));

      final blob = await sharedBlob();
      expect(blob, contains('old note'));
      expect(blob, isNot(contains('note of an account')));
      expect((await settingsPersistenceService.load())!.amoledMode, isTrue);
    });

    test('are in the quarantine, not in the shared settings, after sign-in',
        () async {
      await storeLegacyNotes();
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await store.actions.settingsActions.amoledMode(true);
      await signOut();
      await signIn(_schoolB, 'max');
      await store.actions.settingsActions.amoledMode(false);

      final blob = await sharedBlob();
      expect(blob, isNot(contains('old note')));
      expect(blob, isNot(contains('note of max')));
      final quarantine =
          (secureStorage as TestSecureStorage).storage[studyDataLegacyKey]!;
      expect(StudyData.decode(quarantine).notes, {_exam: 'old note'});
    });

    test('are not lost when the shared settings are first created', () async {
      // An account saved before there were shared settings.
      final legacy = SettingsState((b) => b
        ..assessmentStudyNotes =
            MapBuilder<String, String>({_exam: 'note in the account'}));
      await settingsPersistenceService.adopt(legacy);

      expect(await sharedBlob(), contains('note in the account'));
      expect((await settingsPersistenceService.load())!.hasStudyData, isFalse);
      expect((await settingsPersistenceService.legacyStudyData())!.notes[_exam],
          'note in the account');
    });
  });

  group('removing the notes', () {
    Future<File> attachFile(String user, {String url = _schoolA}) async {
      final scope = AccountScope(url, user);
      final folder = await assessmentAttachmentFolder(scope);
      final file = File('${folder.path}/stored_note of $user.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('pdf of $user');
      return file;
    }

    test('signing out with data deletion deletes document and files', () async {
      await signIn(_schoolA, 'max');
      final file = await attachFile('max');
      final other = await attachFile('anna');
      await writeNotes('note of max');
      await store.actions.settingsActions.deleteDataOnLogout(true);

      await signOut();

      expect(file.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect((await saved(_schoolA, 'max')).isEmpty, isTrue);
      expect(
          (secureStorage as TestSecureStorage)
              .storage
              .containsKey(studyDataKeyFor(AccountScope(_schoolA, 'max'))),
          isFalse);
    });

    test('signing out without data deletion keeps them', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      final file = await attachFile('max');
      await signOut();

      expect(file.existsSync(), isTrue);
      expect((await saved(_schoolA, 'max')).notes[_exam], 'note of max');
    });

    test('turning off saving of data keeps them', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await store.actions.settingsActions.saveNoData(true);
      await store.actions.saveState();

      expect((await saved(_schoolA, 'max')).notes[_exam], 'note of max');
    });

    test('a late edit cannot bring deleted notes back', () async {
      await signIn(_schoolA, 'max');
      await writeNotes('note of max');
      await store.actions.settingsActions.deleteDataOnLogout(true);
      await store.actions.deleteData();
      await store.actions.settingsActions
          .setAssessmentStudyNote(const MapEntry(_exam, 'after deletion'));

      expect((await saved(_schoolA, 'max')).isEmpty, isTrue);
    });
  });

  group('an unreadable document', () {
    test('is never written over', () async {
      final key = studyDataKeyFor(AccountScope(_schoolA, 'max'));
      final storage = _FailingReadStorage(key)..storage[key] = _document();
      secureStorage = storage;

      await signIn(_schoolA, 'max');
      await writeNotes('new note');
      await signOut();

      expect(storage.storage[key], _document());
      expect(storage.failedReads, greaterThan(0));
    });

    test('is loaded as soon as it can be read again', () async {
      final key = studyDataKeyFor(AccountScope(_schoolA, 'max'));
      final storage = _FailingReadStorage(key)..storage[key] = _document();
      secureStorage = storage;
      await signIn(_schoolA, 'max');
      await signOut();

      storage.failing = false;
      await signIn(_schoolA, 'max');

      expect(settings().assessmentStudyNotes[_exam], 'kept note');
    });

    test('a document of an unknown format is kept as it is', () async {
      final key = studyDataKeyFor(AccountScope(_schoolA, 'max'));
      const future = '{"version":2,"notes":{"assessment-7":"newer"}}';
      (secureStorage as TestSecureStorage).storage[key] = future;

      await signIn(_schoolA, 'max');
      await writeNotes('new note');

      expect((secureStorage as TestSecureStorage).storage[key], future);
    });
  });

  group('attachment files', () {
    const max = 'https://a.school.example';

    test('a stored name leads into the folder of the account', () async {
      final scope = AccountScope(max, 'max');
      final file = await resolveAssessmentAttachmentFile(
          const AssessmentAttachment(name: 'x.pdf', path: 'stored_x.pdf'),
          scope);

      final folder = await assessmentAttachmentFolder(scope);
      expect(file!.path, '${folder.path}${Platform.pathSeparator}stored_x.pdf');
      expect(
          file.path,
          isNot((await resolveAssessmentAttachmentFile(
                  const AssessmentAttachment(
                      name: 'x.pdf', path: 'stored_x.pdf'),
                  AccountScope(max, 'anna')))!
              .path));
    });

    test('a file of another account is not found by its name', () async {
      final other = await assessmentAttachmentFolder(AccountScope(max, 'anna'));
      File('${other.path}/stored_x.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('anna');

      final file = await resolveAssessmentAttachmentFile(
          const AssessmentAttachment(name: 'x.pdf', path: 'stored_x.pdf'),
          AccountScope(max, 'max'));

      expect(file!.existsSync(), isFalse);
    });

    test('a path saved by an older version is still read', () async {
      final old = File('${attachmentsRoot.path}/1_old.pdf')
        ..writeAsStringSync('old');
      final file = await resolveAssessmentAttachmentFile(
          AssessmentAttachment(name: 'old.pdf', path: old.path),
          AccountScope(max, 'max'));

      expect(file!.path, old.path);
      expect(file.readAsStringSync(), 'old');
    });

    test('names that leave the folder are not resolved', () async {
      for (final name in ['../x.pdf', 'a/b.pdf', r'..\x.pdf', 'relative/x']) {
        expect(
            await resolveAssessmentAttachmentFile(
                AssessmentAttachment(name: 'x', path: name),
                AccountScope(max, 'max')),
            isNull,
            reason: name);
      }
    });

    test('removing one deletes only the file of the account', () async {
      final mine = await assessmentAttachmentFolder(AccountScope(max, 'max'));
      final theirs =
          await assessmentAttachmentFolder(AccountScope(max, 'anna'));
      final mineFile = File('${mine.path}/stored_x.pdf')
        ..createSync(recursive: true);
      final theirFile = File('${theirs.path}/stored_x.pdf')
        ..createSync(recursive: true);

      await removeAssessmentAttachment(
          const AssessmentAttachment(name: 'x.pdf', path: 'stored_x.pdf'),
          AccountScope(max, 'max'));

      expect(mineFile.existsSync(), isFalse);
      expect(theirFile.existsSync(), isTrue);
    });
  });

  test('a save of the notes waits behind a write that is still running',
      () async {
    await signIn(_schoolA, 'max');
    final release = Completer<void>();
    final running = statePersistenceService.flush(
      state: store.state,
      deletedData: false,
      server: wrapper.loginAddress,
      writer: (key, value) => release.future,
      keyFactory: getStorageKey,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final edit = store.actions.settingsActions
        .setAssessmentStudyNote(const MapEntry(_exam, 'queued note'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await _rawDocument(_schoolA, 'max')), isNull);

    release.complete();
    await running;
    await edit;

    expect((await saved(_schoolA, 'max')).notes[_exam], 'queued note');
  });

  group('the saved document', () {
    test('survives encoding and decoding', () {
      const data = StudyData(
        progress: {'assessment-1': 'a,b'},
        notes: {'assessment-1': 'note', 'assessment-2': 'more'},
        attachments: {
          'assessment-1': '[{"name":"a.pdf","path":"1_a.pdf"},'
              '{"name":"b.pdf","path":"2_b.pdf"}]'
        },
        phases: {'assessment-2': '[]'},
      );

      expect(StudyData.decode(data.encode()), data);
      expect(data.noteCount, 2);
      expect(data.fileCount, 2);
      expect(data.isEmpty, isFalse);
    });

    test('is refused when it is not version 1 data', () {
      for (final raw in [
        '{"version":2}',
        '[]',
        'not json',
        '{"version":1,"notes":{"a":1}}',
        '{"version":1,"notes":[]}',
      ]) {
        expect(() => StudyData.decode(raw), throwsA(isA<StudyDataCorrupt>()),
            reason: raw);
      }
    });
  });

  test('the store, the session and the saved account name one scope', () async {
    await signIn(_schoolA, 'max');

    expect(currentAccountScope(), AccountScope(_schoolA, 'max'));
    expect(AccountScope(store.state.url, store.state.loginState.username),
        currentAccountScope());
  });
}

Future<String?> _rawDocument(String url, String user) async =>
    (secureStorage as TestSecureStorage)
        .storage[studyDataKeyFor(AccountScope(url, user))];

String _document() => jsonEncode({
      'version': 1,
      'notes': {'assessment-7': 'kept note'},
    });

/// Secure storage that cannot read one key until [failing] is switched off.
class _FailingReadStorage extends TestSecureStorage {
  _FailingReadStorage(this.failingKey);

  final String failingKey;
  bool failing = true;
  int failedReads = 0;

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
    if (failing && key == failingKey) {
      failedReads++;
      throw StateError('keystore unavailable');
    }
    return storage[key];
  }
}
