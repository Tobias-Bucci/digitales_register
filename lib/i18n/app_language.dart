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

import 'package:flutter/material.dart';

enum AppLanguage {
  de('de'),
  it('it'),
  lld('lld'),
  en('en');

  const AppLanguage(this.code);

  final String code;

  Locale get locale {
    return switch (this) {
      AppLanguage.de => const Locale('de'),
      AppLanguage.it => const Locale('it'),
      AppLanguage.en => const Locale('en'),
      AppLanguage.lld => const Locale.fromSubtags(
          languageCode: 'de',
          countryCode: 'LLD',
        ),
    };
  }

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.de,
    );
  }

  static AppLanguage fromLocale(Locale locale) {
    if (locale.languageCode == 'de' && locale.countryCode == 'LLD') {
      return AppLanguage.lld;
    }
    return fromCode(locale.languageCode);
  }
}
