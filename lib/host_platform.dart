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

import 'dart:io' as io show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// `dart:io`'s [io.Platform], safe to call in the web build.
///
/// `dart:io` compiles for the web, but every [io.Platform] getter throws there.
/// In the browser no native operating system is "the host": every `isX` is
/// false, so code written for "none of the native platforms" takes over.
/// Native builds behave exactly as with [io.Platform].
// A namespace keeps the call sites readable (HostPlatform.isAndroid).
// ignore: avoid_classes_with_only_static_members
abstract final class HostPlatform {
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static String get pathSeparator => kIsWeb ? '/' : io.Platform.pathSeparator;
  static Map<String, String> get environment =>
      kIsWeb ? const <String, String>{} : io.Platform.environment;
  static String get version => kIsWeb ? 'web' : io.Platform.version;
}
