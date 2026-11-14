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

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Web build only: hands [bytes] to the browser as a download named
/// [fileName]. The browser saves it (or asks where), and opens it from its
/// downloads like any other file. The web app keeps no copy.
///
/// The native app saves documents in its folder and opens them with the
/// system's viewer instead; there is no app folder in the browser.
Future<bool> saveInBrowser(String fileName, List<int> bytes) async {
  if (bytes.isEmpty) return false;
  // The browser needs an extension to pick a type and a viewer.
  final name = RegExp(r'\.[A-Za-z0-9]{1,8}$').hasMatch(fileName)
      ? fileName
      : '$fileName.bin';
  try {
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    return true;
  } catch (_) {
    return false;
  }
}
