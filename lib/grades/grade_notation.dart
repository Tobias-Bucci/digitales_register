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

/// Whether [grade], in hundredths, is a grade of the scale from 0 to 10.
bool isGradeInRange(int grade) {
  return grade >= 0 && grade <= 1000;
}

/// A grade as the register and the grade pages write it, such as "8", "7,5",
/// "8-", "7+" or "7/8", in hundredths; null when it is none of these or lies
/// outside the scale.
int? tryParseFormattedGrade(String grade) {
  bool matchesWholeInput(RegExpMatch? match) {
    return match != null && match.start == 0 && match.end == match.input.length;
  }

  final accurate = RegExp(r"(\d+)(?:[.,](\d{1,2}))?").firstMatch(grade);
  if (matchesWholeInput(accurate)) {
    final major = accurate!.group(1)!;
    final minor = accurate.group(2);
    final majorParsed = int.tryParse(major);
    if (majorParsed == null) {
      return null;
    }
    var minorParsed = minor != null ? int.tryParse(minor) : 0;
    if (minorParsed == null) {
      return null;
    }
    if (minor?.length == 1) {
      // parse .5 as 50/100
      minorParsed *= 10;
    }
    final combinedGrade = majorParsed * 100 + minorParsed;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final less = RegExp(r"(\d+)-").firstMatch(grade);
  if (matchesWholeInput(less)) {
    final lessParsed = int.tryParse(less!.group(1)!);
    if (lessParsed == null) {
      return null;
    }
    final combinedGrade = lessParsed * 100 - 25;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final more = RegExp(r"(\d+)\+").firstMatch(grade);
  if (matchesWholeInput(more)) {
    final moreParsed = int.tryParse(more!.group(1)!);
    if (moreParsed == null) {
      return null;
    }
    final combinedGrade = moreParsed * 100 + 25;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  final between = RegExp(r"(\d+)[-/](\d+)").firstMatch(grade);
  if (matchesWholeInput(between)) {
    final startParsed = int.tryParse(between!.group(1)!);
    if (startParsed == null) {
      return null;
    }
    final endParsed = int.tryParse(between.group(2)!);
    if (endParsed == null) {
      return null;
    }
    if (endParsed != startParsed + 1) {
      return null;
    }
    final combinedGrade = startParsed * 100 + 50;
    if (!isGradeInRange(combinedGrade)) {
      return null;
    }
    return combinedGrade;
  }

  return null;
}
