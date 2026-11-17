// Copyright (C) 2021 Michael Debertol
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

import 'package:dr/app_state.dart';
import 'package:dr/star_rating.dart';
import 'package:dr/util.dart';

/// Reads the [Config] of the signed-in user from the HTML of the register
/// page. The login page, which the server sends with HTTP 200 once the
/// session has expired, is a parse error.
Config parseSchoolConfig(String source) {
  return tryParse(source, (source) {
    if (isSchoolLoginPage(source)) {
      throw const FormatException(
        "Received login redirect page instead of the expected config page.",
      );
    }

    final id = _readUserId(source);
    final fullName = _readFullName(source);
    final imgSource = _readImgSource(source);
    final autoLogout = _readAutoLogoutSeconds(source);
    final currentSemesterMaybe = _readCurrentSemester(source);
    final isStudentOrParent = _readIsStudentOrParent(source);
    return Config(
      (b) => b
        ..userId = id
        ..autoLogoutSeconds = autoLogout
        ..fullName = fullName
        ..imgSource = imgSource
        ..competenceStarsScale = _readCompetenceStarsScale(source)
        ..currentSemesterMaybe = currentSemesterMaybe
        ..isStudentOrParent = isStudentOrParent,
    );
  });
}

int? _readCompetenceStarsScale(String source) {
  // This key is present in the existing register webpage fixture. Do not
  // infer a maximum from observed grades or carry a previous school's scale.
  final matches = RegExp(
    r'''(?:["']?competence_stars_scale["']?)\s*:\s*([^,}\r\n]+)''',
  ).allMatches(source).toList();
  if (matches.length != 1) return null;
  var raw = matches.single.group(1)!.trim();
  if (raw.length >= 2 &&
      ((raw.startsWith('"') && raw.endsWith('"')) ||
          (raw.startsWith("'") && raw.endsWith("'")))) {
    raw = raw.substring(1, raw.length - 1);
  }
  return parseStarScale(raw);
}

bool _isLoginRedirectPage(String source) {
  return RegExp(
    r'^[\s\n]*<script type="text/javascript">\n?\s*window\.location = "https://.+\.digitalesregister.it/v2/login";\n?\s*</script>[\s\n]*$',
  ).hasMatch(source);
}

/// Whether [source] is the school's login page or login redirect script,
/// which the server returns with HTTP 200 once the session has expired.
bool isSchoolLoginPage(String source) {
  return _isLoginRedirectPage(source) ||
      (RegExp(r'<html\b', caseSensitive: false).hasMatch(source) &&
          RegExp(r'<title\b[^>]*>\s*Login\s*</title>', caseSensitive: false)
              .hasMatch(source));
}

String _readAssignmentValue(String source, String key) {
  final marker = "$key=";
  final start = source.indexOf(marker);
  if (start < 0) {
    throw FormatException("Missing '$marker' in config page.");
  }
  final valueStart = start + marker.length;
  final end = source.indexOf(";", valueStart);
  if (end < 0) {
    throw FormatException("Missing ';' after '$marker' in config page.");
  }
  return source.substring(valueStart, end).trim();
}

String _readConfigValue(String source, String key) {
  final marker = "$key: ";
  final start = source.indexOf(marker);
  if (start < 0) {
    throw FormatException("Missing '$marker' in config page.");
  }
  final valueStart = start + marker.length;
  final end = source.indexOf(",", valueStart);
  if (end < 0) {
    throw FormatException("Missing ',' after '$marker' in config page.");
  }
  return source.substring(valueStart, end).trim();
}

String _readRequiredSubstring(
  String source,
  String startMarker,
  String endMarker,
) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw FormatException("Missing '$startMarker' in config page.");
  }
  final valueStart = start + startMarker.length;
  final end = source.indexOf(endMarker, valueStart);
  if (end < 0) {
    throw FormatException(
      "Missing '$endMarker' after '$startMarker' in config page.",
    );
  }
  return source.substring(valueStart, end).trim();
}

bool _readIsStudentOrParent(String source) {
  return !source.contains("var isStudentOrParent=0;");
}

int? _readCurrentSemester(String source) {
  if (source.contains("semesterWechsel=1")) return 2;
  if (source.contains("semesterWechsel=2")) {
    return 1;
  } else {
    return null;
  }
}

int _readAutoLogoutSeconds(String source) {
  return int.parse(_readConfigValue(source, "auto_logout_seconds"));
}

int _readUserId(String source) {
  return int.parse(_readAssignmentValue(source, "currentUserId"));
}

String _readAfterImgId(String source) {
  return source
      .substring(source.indexOf("navigationProfilePicture") +
          "navigationProfilePicture".length)
      .trim();
}

String _readFullName(String source) {
  final afterImgId = _readAfterImgId(source);
  return _readRequiredSubstring(afterImgId, ">", "<");
}

String _readImgSource(String source) {
  final afterImgId = _readAfterImgId(source);
  return _readRequiredSubstring(afterImgId, 'src="', '"');
}
