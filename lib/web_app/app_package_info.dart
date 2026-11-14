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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// The app's name and version, also in the browser.
///
/// In the web build the plugin looks for `version.json` next to the assets,
/// which the deployment moves into a fingerprinted folder, and gives up. The
/// file is still at the root of the web app, so the web build reads it there.
Future<PackageInfo> appPackageInfo({http.Client? client}) async {
  if (!kIsWeb) return PackageInfo.fromPlatform();
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.base.resolve('/version.json'))
        .timeout(const Duration(seconds: 10));
    final data = response.statusCode == 200
        ? jsonDecode(response.body) as Map<String, dynamic>
        : const <String, dynamic>{};
    return PackageInfo(
      appName: data['app_name'] as String? ?? '',
      packageName: data['package_name'] as String? ?? '',
      version: data['version'] as String? ?? '',
      buildNumber: data['build_number'] as String? ?? '',
    );
  } finally {
    if (client == null) c.close();
  }
}
