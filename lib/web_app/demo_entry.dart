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

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// `/demo`: the web app opens straight into the built-in demo account.
///
/// A link from the website ("try it without an account") lands here. The
/// session is a throwaway one:
///
/// - It signs in to the demo account (school empty, `demo` / `demo`), which
///   runs on local sample data and sends no sign-in request.
/// - It stores nothing in the browser: settings and the saved login live in
///   memory only, so the visitor's own saved accounts are neither read nor
///   touched, and a reload or a new tab starts the normal web app again.
///
/// Native builds never enter it. Normal starts of the web app are unchanged.
// ignore: avoid_classes_with_only_static_members
abstract final class DemoEntry {
  /// The address that starts it.
  static const String path = '/demo';

  static bool _active = false;
  static bool _signInPending = false;

  /// True for the whole session once the web app was opened at [path].
  static bool get active => _active;

  /// The in-memory replacement for the secure storage, while [active].
  static FlutterSecureStorage? get secureStorage => _secureStorage;
  static FlutterSecureStorage? _secureStorage;

  /// Whether [uriPath] is the demo address (`/demo`, `/demo/`, any case).
  static bool isDemoPath(String uriPath) {
    var p = uriPath.toLowerCase();
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p == path;
  }

  /// Call once at start-up, before anything reads storage. Returns whether
  /// the demo session started.
  static bool start(Uri startUri, {bool web = kIsWeb}) {
    if (!web || _active || !isDemoPath(startUri.path)) return false;
    _active = true;
    _signInPending = true;
    // Both stores the app writes to in a browser (localStorage through
    // shared_preferences and flutter_secure_storage) become memory.
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    _secureStorage = MemorySecureStorage();
    return true;
  }

  /// True once: the start-up sign-in should use the demo account instead of
  /// a saved login.
  static bool takeSignIn() {
    final pending = _signInPending;
    _signInPending = false;
    return pending;
  }

  @visibleForTesting
  static void reset() {
    _active = false;
    _signInPending = false;
    _secureStorage = null;
  }
}

/// A [FlutterSecureStorage] that keeps everything in memory, for [DemoEntry].
class MemorySecureStorage extends FlutterSecureStorage {
  MemorySecureStorage();

  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map.of(_values);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.clear();
  }
}
