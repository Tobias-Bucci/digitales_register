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

// One release ships the version of pubspec.yaml on every platform
// (RELEASE_CHECKLIST.md). The Apple projects must take it from Flutter's
// build variables instead of a number typed into the project.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final project in [
    'ios/Runner.xcodeproj/project.pbxproj',
    'macos/Runner.xcodeproj/project.pbxproj',
  ]) {
    test('$project takes version and build number from pubspec.yaml', () {
      final text = File(project).readAsStringSync();
      final marketing = RegExp('MARKETING_VERSION = ([^;]+);')
          .allMatches(text)
          .map((m) => m.group(1))
          .toList();
      final build = RegExp('CURRENT_PROJECT_VERSION = ([^;]+);')
          .allMatches(text)
          .map((m) => m.group(1))
          .toList();

      expect(marketing, isNotEmpty);
      expect(build, isNotEmpty);
      expect(marketing, everyElement(r'"$(FLUTTER_BUILD_NAME)"'));
      expect(build, everyElement(r'"$(FLUTTER_BUILD_NUMBER)"'));
    });
  }
}
