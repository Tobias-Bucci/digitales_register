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
import 'package:dr/calendar_sync_service.dart';
import 'package:dr/class_register_cache.dart';
import 'package:dr/local_data_inventory.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/page_payload_cache.dart';
import 'package:dr/study_data_service.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

const _school = 'https://a.school.example';

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

  /// The answer to every request of the page caches.
  Object? answer = '<html>homework</html>';
  final List<String> sent = <String>[];

  @override
  String get loginAddress => '$url/v2/api/auth/login';
  @override
  String get baseAddress => '$url/v2/';
  @override
  void logout({required bool hard, bool logoutForcedByServer = false}) {}

  @override
  Future<dynamic> send(String path,
      {Map<String, Object?> args = const {},
      String method = 'POST',
      bool isRetryAfterUnexpectedLogout = false,
      bool forceRelogin = false,
      int unexpectedLogoutRetryCount = 0,
      bool acceptEmptyResponse = false}) async {
    sent.add(path);
    return answer;
  }
}

void main() {
  late Directory work;
  late Directory attachments;
  late Directory downloads;
  late Directory openCopies;
  late Store<AppState, AppStateBuilder, AppActions> store;
  late _AccountWrapper session;
  late String storageKey;
  late AccountScope scope;

  setUp(() async {
    await bootstrapTestEnvironment();
    work = await Directory.systemTemp.createTemp('local-data-');
    attachments = Directory('${work.path}/attachments')..createSync();
    downloads = Directory('${work.path}/downloads')..createSync();
    openCopies = Directory('${work.path}/open')..createSync();
    assessmentAttachmentsRootOverride = () async => attachments;
    assessmentOpenCopiesFolderOverride = () async => openCopies;
    attachmentDownloadDirectoryOverride = () async => downloads.path;
    store = createStore(withMiddleware: true);
    addTearDown(store.dispose);
    session = _AccountWrapper(_school, 'max');
    wrapper = session;
    scope = AccountScope(_school, 'max');
    storageKey = getStorageKey('max', session.loginAddress);
    await store.actions.setUrl(_school);
    await store.actions.loginActions.loggedIn(LoggedInPayload((b) => b
      ..username = 'max'
      ..fromStorage = true
      ..offlineOnly = true));
  });

  tearDown(() async {
    assessmentAttachmentsRootOverride = null;
    assessmentOpenCopiesFolderOverride = null;
    attachmentDownloadDirectoryOverride = null;
    await work.delete(recursive: true);
    await resetTestState();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  List<String> cacheKeys() => [
        'homeworkSummary:$storageKey',
        'classRegisterLessons:$storageKey',
        'courseMaterials:$storageKey',
      ];

  /// Puts something into every place the app keeps data of the account.
  Future<void> fillEverything() async {
    final p = await prefs();
    for (final key in cacheKeys()) {
      await p.setString(key, jsonEncode({'payload': <Object?>[]}));
    }
    await p.setString('gradeDeadlineOverrides:$storageKey', '{"count":1}');
    await p.setString('courseMaterialFileVersions:${scope.fileId}', '{}');
    await p.setString('calendarSyncRecords', '[{"syncKey":"k","eventId":1}]');
    await studyDataService.save(
        scope, const StudyData(notes: {'assessment-1': 'my note'}));
    File('${attachments.path}/${scope.fileId}/1_a.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('study file');
    File('${openCopies.path}/2_a.pdf').writeAsStringSync('open copy');
    File('${downloads.path}/${scope.fileId}/course_1_x.pdf')
      ..createSync(recursive: true)
      ..writeAsStringSync('download');
  }

  Future<void> expectCachesGone() async {
    final p = await prefs();
    for (final key in cacheKeys()) {
      expect(p.containsKey(key), isFalse, reason: key);
    }
  }

  /// What deleting data must leave: things outside the app, and files the
  /// user downloaded.
  Future<void> expectOutsideLeftAlone() async {
    final p = await prefs();
    expect(p.getString('calendarSyncRecords'), isNotNull);
    expect(
        p.getString('courseMaterialFileVersions:${scope.fileId}'), isNotNull);
    expect(
        File('${downloads.path}/${scope.fileId}/course_1_x.pdf')
            .readAsStringSync(),
        'download');
  }

  group('caches are not written while saving is off', () {
    test('the page cache, the class register cache and the homework refresh',
        () async {
      await store.actions.settingsActions.saveNoData(true);

      await pagePayloadCacheService.save('homeworkSummary:$storageKey',
          PagePayloadSnapshot<String>.fromPayload('<html></html>'));
      await classRegisterCacheService.save(
          'classRegisterLessons:$storageKey',
          ClassRegisterPayloadSnapshot.fromPayload(
              const <Map<String, dynamic>>[]));
      final refreshed = await refreshHomeworkSummaryHtmlPayload();

      // The page is still shown, it is only not kept.
      expect(refreshed, isNotNull);
      expect(session.sent, isNotEmpty);
      expect((await prefs()).getKeys().where((k) => k.contains(':')), isEmpty);
    });

    test('the lessons and course materials a refresh loads', () async {
      await store.actions.settingsActions.saveNoData(true);
      session.answer = <dynamic>[];

      await refreshClassRegisterLessonPayload();
      await refreshCourseMaterialsPayload();

      expect((await prefs()).getKeys().where((k) => k.contains(':')), isEmpty);
    });

    test('and are written again once saving is on', () async {
      await store.actions.settingsActions.saveNoData(true);
      await store.actions.settingsActions.saveNoData(false);

      await refreshHomeworkSummaryHtmlPayload();

      expect(
          (await prefs()).containsKey('homeworkSummary:$storageKey'), isTrue);
    });

    test('and not after data was deleted, whatever finishes later', () async {
      await store.actions.deleteData();

      await refreshHomeworkSummaryHtmlPayload();
      await pagePayloadCacheService.save('homeworkSummary:$storageKey',
          PagePayloadSnapshot<String>.fromPayload('<html></html>'));

      expect(
          (await prefs()).containsKey('homeworkSummary:$storageKey'), isFalse);
    });
  });

  group('turning saving off', () {
    test('deletes the caches of the account and nothing the user wrote',
        () async {
      await fillEverything();

      await store.actions.settingsActions.saveNoData(true);

      await expectCachesGone();
      final p = await prefs();
      expect(p.getString('gradeDeadlineOverrides:$storageKey'), isNotNull);
      expect((await studyDataService.load(scope)).notes,
          {'assessment-1': 'my note'});
      expect(File('${attachments.path}/${scope.fileId}/1_a.pdf').existsSync(),
          isTrue);
      await expectOutsideLeftAlone();
    });

    test('leaves the caches of another account alone', () async {
      await fillEverything();
      final other = getStorageKey('anna', session.loginAddress);
      await (await prefs()).setString('homeworkSummary:$other', '{}');

      await store.actions.settingsActions.saveNoData(true);

      expect((await prefs()).getString('homeworkSummary:$other'), '{}');
    });
  });

  group('deleting data', () {
    Future<void> expectDeletedForTheAccount() async {
      await expectCachesGone();
      final p = await prefs();
      expect(p.containsKey('gradeDeadlineOverrides:$storageKey'), isFalse);
      expect((await studyDataService.load(scope)).isEmpty, isTrue);
      expect(Directory('${attachments.path}/${scope.fileId}').existsSync(),
          isFalse);
      expect(openCopies.existsSync(), isFalse);
      await expectOutsideLeftAlone();
    }

    test('removes every cache, note, file and copy of the account', () async {
      await fillEverything();

      await store.actions.deleteData();

      await expectDeletedForTheAccount();
    });

    test('is what signing out with deletion of data does', () async {
      await fillEverything();
      await store.actions.settingsActions.deleteDataOnLogout(true);

      await store.actions.loginActions.logout(LogoutPayload((b) => b
        ..hard = true
        ..forced = false));

      await expectDeletedForTheAccount();
    });

    test('does not touch what other accounts have', () async {
      await fillEverything();
      final other = AccountScope(_school, 'anna');
      await studyDataService.save(
          other, const StudyData(notes: {'assessment-1': 'anna'}));
      final otherKey = getStorageKey('anna', session.loginAddress);
      final p = await prefs();
      await p.setString('homeworkSummary:$otherKey', '{}');
      File('${attachments.path}/${other.fileId}/1_a.pdf')
        ..createSync(recursive: true)
        ..writeAsStringSync('anna file');

      await store.actions.deleteData();

      expect((await studyDataService.load(other)).notes, isNotEmpty);
      expect(p.getString('homeworkSummary:$otherKey'), '{}');
      expect(File('${attachments.path}/${other.fileId}/1_a.pdf').existsSync(),
          isTrue);
    });
  });

  group('removing an account', () {
    test('deletes everything of it through the same list', () async {
      await fillEverything();
      final blob = escapeKey(storageKey);
      (secureStorage as TestSecureStorage).storage[blob] = 'state';
      await secureStorage.write(
          key: 'login',
          value: jsonEncode({'user': 'max', 'pass': 'p', 'url': _school}));

      await store.actions.loginActions.removeCurrentAccount();

      await expectCachesGone();
      final p = await prefs();
      expect(p.containsKey('gradeDeadlineOverrides:$storageKey'), isFalse);
      expect(
          p.containsKey('courseMaterialFileVersions:${scope.fileId}'), isFalse);
      expect((await secureStorage.read(key: blob)), isNull);
      expect((await studyDataService.load(scope)).isEmpty, isTrue);
      expect(Directory('${attachments.path}/${scope.fileId}').existsSync(),
          isFalse);
      expect(
          Directory('${downloads.path}/${scope.fileId}').existsSync(), isFalse);
      expect(openCopies.existsSync(), isFalse);
      // Entries in the calendar of the device are not the app's to remove.
      expect(p.getString('calendarSyncRecords'), isNotNull);
    });
  });

  group('the calendar entries the app exported', () {
    test('and the list that finds them again are left alone by every path',
        () async {
      await fillEverything();

      await store.actions.settingsActions.saveNoData(true);
      await store.actions.deleteData();

      expect((await prefs()).getString('calendarSyncRecords'),
          '[{"syncKey":"k","eventId":1}]');
    });

    test('are deleted only by the explicit action', () async {
      await fillEverything();
      var deleted = <int>[];
      CalendarSyncService.deleteEventOverride = (id) async => deleted.add(id);
      addTearDown(() => CalendarSyncService.deleteEventOverride = null);

      await store.actions.settingsActions.removeCalendarSyncEvents();

      expect(deleted, [1]);
      expect((await prefs()).getString('calendarSyncRecords'), '[]');
    });
  });

  group('the inventory', () {
    test('tries every entry even when one fails, and reports the failure',
        () async {
      final ran = <String>[];
      final inventory = LocalDataInventory([
        LocalDataEntry(
          id: 'first',
          category: LocalDataCategory.appOwnedCache,
          deletedBy: const {LocalDataTrigger.deleteData},
          deleteFor: (_) async {
            ran.add('first');
            throw StateError('cannot delete');
          },
        ),
        LocalDataEntry(
          id: 'second',
          category: LocalDataCategory.appOwnedCache,
          deletedBy: const {LocalDataTrigger.deleteData},
          deleteFor: (_) async => ran.add('second'),
        ),
        LocalDataEntry(
          id: 'other',
          category: LocalDataCategory.appOwnedCache,
          deletedBy: const {LocalDataTrigger.removeAccount},
          deleteFor: (_) async => ran.add('other'),
        ),
      ]);

      await expectLater(
          inventory.deleteForAccount(
              LocalDataAccount(scope: scope, storageKey: storageKey),
              LocalDataTrigger.deleteData),
          throwsStateError);

      expect(ran, ['first', 'second']);
    });

    test('lists every place with the data it holds', () {
      expect({
        for (final e in localDataInventory.entries) e.id: e.category
      }, {
        'accountState': LocalDataCategory.appOwnedCache,
        'homeworkSummaryCache': LocalDataCategory.appOwnedCache,
        'classRegisterCache': LocalDataCategory.appOwnedCache,
        'courseMaterialsCache': LocalDataCategory.appOwnedCache,
        'gradeDeadlineOverrides': LocalDataCategory.userCreated,
        'studyData': LocalDataCategory.userCreated,
        'studyFiles': LocalDataCategory.userCreated,
        'studyFileOpenCopies': LocalDataCategory.appOwnedCache,
        'downloads': LocalDataCategory.download,
        'downloadVersions': LocalDataCategory.appOwnedCache,
        'schoolNotificationState': LocalDataCategory.appOwnedCache,
        'calendarSyncRecords': LocalDataCategory.export,
      });
    });

    test('keeps what the user made and downloaded when saving is turned off',
        () {
      for (final entry in localDataInventory.entries) {
        if (entry.deletedBy.contains(LocalDataTrigger.stopSaving)) {
          expect(entry.category, LocalDataCategory.appOwnedCache,
              reason: entry.id);
          expect(entry.gatedByNoDataSaving, isTrue, reason: entry.id);
        }
        if (entry.category == LocalDataCategory.export ||
            entry.category == LocalDataCategory.download) {
          expect(entry.deletedBy, isNot(contains(LocalDataTrigger.deleteData)),
              reason: entry.id);
          expect(entry.deletedBy, isNot(contains(LocalDataTrigger.stopSaving)),
              reason: entry.id);
        }
      }
    });

    test('every cache that is gated is deleted when saving is turned off', () {
      for (final entry in localDataInventory.entries) {
        if (entry.gatedByNoDataSaving) {
          expect(entry.deletedBy, contains(LocalDataTrigger.stopSaving),
              reason: entry.id);
        }
      }
    });
  });

  group('every place that writes to the device is accounted for', () {
    // The expressions that name what each write stores, by file. A write that
    // is not listed here makes this test fail: decide whether it needs an
    // entry in the inventory (data of an account) or is global (settings,
    // markers, credentials), and say so here.
    const inventoryEntries = <String, Set<String>>{
      'lib/page_payload_cache.dart': {'key'},
      'lib/class_register_cache.dart': {'key'},
      'lib/calendar_sync_service.dart': {'_calendarSyncRecordsKey'},
      'lib/middleware/middleware.dart': {
        '_courseMaterialVersionsKeyFor(scope)',
      },
      'lib/ui/days.dart': {'_gradeDeadlinePreferenceStorageKey()'},
    };
    const globalWrites = <String, Set<String>>{
      'lib/analytics_service.dart': {"'lastObservedAppVersion'"},
      'lib/android_widget_service.dart': {'androidWidgetSnapshotStorageKey'},
      'lib/app_clock.dart': {'_preferenceKey'},
      'lib/app_language_controller.dart': {'_appLanguagePreferenceKey'},
      'lib/app_subject_translation_controller.dart': {
        '_subjectTranslationEnabledPreferenceKey',
      },
      'lib/middleware/middleware.dart': {'_legacyStudyPromptedKey'},
      'lib/privacy_consent.dart': {'marker', 'privacyDecisionKey'},
      'lib/product_analytics.dart': {"'analyticsInstallationNamespaceV4'"},
      'lib/settings_persistence_service.dart': {'globalSettingsPreferenceKey'},
      'lib/theme_controller.dart': {
        'accentPreferenceKey',
        'platformOverridePreferenceKey',
        '_followDeviceThemePreferenceKey',
        '_themeBrightnessPreferenceKey',
      },
      'lib/tutorial/tutorial_service.dart': {'seenKey'},
      'lib/ui/days.dart': {'_localReminderAssessmentHintKey'},
    };

    Map<String, Set<String>> writesInLib() {
      final writer = RegExp(
          r'\.set(?:String|Bool|Int|Double|StringList)\(\s*([^,;]+?)\s*,',
          multiLine: true);
      final result = <String, Set<String>>{};
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
              (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))) {
        final text = file.readAsStringSync();
        final path = file.path.replaceAll(r'\', '/');
        for (final match in writer.allMatches(text)) {
          final expression = match.group(1)!.replaceAll(RegExp(r'\s+'), ' ');
          (result[path] ??= <String>{}).add(expression);
        }
      }
      return result;
    }

    test('each preference write is in the inventory or marked global', () {
      final unknown = <String>[];
      writesInLib().forEach((file, expressions) {
        for (final expression in expressions) {
          final known =
              (inventoryEntries[file]?.contains(expression) ?? false) ||
                  (globalWrites[file]?.contains(expression) ?? false);
          if (!known) unknown.add('$file: $expression');
        }
      });
      expect(unknown, isEmpty,
          reason: 'These writes are not classified. Add an entry to '
              'localDataInventory (data of an account) or list them as '
              'global here.');
    });

    test('the classification lists no write that is not there anymore', () {
      final writes = writesInLib();
      final stale = <String>[];
      for (final table in [inventoryEntries, globalWrites]) {
        table.forEach((file, expressions) {
          for (final expression in expressions) {
            if (!(writes[file]?.contains(expression) ?? false)) {
              stale.add('$file: $expression');
            }
          }
        });
      }
      // Keys kept in the table for writes that moved are not an error, but a
      // table that lists nothing real hides new writes.
      expect(stale.length, lessThan(3), reason: stale.join('\n'));
    });

    test('the namespaces the inventory deletes are the ones that are written',
        () {
      final source = File('lib/middleware/middleware.dart').readAsStringSync();
      for (final namespace in [
        "'homeworkSummary:",
        "'classRegisterLessons:",
        "'courseMaterials:",
      ]) {
        expect(source, contains(namespace), reason: namespace);
      }
      final inventory =
          File('lib/middleware/local_data.dart').readAsStringSync();
      for (final namespace in [
        "'homeworkSummary'",
        "'classRegisterLessons'",
        "'courseMaterials'",
        "'gradeDeadlineOverrides'",
      ]) {
        expect(inventory, contains(namespace), reason: namespace);
      }
    });
  });

  group('the texts', () {
    Map<String, dynamic> catalog(String language) =>
        jsonDecode(File('assets/locales/$language.json').readAsStringSync())
            as Map<String, dynamic>;

    // What stays when data is deleted, in each language: downloaded files and
    // entries in the calendar of the device must be named as kept.
    const keptCalendar = {
      'de': 'Gerätekalender',
      'en': 'device calendar',
      'it': 'calendario del dispositivo',
      'lld': 'calender dl aparat',
    };

    for (final language in keptCalendar.keys) {
      test('in $language do not promise to delete exports or downloads', () {
        final texts = catalog(language);
        for (final key in [
          'settings.deleteDataOnLogout.subtitle',
          'settings.storeData.confirm.body',
          'login.removeAccount.body',
        ]) {
          final text = texts[key] as String;
          expect(text, contains(keptCalendar[language]!), reason: key);
        }
        // Signing out and turning saving off keep downloaded files; the
        // removal of an account deletes them and says so.
        final logoutText = texts['settings.deleteDataOnLogout.subtitle'];
        final storeText = texts['settings.storeData.confirm.body'];
        final removeText = texts['login.removeAccount.body'] as String;
        const downloads = {
          'de': 'Heruntergeladene Dateien',
          'en': 'Downloaded files',
          'it': 'file scaricati',
          'lld': 'files desćariés',
        };
        expect((logoutText as String).toLowerCase(),
            contains(downloads[language]!.toLowerCase()));
        expect((storeText as String).toLowerCase(),
            contains(downloads[language]!.toLowerCase()));
        expect(removeText.toLowerCase(),
            contains(downloads[language]!.toLowerCase()));
      });
    }
  });
}
