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
import 'package:flutter/services.dart';

/// The fonts in `assets/fonts/` (used by the PDF export) and the license
/// file that ships next to each.
///
/// The SIL Open Font License asks that the copyright notice and the license
/// travel with the fonts; listing them on the license page makes them
/// visible, not only present in the app bundle.
const bundledFontLicenses = <String, String>{
  'Noto Sans': 'assets/fonts/OFL.txt',
  'Noto Emoji': 'assets/fonts/NotoEmoji-OFL.txt',
};

/// Adds the licenses of [bundledFontLicenses] to the license page
/// (`showLicensePage`). The files are read only when the page asks.
void registerBundledFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in bundledFontLicenses.entries) {
      yield LicenseEntryWithLineBreaks(
        [entry.key],
        await rootBundle.loadString(entry.value),
      );
    }
  });
}
