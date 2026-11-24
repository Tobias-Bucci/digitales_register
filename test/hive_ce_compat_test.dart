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

// #170: hive was replaced by hive_ce. The files in test/fixtures/hive_v2 were
// written by hive 2.2.3, encrypted like the desktop credential store
// (`database`) and the notification history (lazy box). hive_ce must read
// them unchanged, or an update would lose saved sign-ins on macOS and Linux.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

final _key = base64Decode('q2s9Zr5m0b0yQm4n1d1o5bKZkQ6q8rJ0T8b2e3m6a1c=');

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_v2_');
    for (final file in Directory('test/fixtures/hive_v2').listSync()) {
      if (file is File) {
        await file.copy('${dir.path}/${file.uri.pathSegments.last}');
      }
    }
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('the encrypted credential box of hive 2 opens with its key', () async {
    final box = await Hive.openBox<String>('database',
        encryptionCipher: HiveAesCipher(_key));
    expect(box.get('login'),
        '{"user":"max","pass":"secret","url":"https://a.example"}');
    expect(box.get('state:max'), 'saved state ä ö ü');

    // Writing and reading again keeps the old entries.
    await box.put('state:anna', 'new');
    await box.close();
    final reopened = await Hive.openBox<String>('database',
        encryptionCipher: HiveAesCipher(_key));
    expect(reopened.keys, containsAll(['login', 'state:max', 'state:anna']));
  });

  test('the lazy notification history of hive 2 opens with its key', () async {
    final box = await Hive.openLazyBox<String>('school_notification_history_v1',
        encryptionCipher: HiveAesCipher(_key));
    expect(await box.get('entry-1'), '{"title":"Neue Note"}');
    expect(await box.get('entry-2'), '{"title":"Neue Nachricht"}');
  });
}
