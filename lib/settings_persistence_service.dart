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

import 'package:dr/app_state.dart';
import 'package:dr/diagnostics_service.dart';
import 'package:dr/privacy_log.dart';
import 'package:dr/serializers.dart';
import 'package:dr/study_data_service.dart';
import 'package:dr/theme/app_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const globalSettingsPreferenceKey = 'globalSettingsState';

class SettingsPersistenceService {
  /// The settings shared by all accounts, without any learning notes.
  ///
  /// The shared blob used to hold the learning notes of every account that
  /// ever signed in on the device. They belong to no account, so nothing that
  /// loads settings gets them; [legacyStudyData] reads them for the one
  /// migration that deals with them.
  Future<SettingsState?> load() async {
    final stored = await _readStored();
    return stored == null ? null : _withoutStudyData(stored);
  }

  /// The learning notes still stored in the shared blob, or null when there
  /// is no blob. Throws [StudyDataUnreadable] for a blob that is there but
  /// cannot be read: it may still hold notes.
  Future<StudyData?> legacyStudyData() async {
    final stored = await _readStored(throwIfUnreadable: true);
    return stored == null ? null : StudyData.fromSettings(stored);
  }

  Future<SettingsState?> _readStored({bool throwIfUnreadable = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(globalSettingsPreferenceKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final deserialized = serializers.deserialize(json.decode(raw) as Object);
      if (deserialized is SettingsState) {
        return migrateSubjectColorsToPalette(deserialized);
      }
    } catch (error, stackTrace) {
      diagnostics.report(error, stackTrace, DiagnosticError.storage);
      privacyLog('technical_operation');
      if (throwIfUnreadable) throw const StudyDataUnreadable();
    }
    return null;
  }

  /// Saves [settings] for all accounts. The learning notes in [settings]
  /// belong to the account that is signed in and are not saved here: whatever
  /// notes the stored blob holds stay exactly as they are until
  /// [dropLegacyStudyData] removes them.
  Future<void> save(SettingsState settings) async {
    final stored = await _readStored();
    final toSave = stored == null
        ? _withoutStudyData(settings)
        : StudyData.fromSettings(stored).applyTo(settings);
    await _write(toSave);
  }

  /// Stores [settings] as they are, learning notes included, when nothing is
  /// stored yet. The notes of an older saved state are not lost this way; they
  /// belong to no account until they are migrated.
  Future<void> adopt(SettingsState settings) async {
    if (await _readStored() != null) return;
    await _write(settings);
  }

  /// Removes the learning notes from the stored blob. Only to be called once
  /// they are safe somewhere else.
  Future<void> dropLegacyStudyData() async {
    final stored = await _readStored();
    if (stored == null) return;
    final cleaned = _withoutStudyData(stored);
    if (cleaned != stored) await _write(cleaned);
  }

  Future<void> _write(SettingsState settings) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (!await prefs.setString(globalSettingsPreferenceKey,
          json.encode(serializers.serialize(settings)))) {
        throw StateError('Settings write failed');
      }
    } catch (e, stack) {
      diagnostics.report(e, stack, DiagnosticError.storage);
      rethrow;
    }
  }
}

SettingsState _withoutStudyData(SettingsState settings) =>
    StudyData.empty.applyTo(settings);

/// Snaps subject colors that were picked freely before the curated palette
/// existed to the closest palette swatch.
SettingsState migrateSubjectColorsToPalette(SettingsState settings) {
  final needsMigration = settings.subjectThemes.values
      .any((theme) => !AppPalette.isSwatch(theme.color));
  if (!needsMigration) return settings;
  return settings.rebuild(
    (b) => b.subjectThemes.updateAllValues(
      (_, theme) => AppPalette.isSwatch(theme.color)
          ? theme
          : theme.rebuild(
              (t) => t.color = AppPalette.nearestSwatch(theme.color).toARGB32(),
            ),
    ),
  );
}

final SettingsPersistenceService settingsPersistenceService =
    SettingsPersistenceService();
