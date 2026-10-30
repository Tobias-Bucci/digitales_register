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

import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The learning notes a student keeps for the exams of one account: progress,
/// notes, attached files (as JSON metadata) and edited study phases, each by
/// the stable id of the exam.
@immutable
class StudyData {
  const StudyData({
    this.progress = const <String, String>{},
    this.notes = const <String, String>{},
    this.attachments = const <String, String>{},
    this.phases = const <String, String>{},
  });

  static const StudyData empty = StudyData();

  final Map<String, String> progress;
  final Map<String, String> notes;
  final Map<String, String> attachments;
  final Map<String, String> phases;

  factory StudyData.fromSettings(SettingsState settings) => StudyData(
        progress: settings.assessmentStudyProgress.toMap(),
        notes: settings.assessmentStudyNotes.toMap(),
        attachments: settings.assessmentStudyAttachments.toMap(),
        phases: settings.assessmentStudyPhases.toMap(),
      );

  /// [settings] with exactly this data as its learning notes.
  SettingsState applyTo(SettingsState settings) => settings.rebuild(
        (b) => b
          ..assessmentStudyProgress = MapBuilder<String, String>(progress)
          ..assessmentStudyNotes = MapBuilder<String, String>(notes)
          ..assessmentStudyAttachments = MapBuilder<String, String>(attachments)
          ..assessmentStudyPhases = MapBuilder<String, String>(phases),
      );

  bool get isEmpty =>
      progress.isEmpty &&
      notes.isEmpty &&
      attachments.isEmpty &&
      phases.isEmpty;

  /// Exams that have notes, files, progress or a plan.
  Set<String> get keys =>
      {...progress.keys, ...notes.keys, ...attachments.keys, ...phases.keys};

  /// How many notes the data holds, for messages that must not show content.
  int get noteCount => notes.length;

  /// How many files the data holds, for messages that must not show names.
  int get fileCount {
    var count = 0;
    for (final encoded in attachments.values) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) count += decoded.length;
      } catch (_) {
        // Metadata that cannot be read still stands for a file.
        count++;
      }
    }
    return count;
  }

  static Map<String, String> _withMissing(
          Map<String, String> base, Map<String, String> other) =>
      {...other, ...base};

  /// This data plus every entry of [other] this has no entry for. Nothing that
  /// this holds is replaced.
  StudyData withMissingFrom(StudyData other) => StudyData(
        progress: _withMissing(progress, other.progress),
        notes: _withMissing(notes, other.notes),
        attachments: _withMissing(attachments, other.attachments),
        phases: _withMissing(phases, other.phases),
      );

  static bool _holds(Map<String, String> whole, Map<String, String> part) =>
      part.entries.every((entry) => whole[entry.key] == entry.value);

  /// Whether every entry of [other] is in this, with the same value.
  bool contains(StudyData other) =>
      _holds(progress, other.progress) &&
      _holds(notes, other.notes) &&
      _holds(attachments, other.attachments) &&
      _holds(phases, other.phases);

  static Map<String, String> _without(
          Map<String, String> whole, Map<String, String> part) =>
      {
        for (final entry in whole.entries)
          if (part[entry.key] != entry.value) entry.key: entry.value,
      };

  /// This data without the entries that [other] holds with the same value.
  StudyData without(StudyData other) => StudyData(
        progress: _without(progress, other.progress),
        notes: _without(notes, other.notes),
        attachments: _without(attachments, other.attachments),
        phases: _without(phases, other.phases),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'progress': progress,
        'notes': notes,
        'attachments': attachments,
        'phases': phases,
      };

  String encode() => jsonEncode(toJson());

  /// Throws a [StudyDataCorrupt] for anything that is not version 1 data.
  factory StudyData.decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) {
        throw const FormatException('Unknown study data format');
      }
      Map<String, String> readMap(String name) {
        final value = decoded[name];
        if (value == null) return const <String, String>{};
        if (value is! Map) throw FormatException('$name is not a map');
        for (final entry in value.entries) {
          if (entry.key is! String || entry.value is! String) {
            throw FormatException('$name holds a foreign entry');
          }
        }
        return value.cast<String, String>().map(MapEntry.new);
      }

      return StudyData(
        progress: readMap('progress'),
        notes: readMap('notes'),
        attachments: readMap('attachments'),
        phases: readMap('phases'),
      );
    } catch (_) {
      throw const StudyDataCorrupt();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StudyData &&
      _mapEquals(progress, other.progress) &&
      _mapEquals(notes, other.notes) &&
      _mapEquals(attachments, other.attachments) &&
      _mapEquals(phases, other.phases);

  @override
  int get hashCode => Object.hash(progress.length, notes.length,
      attachments.length, phases.length, keys.length);
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Saved study data could not be read. It is kept as it is: a failed read does
/// not prove the data is gone, so nothing may be written over it.
class StudyDataUnreadable implements Exception {
  const StudyDataUnreadable();

  @override
  String toString() => 'StudyDataUnreadable';
}

/// Saved study data is there but is not in a format this version understands.
class StudyDataCorrupt extends StudyDataUnreadable {
  const StudyDataCorrupt();

  @override
  String toString() => 'StudyDataCorrupt';
}

/// The secure-storage key of the study data of one account.
String studyDataKeyFor(AccountScope scope) => 'study-data-v1-${scope.fileId}';

/// Keeps every account's study data in a document of its own in the secure
/// storage, apart from the settings that are shared by all accounts. Writes
/// that must stay in order with deletions go through the persistence queue of
/// the caller.
class StudyDataService {
  StudyDataService({required this.storage});

  final FlutterSecureStorage Function() storage;

  /// Waited before the one retry of a failed read.
  @visibleForTesting
  Duration retryDelay = const Duration(milliseconds: 200);

  /// Reads [key]. A failed read is tried once more and then reported as
  /// [StudyDataUnreadable]; it is never mistaken for missing data.
  Future<String?> read(String key) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await storage().read(key: key);
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(retryDelay);
          continue;
        }
        throw const StudyDataUnreadable();
      }
    }
  }

  Future<void> write(String key, String value) =>
      storage().write(key: key, value: value);

  Future<void> deleteKey(String key) => storage().delete(key: key);

  /// The study data of [scope]; empty when none was saved yet. Throws
  /// [StudyDataUnreadable] when the saved data cannot be read.
  Future<StudyData> load(AccountScope scope) async {
    final raw = await read(studyDataKeyFor(scope));
    return raw == null ? StudyData.empty : StudyData.decode(raw);
  }

  Future<void> save(AccountScope scope, StudyData data) =>
      write(studyDataKeyFor(scope), data.encode());

  Future<void> delete(AccountScope scope) => deleteKey(studyDataKeyFor(scope));
}
