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

import 'package:dr/i18n/app_language.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appLanguagePreferenceKey = 'appLanguage';

class AppLanguageController {
  AppLanguage _language = AppLanguage.de;

  AppLanguage get language => _language;

  Future<void> load({Locale? fallbackLocale}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(_appLanguagePreferenceKey);
    if (storedCode != null) {
      _language = AppLanguage.fromCode(storedCode);
      return;
    }
    if (fallbackLocale != null) {
      _language = AppLanguage.fromLocale(fallbackLocale);
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    _language = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appLanguagePreferenceKey, language.code);
  }
}

final AppLanguageController appLanguageController = AppLanguageController();
