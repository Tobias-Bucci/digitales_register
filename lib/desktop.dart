// Copyright (C) 2021 Michael Debertol
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

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as secure_storage;
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

// This file contains wrappers to make initial desktop compatibility easier.

bool isDesktop() {
  return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
}

/// flutter_secure_storage puts kSecAttrAccessible into every iOS Keychain
/// query. A class-specific read cannot see an item of another class, and a
/// class-specific write collides with it. Without a class, reads match any
/// item and updates keep the item's class; new items still use Apple's default
/// (when unlocked). The background notification worker upgrades `login` to
/// after-first-unlock, so the UI must not query a fixed class. Other platforms
/// ignore iOS options.
const keychainAnyAccessibility = secure_storage.IOSOptions(accessibility: null);

secure_storage.FlutterSecureStorage getFlutterSecureStorage() {
  if (isDesktop() && !Platform.isWindows) {
    return DesktopSecureStorage();
  } else {
    return const secure_storage.FlutterSecureStorage(
        iOptions: keychainAnyAccessibility);
  }
}

// Uses a different implementation to work on desktop. We cannot switch to
// this impl for every platform because that would break backwards compatibility.
class DesktopSecureStorage extends secure_storage.FlutterSecureStorage {
  Future<Box<String>> hiveBox = getEncryptedBox();
  DesktopSecureStorage();

  /// Becomes true once per installation when Linux has no reachable keyring
  /// and the app falls back to a key file. The UI shows a short hint for it.
  static final keyringFallbackNotice = ValueNotifier<bool>(false);

  // Every instance shares one key lookup so parallel opens cannot create
  // competing keys.
  static Future<Box<String>>? _box;
  static Future<Box<String>> getEncryptedBox() => _box ??= _openEncryptedBox();

  static Future<Box<String>> _openEncryptedBox() async {
    final applicationDocumentDirectory = await getApplicationSupportDirectory();
    final homeDirectory =
        Directory("${applicationDocumentDirectory.path}/RegisterDB");
    if (!await homeDirectory.exists()) {
      await homeDirectory.create();
    }
    Hive.init(homeDirectory.path);
    final keyFile = File("${homeDirectory.path}/database.key");
    final key = await _readKey(homeDirectory, keyFile);
    if (key == null) {
      // The keyring that encrypted the existing database is unreachable right
      // now. Opening that file with a new key would make Hive drop its entries
      // as corrupted, so this session keeps its data in memory only.
      await _noticeKeyringFallback(homeDirectory);
      return Hive.openBox('database', bytes: Uint8List(0));
    }
    return Hive.openBox('database',
        encryptionCipher: HiveAesCipher(base64Decode(key)));
  }

  /// Returns the database key, or null when it is locked in an unreachable
  /// keyring. Only a keyring that answers "not found" gets a new key.
  static Future<String?> _readKey(Directory homeDirectory, File keyFile) async {
    if (await keyFile.exists()) {
      return (await keyFile.readAsString()).trim();
    }
    final BiometricStorageFile keyring;
    String? key;
    try {
      keyring = await BiometricStorage().getStorage(
        "",
        options: StorageFileInitOptions(
          authenticationRequired: false,
        ),
      );
      key = await keyring.read();
    } catch (error) {
      if (!_isKeyringUnavailable(error)) rethrow;
      if (await _hasDatabase(homeDirectory)) return null;
      return _createKeyFile(homeDirectory, keyFile);
    }
    if (key != null) return key;
    key = base64UrlEncode(Hive.generateSecureKey());
    try {
      await keyring.write(key);
    } catch (error) {
      if (!_isKeyringUnavailable(error)) rethrow;
      return _createKeyFile(homeDirectory, keyFile, key: key);
    }
    return key;
  }

  /// Linux desktops without a Secret Service (e.g. minimal setups or a
  /// Raspberry Pi) report D-Bus errors such as ServiceUnknown here.
  static bool _isKeyringUnavailable(Object error) =>
      Platform.isLinux && (error is PlatformException || error is AuthException);

  static Future<bool> _hasDatabase(Directory homeDirectory) =>
      File("${homeDirectory.path}/database.hive").exists();

  /// Stores the key next to the database, readable by the user only.
  static Future<String?> _createKeyFile(Directory homeDirectory, File keyFile,
      {String? key}) async {
    key ??= base64UrlEncode(Hive.generateSecureKey());
    final temporary = File("${keyFile.path}.tmp");
    await temporary.writeAsString(key, flush: true);
    final chmod = await Process.run('chmod', ['600', temporary.path]);
    if (chmod.exitCode != 0) {
      await temporary.delete();
      return null;
    }
    await temporary.rename(keyFile.path);
    await _noticeKeyringFallback(homeDirectory);
    return key;
  }

  static Future<void> _noticeKeyringFallback(Directory homeDirectory) async {
    final marker = File("${homeDirectory.path}/keyring-notice-shown");
    if (await marker.exists()) return;
    await marker.create();
    keyringFallbackNotice.value = true;
  }

  @override
  Future<void> delete({
    required String key,
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    await (await hiveBox).delete(key);
  }

  @override
  Future<void> deleteAll({
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    await (await hiveBox).clear();
  }

  @override
  Future<String?> read({
    required String key,
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).get(key);
  }

  @override
  Future<Map<String, String>> readAll({
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).toMap() as Map<String, String>;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).put(key, value!);
  }

  @override
  Future<bool> containsKey({
    required String key,
    secure_storage.AppleOptions? iOptions,
    secure_storage.AndroidOptions? aOptions,
    secure_storage.LinuxOptions? lOptions,
    secure_storage.AppleOptions? mOptions,
    secure_storage.WindowsOptions? wOptions,
    secure_storage.WebOptions? webOptions,
  }) async {
    return (await hiveBox).containsKey(key);
  }

  @override
  secure_storage.AndroidOptions get aOptions => throw UnimplementedError();

  @override
  secure_storage.IOSOptions get iOptions => throw UnimplementedError();

  @override
  secure_storage.LinuxOptions get lOptions => throw UnimplementedError();

  @override
  secure_storage.AppleOptions get mOptions => throw UnimplementedError();

  @override
  secure_storage.WindowsOptions get wOptions => throw UnimplementedError();

  @override
  secure_storage.WebOptions get webOptions => throw UnimplementedError();
}
