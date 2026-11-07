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

import 'package:dr/i18n/app_localizations.dart';
import 'package:dr/ui/grade_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// How the grades page of the new design writes numbers and dates. The state
/// holds them for the German notation of the register, which stays with Legacy.
class GradesFormat {
  GradesFormat.of(BuildContext context)
      : _l10n = context.l10n,
        _language = Localizations.localeOf(context).languageCode,
        _tag = Localizations.localeOf(context).toLanguageTag();

  final AppLocalizations _l10n;
  final String _language, _tag;

  /// [hundredths] as an average with two decimals, or "/" without a value.
  String average(num? hundredths) => hundredths == null
      ? '/'
      : NumberFormat('0.00', _language).format(hundredths / 100);

  /// The same for a forecast, which is not as exact.
  String estimate(num hundredths) =>
      NumberFormat('0.0', _language).format(hundredths / 100);

  /// A change of an average, always with its sign.
  String change(num hundredths) => NumberFormat('+0.0;-0.0', _language).format(
        hundredths / 100,
      );

  /// A grade as the register writes it, like 7+, or as a decimal.
  String grade(String formatted) => formatted.replaceAll(
        ',',
        NumberFormat('0.0', _language).symbols.DECIMAL_SEP,
      );

  String weight(int percent) =>
      NumberFormat.percentPattern(_language).format(percent / 100);

  String shortDate(DateTime date) => DateFormat.Md(_tag).format(date);

  String longDate(DateTime date) => DateFormat.yMMMd(_tag).format(date);

  /// What the colour of a grade says, for those who cannot see it.
  String? category(num? hundredths) => switch (gradeCategory(hundredths)) {
        GradeCategory.good => _l10n.text('grades.category.good'),
        GradeCategory.satisfactory =>
          _l10n.text('grades.category.satisfactory'),
        GradeCategory.failing => _l10n.text('grades.category.failing'),
        null => null,
      };

  /// [value] with its category, for a screen reader.
  String spoken(String value, num? hundredths) {
    final name = category(hundredths);
    return name == null ? value : '$value, $name';
  }
}

/// The value of an average that the state holds as text, such as 7,64 or /.
double? parseAverageHundredths(String value) {
  final parsed = double.tryParse(value.replaceAll(',', '.'));
  return parsed == null ? null : parsed * 100;
}
