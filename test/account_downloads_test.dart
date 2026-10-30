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

import 'package:dio/dio.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/course_materials.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_harness.dart';

const _schoolA = 'https://a.school.example';
const _schoolB = 'https://b.school.example';

class _Wrapper extends Mock implements Wrapper {
  @override
  bool get isRetired => false;
}

CourseMaterialEntry _entry([String lastModified = '2026-10-01 08:00:00']) =>
    CourseMaterialEntry.fromJson({
      'id': 657,
      'courseContentId': 83,
      'type': 'file',
      'file': 'server.pdf',
      'originalName': 'Blatt.pdf',
      'lastmodified': lastModified,
    });

void main() {
  late Directory base;
  late _Wrapper mock;
  late Dio client;
  late Wrapper previousWrapper;
  late List<String> requestedBy;
  late List<String> opened;
  late String signedIn;

  /// Signs in as [user] at [url]: what the next session captures.
  void signInAs(String url, String user) {
    signedIn = '$url|$user';
    when(() => mock.url).thenReturn(url);
    when(() => mock.user).thenReturn(user);
    when(() => mock.baseAddress).thenReturn('$url/v2/');
  }

  String folderOf(String url, String user) =>
      '${base.path}/${AccountScope(url, user).fileId}';

  File fileOf(String url, String user, String name) =>
      File('${folderOf(url, user)}/$name');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    base = await Directory.systemTemp.createTemp('account-downloads-');
    previousWrapper = wrapper;
    mock = _Wrapper();
    wrapper = mock;
    client = Dio();
    requestedBy = [];
    opened = [];
    // Every account gets its own bytes, so a mix-up shows in the content.
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requestedBy.add(signedIn);
      handler.resolve(Response<List<int>>(
        requestOptions: options,
        statusCode: 200,
        data: [37, 80, 68, 70, 45, ...signedIn.codeUnits],
        headers: Headers.fromMap({
          'content-type': ['application/pdf']
        }),
      ));
    }));
    when(() => mock.dio).thenReturn(client);
    when(() => mock.ensureLoggedIn()).thenAnswer((_) async => true);
    when(() => mock.ensureLoggedIn(
          isRetryAfterUnexpectedLogout:
              any(named: 'isRetryAfterUnexpectedLogout'),
          forceRelogin: any(named: 'forceRelogin'),
        )).thenAnswer((_) async => true);
    signInAs(_schoolA, 'max');
    attachmentDownloadDirectoryOverride = () async => base.path;
    courseMaterialPlatformOverride = TargetPlatform.windows;
    courseMaterialFileOpenerOverride = (path) async {
      opened.add(path);
      return OpenResult(type: ResultType.done, message: 'done');
    };
    downloadedFileOpenerOverride = courseMaterialFileOpenerOverride;
    clearRuntimeCaches();
  });

  tearDown(() async {
    wrapper = previousWrapper;
    attachmentDownloadDirectoryOverride = null;
    courseMaterialPlatformOverride = null;
    courseMaterialFileOpenerOverride = null;
    downloadedFileOpenerOverride = null;
    courseMaterialDebugLogsOverride = null;
    client.close(force: true);
    await base.delete(recursive: true);
  });

  for (final (name, otherUrl, otherUser) in [
    ('another user of the same school', _schoolA, 'anna'),
    ('the same user name at another school', _schoolB, 'max'),
  ]) {
    group(name, () {
      test('does not open a course document saved for the first account',
          () async {
        courseMaterialDebugLogsOverride = false;
        expect(await openCourseMaterialEntry(_entry()), isTrue);
        final firstBytes =
            await fileOf(_schoolA, 'max', _entry().uniqueName).readAsBytes();
        expect(requestedBy, ['$_schoolA|max']);

        signInAs(otherUrl, otherUser);
        expect(await openCourseMaterialEntry(_entry()), isTrue);

        // It was downloaded again, and the file that was opened is its own.
        expect(requestedBy, ['$_schoolA|max', '$otherUrl|$otherUser']);
        expect(
            opened.last, fileOf(otherUrl, otherUser, _entry().uniqueName).path);
        expect(opened.last, isNot(opened.first));
        expect(await File(opened.last).readAsBytes(), isNot(firstBytes));
        // The first account's file was not replaced.
        expect(await fileOf(_schoolA, 'max', _entry().uniqueName).readAsBytes(),
            firstBytes);
      });

      test('has no saved document where the first account saved one', () async {
        courseMaterialDebugLogsOverride = false;
        await openCourseMaterialEntry(_entry());
        expect(await canOpenFile(_entry().uniqueName), isTrue);

        signInAs(otherUrl, otherUser);

        expect(await canOpenFile(_entry().uniqueName), isFalse);
      });

      test('keeps its own version list', () async {
        courseMaterialDebugLogsOverride = false;
        await openCourseMaterialEntry(_entry());
        signInAs(otherUrl, otherUser);
        await openCourseMaterialEntry(_entry('2026-10-05 08:00:00'));
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs
            .getKeys()
            .where((key) => key.startsWith('courseMaterialFileVersions'));

        expect(keys, {
          'courseMaterialFileVersions:${AccountScope(_schoolA, 'max').fileId}',
          'courseMaterialFileVersions:'
              '${AccountScope(otherUrl, otherUser).fileId}',
        });
      });

      test('downloads a message, homework or calendar file of its own',
          () async {
        for (final prefix in ['hw_', 'cal_', 'msg_']) {
          expect(
              await downloadFile(
                  '$_schoolA/file', '${prefix}1_Blatt.pdf', const {}),
              isTrue);
        }
        final firstBytes =
            await fileOf(_schoolA, 'max', 'hw_1_Blatt.pdf').readAsBytes();

        signInAs(otherUrl, otherUser);
        for (final prefix in ['hw_', 'cal_', 'msg_']) {
          // Nothing of the first account is there, so nothing is asked about
          // keeping or replacing it, and nothing of it can be opened.
          expect(await canOpenFile('${prefix}1_Blatt.pdf'), isFalse);
          expect(
              await downloadFile(
                  '$otherUrl/file', '${prefix}1_Blatt.pdf', const {}),
              isTrue);
          expect(await canOpenFile('${prefix}1_Blatt.pdf'), isTrue);
        }

        expect(await fileOf(_schoolA, 'max', 'hw_1_Blatt.pdf').readAsBytes(),
            firstBytes);
        expect(
            await fileOf(otherUrl, otherUser, 'hw_1_Blatt.pdf').readAsBytes(),
            isNot(firstBytes));
      });

      test('opens only its own file', () async {
        await downloadFile('$_schoolA/file', 'msg_1_Blatt.pdf', const {});
        signInAs(otherUrl, otherUser);

        // There is nothing saved for this account: whatever the viewer is
        // asked to open, it is not the first account's file.
        await openFile('msg_1_Blatt.pdf');
        expect(opened,
            isNot(contains(fileOf(_schoolA, 'max', 'msg_1_Blatt.pdf').path)));
        expect(await fileOf(otherUrl, otherUser, 'msg_1_Blatt.pdf').exists(),
            isFalse);

        opened.clear();
        await downloadFile('$otherUrl/file', 'msg_1_Blatt.pdf', const {});
        await openFile('msg_1_Blatt.pdf');
        expect(opened, [fileOf(otherUrl, otherUser, 'msg_1_Blatt.pdf').path]);
      });
    });
  }

  test('the first account finds its documents again after a switch back',
      () async {
    courseMaterialDebugLogsOverride = false;
    await openCourseMaterialEntry(_entry());
    signInAs(_schoolB, 'max');
    await openCourseMaterialEntry(_entry());
    requestedBy.clear();

    signInAs(_schoolA, 'max');
    expect(await openCourseMaterialEntry(_entry()), isTrue);

    expect(requestedBy, isEmpty);
    expect(opened.last, fileOf(_schoolA, 'max', _entry().uniqueName).path);
  });

  test('a document saved before accounts had folders is read by no account',
      () async {
    courseMaterialDebugLogsOverride = false;
    final legacy = File('${base.path}/${_entry().uniqueName}')
      ..writeAsBytesSync([1, 2, 3]);
    final legacyMessage = File('${base.path}/msg_1_Blatt.pdf')
      ..writeAsBytesSync([4, 5, 6]);
    // Even an old version record cannot make the old file current.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('courseMaterialFileVersions',
        jsonEncode({_entry().uniqueName: _entry().contentVersion}));

    expect(await canOpenFile(_entry().uniqueName), isFalse);
    expect(await canOpenFile('msg_1_Blatt.pdf'), isFalse);
    expect(await openCourseMaterialEntry(_entry()), isTrue);
    await downloadFile('$_schoolA/file', 'msg_1_Blatt.pdf', const {});

    expect(requestedBy, hasLength(2));
    expect(opened.single, isNot(legacy.path));
    // It stays where it was, unchanged.
    expect(legacy.readAsBytesSync(), [1, 2, 3]);
    expect(legacyMessage.readAsBytesSync(), [4, 5, 6]);
    expect(prefs.getString('courseMaterialFileVersions'), isNotNull);
  });

  test('a folder name cannot be used to reach another folder', () async {
    // The folder name comes from the account, never from the backend.
    for (final name in [
      '../x.pdf',
      '${AccountScope(_schoolB, 'max').fileId}/x'
    ]) {
      expect(await downloadFile('$_schoolA/file', name, const {}), isFalse);
    }
    expect(Directory(folderOf(_schoolB, 'max')).existsSync(), isFalse);
  });
}
