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

/// How good a grade is, by the colour the app gives it: red, orange or
/// green. Orange covers 5.50 through 5.75 inclusive, in hundredths.
/// They do not change the passing threshold (6) or any grade calculations.
enum GradeCategory { failing, satisfactory, good }

GradeCategory? gradeCategory(num? hundredths) {
  if (hundredths == null || !hundredths.isFinite || hundredths < 0) return null;
  if (hundredths < 550) return GradeCategory.failing;
  if (hundredths <= 575) return GradeCategory.satisfactory;
  return GradeCategory.good;
}
