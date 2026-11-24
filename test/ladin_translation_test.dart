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

// #163: a Ladin text that equals the German one is usually a string nobody
// translated. Every such key must be listed below, either as the same in
// both languages or as waiting for a native speaker, so a new German text in
// lld.json fails here instead of reaching Ladin users.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Words and formats that are the same in German and Ladin.
const _sameInBothLanguages = {
  'dashboard.dayHeading',
  'dashboard.dayHeading.relative',
  'dashboard.filter',
  'dashboard.test',
  'dashboard.title',
  'export.csv',
  'export.field.semester',
  'export.pdf',
  'messages.archived.short',
  'notifications.sourceApp',
  'palette.accent.teal',
  'palette.group.standard',
  'palette.swatch.teal',
  'profile.title',
  'reminders.mensa.urlHint',
  'schoolNotifications.line.described',
  'schoolNotifications.line.gradeChanged',
  'schoolNotifications.line.gradeNew',
  'schoolNotifications.line.message',
  'schoolTerm.minus',
  'schoolTerm.test',
  'settings.about.version',
  'settings.demo.section',
  'settings.design.legacy',
  'settings.section.profile',
  'settings.theme.amoled',
  'sidebar.dashboard',
  'sidebar.profile',
  'tutorial.settings.title',
};

/// Still German in lld.json and waiting for a native speaker (#163). Remove a
/// key once it is translated.
const _awaitingLadinTranslation = {
  'dashboard.customize.absenceCount',
  'dashboard.customize.empty',
  'dashboard.customize.hint',
  'dashboard.customize.loading',
  'dashboard.customize.offline',
  'dashboard.customize.remove',
  'dashboard.customize.reorder',
  'dashboard.customize.reset',
  'dashboard.customize.title',
  'dashboard.customize.unavailable',
  'dashboard.customize.widthAutomatic',
  'dashboard.customize.widthFull',
  'dashboard.customize.widthHalf',
  'dashboard.customize.widthHint',
  'grades.forecast.stable',
  'privacyCategory.diagnostics.title',
  'privacyCategory.usage.title',
  'privacyConsent.cancel',
  'privacyConsent.customize',
  'privacyConsent.save',
  'privacyDetails.revocation.title',
  'privacyDetails.school.title',
  'privacySettings.disabled',
  'privacySettings.enabled',
};

Map<String, dynamic> _catalog(String language) =>
    jsonDecode(File('assets/locales/$language.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final german = _catalog('de');
  final ladin = _catalog('lld');
  final equal = {
    for (final key in german.keys)
      if (ladin[key] == german[key]) key,
  };

  test('no new Ladin text is still German', () {
    final unexplained = equal
        .difference(_sameInBothLanguages)
        .difference(_awaitingLadinTranslation);
    expect(unexplained, isEmpty,
        reason: 'Translate these keys in lld.json, or list them above if '
            'German and Ladin really write them the same.');
  });

  test('the lists name only keys that are still the same', () {
    expect(
        _sameInBothLanguages.intersection(_awaitingLadinTranslation), isEmpty);
    expect(_awaitingLadinTranslation.difference(equal), isEmpty,
        reason: 'Translated: remove these keys from the list.');
    expect(_sameInBothLanguages.difference(equal), isEmpty,
        reason: 'No longer the same: remove these keys from the list.');
  });
}
