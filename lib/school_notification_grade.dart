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

import 'package:dr/dashboard_events.dart'
    show DashboardEventKind, dashboardEventKindOf;
import 'package:dr/data.dart' show Notification;
import 'package:dr/grades/grade_notation.dart' show tryParseFormattedGrade;
import 'package:html/parser.dart' as html;

/// The grade a new-grade entry of the school's feed announces (#153).
///
/// The register writes these entries as its wording followed by three quoted
/// parts, such as `Neue Bewertung "Mathematik" "Schularbeit" "7½"`: the
/// subject, the kind of grade and the grade.
class SchoolNotificationGrade {
  const SchoolNotificationGrade({
    required this.subject,
    required this.kind,
    required this.text,
    this.hundredths,
  });

  final String subject;
  final String kind;

  /// The grade as the register wrote it, such as "7½".
  final String text;

  /// Its value, or null for a short grade the app cannot read, such as "gut",
  /// which is shown as written and without a colour.
  final int? hundredths;
}

/// Any of the quotes the register may use, straight, typographic or angle.
final _quoted = RegExp('["„“”«»]([^"„“”«»]*)["„“”«»]');
final _whitespace = RegExp(r'\s+');

/// Minus signs and dashes that stand for the hyphen of a grade such as 8-.
final _dashes = RegExp('[−–]');

/// The longest grade that is shown as written when the app cannot read it.
const _maxUnreadableLength = 4;

/// The grade of the feed text [text], or null when it has fewer than three
/// quoted parts or no usable grade. The wording around the quotes is ignored,
/// so it does not matter which language the school writes in. With more than
/// three parts, the first is the subject, the last the grade and the others
/// the kind.
SchoolNotificationGrade? parseSchoolNotificationGrade(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final decoded = text.contains('&') ? html.parseFragment(text).text! : text;
  final parts = [
    for (final match in _quoted.allMatches(decoded))
      match.group(1)!.replaceAll(_whitespace, ' ').trim(),
  ];
  if (parts.length < 3) return null;
  final grade = parts.last;
  if (grade.isEmpty) return null;
  final hundredths = tryParseFormattedGrade(grade
      .replaceAll(_whitespace, '')
      .replaceAll('½', '.5')
      .replaceAll(_dashes, '-'));
  if (hundredths == null && grade.length > _maxUnreadableLength) return null;
  return SchoolNotificationGrade(
    subject: parts.first,
    kind: parts.sublist(1, parts.length - 1).join(' '),
    text: grade,
    hundredths: hundredths,
  );
}

/// What [schoolNotificationGradeOf] found, so that each entry is read once.
final _read = Expando<Object>('school notification grade');
const _noGrade = Object();

/// The grade [notification] announces, from its title or, failing that, its
/// second line; null when it is no grade or its text has none. Read once per
/// entry. Reading never depends on the feed, so an entry that was read and
/// left the feed keeps its grade.
SchoolNotificationGrade? schoolNotificationGradeOf(Notification notification) {
  if (dashboardEventKindOf(notification.type) != DashboardEventKind.grade) {
    return null;
  }
  final known = _read[notification];
  if (known != null) {
    return identical(known, _noGrade) ? null : known as SchoolNotificationGrade;
  }
  final grade = parseSchoolNotificationGrade(notification.title) ??
      parseSchoolNotificationGrade(notification.subTitle);
  _read[notification] = grade ?? _noGrade;
  return grade;
}
