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

import 'package:built_collection/built_collection.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/app_state.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/serializers.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/study_data_migration.dart';
import 'package:dr/study_data_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

final _account = AccountScope('https://a.school.example', 'max');
final _other = AccountScope('https://a.school.example', 'anna');

class _Aborted implements Exception {
  @override
  String toString() => 'aborted';
}

/// Secure storage that can stop the n-th write or delete, or fail reads.
class _Storage extends TestSecureStorage {
  int operations = 0;
  int? abortAt;
  bool failReads = false;
  bool failReadsOfMarkerOnly = false;
  bool failReadBackOfKey = false;
  String? keyToFailReads;

  void _count() {
    operations++;
    if (abortAt == operations) throw _Aborted();
  }

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
    _count();
    storage[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    _count();
    storage.remove(key);
  }

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
    if (failReads || (keyToFailReads != null && key == keyToFailReads)) {
      throw StateError('keystore unavailable');
    }
    return storage[key];
  }
}

/// The notes of two exams, with three files loose in the shared folder.
class _Fixture {
  _Fixture(this.root);

  final Directory root;

  File file(String name) => File('${root.path}/$name');

  String attachments(List<(String, String)> files) =>
      encodeAssessmentAttachments([
        for (final (name, stored) in files)
          AssessmentAttachment(name: name, path: file(stored).path),
      ]);

  late final StudyData legacy = StudyData(
    progress: const {'assessment-7': 'a,b'},
    notes: const {
      'assessment-7': 'old note 7',
      'assessment-9': 'old note 9',
    },
    attachments: {
      'assessment-7': attachments([('a.pdf', '111_a.pdf')]),
      'assessment-9':
          attachments([('b.pdf', '222_b.pdf'), ('c.pdf', '333_c.pdf')]),
    },
    phases: const {'assessment-9': '[{"id":"p"}]'},
  );

  static const contents = {
    '111_a.pdf': 'content of a',
    '222_b.pdf': 'content of b',
    '333_c.pdf': 'content of c',
  };

  void createFiles() {
    for (final entry in contents.entries) {
      file(entry.key).writeAsStringSync(entry.value);
    }
  }
}

void main() {
  late Directory root;
  late _Storage storage;
  late _Fixture fixture;
  late StudyDataService service;
  late StudyDataMigration migration;

  Future<void> storeShared(StudyData legacy, {String language = 'it'}) async {
    SharedPreferences.setMockInitialValues({
      globalSettingsPreferenceKey: jsonEncode(serializers.serialize(
          legacy.applyTo(SettingsState((b) => b..languageCode = language)))),
    });
  }

  /// Starts the scenario over: fresh storage, files and shared settings.
  Future<void> freshScenario() async {
    for (final entry in root.listSync()) {
      entry.deleteSync(recursive: true);
    }
    fixture.createFiles();
    storage = _Storage();
    secureStorage = storage;
    service = StudyDataService(storage: () => storage)
      ..retryDelay = Duration.zero;
    migration = StudyDataMigration(
        service: service, settings: SettingsPersistenceService());
    await storeShared(fixture.legacy);
  }

  setUp(() async {
    await bootstrapTestEnvironment();
    root = await Directory.systemTemp.createTemp('study-migration-');
    assessmentAttachmentsRootOverride = () async => root;
    fixture = _Fixture(root);
    await freshScenario();
  });

  tearDown(() async {
    assessmentAttachmentsRootOverride = null;
    await root.delete(recursive: true);
    await resetTestState();
  });

  Future<StudyData?> shared() => SettingsPersistenceService().legacyStudyData();

  Future<String> sharedBlob() async => (await SharedPreferences.getInstance())
      .getString(globalSettingsPreferenceKey)!;

  Future<StudyData?> quarantine() => migration.readQuarantine();

  Future<String?> marker() async =>
      storage.storage[studyDataMigrationMarkerKey];

  String readFile(String name) => fixture.file(name).readAsStringSync();

  /// Everything the user could still want, found wherever it is kept: no note
  /// and no file may be missing from all places at once.
  Future<void> expectNothingLost({StudyData? alsoIn}) async {
    final places = <StudyData>[
      if (await shared() case final data?) data,
      if (storage.storage[studyDataLegacyKey] case final raw?)
        StudyData.decode(raw),
      for (final scope in [_account, _other])
        if (storage.storage[studyDataKeyFor(scope)] case final raw?)
          StudyData.decode(raw),
    ];
    for (final entry in fixture.legacy.notes.entries) {
      expect(
          places.any((place) => place.notes[entry.key] == entry.value), isTrue,
          reason: 'note ${entry.key} is nowhere');
    }
    for (final entry in fixture.legacy.progress.entries) {
      expect(places.any((place) => place.progress[entry.key] == entry.value),
          isTrue,
          reason: 'progress ${entry.key} is nowhere');
    }
    for (final entry in fixture.legacy.phases.entries) {
      expect(
          places.any((place) => place.phases[entry.key] == entry.value), isTrue,
          reason: 'phases ${entry.key} is nowhere');
    }
    // Every file, by content, loose in the shared folder or in a folder of an
    // account whose document names it.
    final contentsFound = <String>{};
    for (final entity in root.listSync(recursive: true).whereType<File>()) {
      if (entity.path.endsWith('.part')) continue;
      contentsFound.add(entity.readAsStringSync());
    }
    for (final entry in _Fixture.contents.entries) {
      expect(contentsFound, contains(entry.value),
          reason: 'file ${entry.key} is gone');
    }
    // An entry of an account never points at a file that is not there.
    for (final scope in [_account, _other]) {
      final raw = storage.storage[studyDataKeyFor(scope)];
      if (raw == null) continue;
      for (final value in StudyData.decode(raw).attachments.values) {
        for (final attachment in decodeAssessmentAttachments(value)) {
          final resolved =
              await resolveAssessmentAttachmentFile(attachment, scope);
          expect(resolved != null && await resolved.exists(), isTrue,
              reason: 'an entry of an account points at no file');
        }
      }
    }
  }

  group('the first run', () {
    test(
        'copies the notes unchanged into the quarantine and then frees the '
        'shared settings', () async {
      expect(await migration.ensureQuarantined(),
          StudyMigrationStatus.quarantined);

      expect(await quarantine(), fixture.legacy);
      expect(await marker(), 'quarantined');
      expect((await shared())!.isEmpty, isTrue);
      expect(await sharedBlob(), contains('"it"'));
      for (final entry in _Fixture.contents.entries) {
        expect(readFile(entry.key), entry.value);
      }
      expect(migration.summary(), completion(isNotNull));
    });

    test('gives numbers and nothing else to show', () async {
      await migration.ensureQuarantined();
      final summary = (await migration.summary())!;

      expect(summary.exams, 2);
      expect(summary.notes, 2);
      expect(summary.files, 3);
    });

    test('has nothing to do without notes', () async {
      await storeShared(StudyData.empty);

      expect(await migration.ensureQuarantined(), StudyMigrationStatus.done);
      expect(await marker(), 'done');
      expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
      expect(await migration.summary(), isNull);
    });

    test('has nothing to do without shared settings', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await migration.ensureQuarantined(), StudyMigrationStatus.done);
      expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
    });

    test('does nothing again once it is done', () async {
      await migration.ensureQuarantined();
      final before = Map.of(storage.storage);

      await migration.ensureQuarantined();
      await migration.ensureQuarantined();

      expect(storage.storage, before);
      expect(await quarantine(), fixture.legacy);
    });
  });

  group('a read that fails', () {
    test('postpones the run and sets no marker', () async {
      storage.failReads = true;

      await expectLater(
          migration.ensureQuarantined(), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage.containsKey(studyDataMigrationMarkerKey), isFalse);
      expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
      expect(await shared(), fixture.legacy);

      storage.failReads = false;
      expect(await migration.ensureQuarantined(),
          StudyMigrationStatus.quarantined);
      expect(await quarantine(), fixture.legacy);
    });

    test('while checking the copy leaves the notes where they are', () async {
      // The copy is written, but cannot be read back to be compared.
      storage.keyToFailReads = studyDataLegacyKey;

      await expectLater(
          migration.ensureQuarantined(), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage.containsKey(studyDataMigrationMarkerKey), isFalse);
      expect(await shared(), fixture.legacy);

      storage.keyToFailReads = null;
      await migration.ensureQuarantined();
      expect(await marker(), 'quarantined');
      expect(await quarantine(), fixture.legacy);
    });

    test('of shared settings that cannot be decoded leaves them untouched',
        () async {
      SharedPreferences.setMockInitialValues(
          {globalSettingsPreferenceKey: '{"broken'});

      await expectLater(
          migration.ensureQuarantined(), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage.containsKey(studyDataMigrationMarkerKey), isFalse);
      expect(
          (await SharedPreferences.getInstance())
              .getString(globalSettingsPreferenceKey),
          '{"broken');
    });

    test('of the marker never sets it', () async {
      storage.keyToFailReads = studyDataMigrationMarkerKey;

      await expectLater(
          migration.ensureQuarantined(), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage, isEmpty);
      expect(await shared(), fixture.legacy);
    });
  });

  group('a run that stops', () {
    Future<List<String>> stepsOfACleanRun() async {
      final steps = <String>[];
      migration.onStep = (step) async => steps.add(step);
      await migration.ensureQuarantined();
      migration.onStep = null;
      return steps;
    }

    test('after any step loses nothing and ends the same when repeated',
        () async {
      final steps = await stepsOfACleanRun();
      expect(steps, isNotEmpty);
      final reference = (await quarantine(), await marker());

      for (var stop = 0; stop < steps.length; stop++) {
        await freshScenario();
        migration.onStep = (step) async {
          if (migration.onStep != null && _count++ == stop) throw _Aborted();
        };
        _count = 0;
        await expectLater(
            migration.ensureQuarantined(), throwsA(isA<_Aborted>()),
            reason: 'stop at step $stop (${steps[stop]})');
        await expectNothingLost();

        migration.onStep = null;
        await migration.ensureQuarantined();
        expect((await quarantine(), await marker()), reference,
            reason: 'after stop at step $stop (${steps[stop]})');
        expect((await shared())!.isEmpty, isTrue);
      }
    });

    test('after any write or delete loses nothing and ends the same', () async {
      await migration.ensureQuarantined();
      final reference = (await quarantine(), await marker());
      final operations = storage.operations;
      expect(operations, greaterThanOrEqualTo(2));

      for (var stop = 1; stop <= operations; stop++) {
        await freshScenario();
        storage.abortAt = stop;
        await expectLater(
            migration.ensureQuarantined(), throwsA(isA<_Aborted>()),
            reason: 'stop at operation $stop');
        storage.abortAt = null;
        await expectNothingLost();

        await migration.ensureQuarantined();
        expect((await quarantine(), await marker()), reference,
            reason: 'after stop at operation $stop');
        expect((await shared())!.isEmpty, isTrue);
      }
    });

    test('with the shared settings not freed yet frees them next time',
        () async {
      await migration.ensureQuarantined();
      // The marker is set but the removal from the shared settings was lost.
      await SettingsPersistenceService().adopt(SettingsState());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          globalSettingsPreferenceKey,
          jsonEncode(
              serializers.serialize(fixture.legacy.applyTo(SettingsState()))));
      expect(await shared(), fixture.legacy);

      await migration.ensureQuarantined();

      expect((await shared())!.isEmpty, isTrue);
      expect(await quarantine(), fixture.legacy);
    });

    test('never frees shared settings that the quarantine does not hold',
        () async {
      await migration.ensureQuarantined();
      final newer = fixture.legacy.withMissingFrom(const StudyData(
          notes: {'assessment-99': 'written somewhere else later'}));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(globalSettingsPreferenceKey,
          jsonEncode(serializers.serialize(newer.applyTo(SettingsState()))));

      await migration.ensureQuarantined();

      // The quarantine is not a superset: nothing is dropped.
      expect(await shared(), newer);
    });

    test('with a lost quarantine restores it from the shared settings',
        () async {
      await migration.ensureQuarantined();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          globalSettingsPreferenceKey,
          jsonEncode(
              serializers.serialize(fixture.legacy.applyTo(SettingsState()))));
      storage.storage.remove(studyDataLegacyKey);

      expect(await migration.ensureQuarantined(),
          StudyMigrationStatus.quarantined);
      expect(await quarantine(), fixture.legacy);
    });
  });

  group('assigning', () {
    Future<void> quarantined() async {
      await migration.ensureQuarantined();
    }

    test('gives the account its notes and files and empties the quarantine',
        () async {
      await quarantined();

      final outcome = await migration.assign(_account);

      expect(outcome.remaining.isEmpty, isTrue);
      final account = await service.load(_account);
      expect(account.notes, fixture.legacy.notes);
      expect(account.progress, fixture.legacy.progress);
      expect(account.phases, fixture.legacy.phases);
      // The files are copies in the folder of the account.
      final folder = await assessmentAttachmentFolder(_account);
      final names = <String>[];
      for (final value in account.attachments.values) {
        for (final attachment in decodeAssessmentAttachments(value)) {
          expect(isSafeName(attachment.path), isTrue);
          final file = File('${folder.path}/${attachment.path}');
          names.add(attachment.name);
          expect(file.existsSync(), isTrue);
        }
      }
      expect(names..sort(), ['a.pdf', 'b.pdf', 'c.pdf']);
      // The old files are gone, the copies hold the same content.
      for (final name in _Fixture.contents.keys) {
        expect(fixture.file(name).existsSync(), isFalse);
      }
      expect(
          folder.listSync().whereType<File>().map((f) => f.readAsStringSync()),
          unorderedEquals(_Fixture.contents.values));
      expect(await marker(), 'done');
      expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
      expect(await migration.summary(), isNull);
    });

    test('never replaces what the account already has', () async {
      await quarantined();
      await service.save(
          _account,
          const StudyData(
            notes: {'assessment-7': 'my own note'},
            progress: {'assessment-9': 'z'},
            attachments: {'assessment-9': '[{"name":"mine.pdf","path":"1_m"}]'},
          ));

      final outcome = await migration.assign(_account);

      final account = await service.load(_account);
      expect(account.notes['assessment-7'], 'my own note');
      expect(account.notes['assessment-9'], 'old note 9');
      expect(account.progress['assessment-9'], 'z');
      expect(account.progress['assessment-7'], 'a,b');
      expect(account.attachments['assessment-9'],
          '[{"name":"mine.pdf","path":"1_m"}]');
      // What was not taken over stays quarantined, files included.
      expect(outcome.remaining.notes, {'assessment-7': 'old note 7'});
      expect(outcome.remaining.attachments.keys, ['assessment-9']);
      final left = await quarantine();
      expect(left!.notes, {'assessment-7': 'old note 7'});
      expect(left.attachments.keys, ['assessment-9']);
      expect(await marker(), 'quarantined');
      expect(fixture.file('222_b.pdf').existsSync(), isTrue);
      expect(fixture.file('333_c.pdf').existsSync(), isTrue);
      // The file of the entry that moved is a copy of the account now.
      expect(fixture.file('111_a.pdf').existsSync(), isFalse);
      expect(decodeAssessmentAttachments(account.attachments['assessment-7']),
          hasLength(1));
    });

    test('keeps entries of the app that are not saved yet', () async {
      await quarantined();

      await migration.assign(_account,
          current: const StudyData(notes: {'assessment-7': 'typed just now'}));

      expect((await service.load(_account)).notes['assessment-7'],
          'typed just now');
    });

    test('leaves another account alone', () async {
      await quarantined();
      await service.save(_other, const StudyData(notes: {'x': 'anna'}));

      await migration.assign(_account);

      expect((await service.load(_other)).notes, {'x': 'anna'});
      final folder = await assessmentAttachmentFolder(_other);
      expect(folder.existsSync(), isFalse);
    });

    test('keeps a note whose file is missing and does not delete anything',
        () async {
      await quarantined();
      fixture.file('222_b.pdf').deleteSync();

      await migration.assign(_account);

      final account = await service.load(_account);
      final files =
          decodeAssessmentAttachments(account.attachments['assessment-9']);
      expect(files, hasLength(2));
      // The file that was there is copied, the one that was not keeps its
      // old path.
      expect(
          isSafeName(files.firstWhere((f) => f.name == 'c.pdf').path), isTrue);
      expect(files.firstWhere((f) => f.name == 'b.pdf').path,
          fixture.file('222_b.pdf').path);
    });

    test('does not copy or delete a file outside the shared folder', () async {
      final outside = await Directory.systemTemp.createTemp('study-outside-');
      addTearDown(() => outside.delete(recursive: true));
      final foreign = File('${outside.path}/foreign.pdf')
        ..writeAsStringSync('not ours');
      await storeShared(StudyData(
        notes: const {'assessment-1': 'n'},
        attachments: {
          'assessment-1': encodeAssessmentAttachments(
              [AssessmentAttachment(name: 'foreign.pdf', path: foreign.path)])
        },
      ));
      await quarantined();

      await migration.assign(_account);
      await migration.discard();

      expect(foreign.readAsStringSync(), 'not ours');
      final folder = await assessmentAttachmentFolder(_account);
      expect(folder.existsSync() && folder.listSync().isNotEmpty, isFalse);
    });

    test('twice ends with the same result', () async {
      await quarantined();
      await migration.assign(_account);
      final account = await service.load(_account);

      final second = await migration.assign(_account);

      expect(second.moved.isEmpty, isTrue);
      expect(await service.load(_account), account);
    });

    test('with an unreadable account document changes nothing', () async {
      await quarantined();
      storage.keyToFailReads = studyDataKeyFor(_account);
      final before = Map.of(storage.storage);

      await expectLater(
          migration.assign(_account), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage, before);
      for (final name in _Fixture.contents.keys) {
        expect(fixture.file(name).existsSync(), isTrue);
      }
    });

    test('with an account document of an unknown format changes nothing',
        () async {
      await quarantined();
      storage.storage[studyDataKeyFor(_account)] = '{"version":2}';
      final before = Map.of(storage.storage);

      await expectLater(
          migration.assign(_account), throwsA(isA<StudyDataUnreadable>()));

      expect(storage.storage, before);
    });

    test('before the quarantine exists does nothing', () async {
      final outcome = await migration.assign(_account);

      expect(outcome.moved.isEmpty, isTrue);
      expect(storage.storage, isEmpty);
    });

    test('after any step or write that stops loses nothing and ends the same',
        () async {
      await quarantined();
      final steps = <String>[];
      migration.onStep = (step) async => steps.add(step);
      await migration.assign(_account);
      migration.onStep = null;
      final referenceAccount = await service.load(_account);
      final referenceFiles =
          _folderContents(await assessmentAttachmentFolder(_account));
      final operations = storage.operations;

      // Stop before each step, and at each write or delete of a run.
      for (var stop = 0; stop < steps.length + operations; stop++) {
        await freshScenario();
        await quarantined();
        storage.operations = 0;
        if (stop < steps.length) {
          _count = 0;
          migration.onStep = (step) async {
            if (_count++ == stop) throw _Aborted();
          };
        } else {
          storage.abortAt = stop - steps.length + 1;
        }
        final reason = stop < steps.length
            ? 'stop at step ${steps[stop]}'
            : 'stop at write ${stop - steps.length + 1}';
        try {
          await migration.assign(_account);
        } on _Aborted {
          // expected
        }
        migration.onStep = null;
        storage.abortAt = null;
        await expectNothingLost();

        await migration.assign(_account);
        final account = await service.load(_account);
        expect(account.notes, referenceAccount.notes, reason: reason);
        expect(account.progress, referenceAccount.progress, reason: reason);
        expect(account.phases, referenceAccount.phases, reason: reason);
        expect(
            _namesOfAttachments(account), _namesOfAttachments(referenceAccount),
            reason: reason);
        expect(_folderContents(await assessmentAttachmentFolder(_account)),
            unorderedEquals(referenceFiles),
            reason: reason);
        expect(await marker(), 'done', reason: reason);
        // Only a stop between the end of the migration and the deletion of
        // the old files leaves some of them behind, unreferenced; they are
        // the original files and nothing else.
        final loose = root.listSync().whereType<File>().map((f) => f.path);
        expect(
            loose.every((path) =>
                _Fixture.contents.keys.any((name) => path.endsWith(name))),
            isTrue,
            reason: reason);
      }
    });
  });

  group('discarding', () {
    test('deletes the quarantine and its files and closes the migration',
        () async {
      await migration.ensureQuarantined();

      await migration.discard();

      expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
      expect(await marker(), 'done');
      expect((await shared())!.isEmpty, isTrue);
      for (final name in _Fixture.contents.keys) {
        expect(fixture.file(name).existsSync(), isFalse);
      }
      expect(await service.load(_account), StudyData.empty);
    });

    test('does not touch files of accounts', () async {
      await migration.ensureQuarantined();
      final folder = await assessmentAttachmentFolder(_account);
      final own = File('${folder.path}/own.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('own');

      await migration.discard();

      expect(own.readAsStringSync(), 'own');
    });

    test('that stops can be repeated', () async {
      await migration.ensureQuarantined();
      final steps = <String>[];
      migration.onStep = (step) async => steps.add(step);
      await migration.discard();
      migration.onStep = null;

      for (var stop = 0; stop < steps.length; stop++) {
        await freshScenario();
        await migration.ensureQuarantined();
        _count = 0;
        migration.onStep = (step) async {
          if (_count++ == stop) throw _Aborted();
        };
        await expectLater(migration.discard(), throwsA(isA<_Aborted>()),
            reason: 'stop at ${steps[stop]}');
        migration.onStep = null;

        await migration.discard();
        expect(await marker(), 'done', reason: steps[stop]);
        expect(storage.storage.containsKey(studyDataLegacyKey), isFalse);
        expect((await shared())!.isEmpty, isTrue);
      }
    });
  });

  group('when the quarantine is gone', () {
    test('there is nothing to show', () async {
      expect(await migration.summary(), isNull);
      await migration.ensureQuarantined();
      await migration.discard();
      expect(await migration.summary(), isNull);
    });
  });
}

int _count = 0;

bool isSafeName(String name) =>
    name.isNotEmpty && !name.contains('/') && !name.contains(r'\');

List<String> _folderContents(Directory folder) => folder.existsSync()
    ? folder
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.endsWith('.part'))
        .map((file) => file.readAsStringSync())
        .toList()
    : <String>[];

List<String> _namesOfAttachments(StudyData data) => [
      for (final value in data.attachments.values)
        for (final a in decodeAssessmentAttachments(value)) a.name,
    ]..sort();
