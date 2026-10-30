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
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dr/account_scope.dart';
import 'package:dr/assessment_attachments.dart';
import 'package:dr/settings_persistence_service.dart';
import 'package:dr/study_data_service.dart';
import 'package:dr/util.dart';
import 'package:flutter/foundation.dart';

/// Where the migration of the learning notes that older versions kept for all
/// accounts stands.
enum StudyMigrationStatus {
  /// Nothing is left to migrate.
  done,

  /// The notes are safe in the quarantine document. No account reads it; the
  /// user decides which account gets them, or that nobody does.
  quarantined,
}

/// What the quarantine holds, as numbers only. Content and file names never
/// leave the quarantine except into the account the user chooses.
@immutable
class LegacyStudySummary {
  const LegacyStudySummary(
      {required this.exams, required this.notes, required this.files});

  final int exams;
  final int notes;
  final int files;
}

/// What assigning the quarantine to an account did.
@immutable
class StudyAssignOutcome {
  const StudyAssignOutcome({
    required this.moved,
    required this.remaining,
  });

  /// What now belongs to the account.
  final StudyData moved;

  /// What stays in the quarantine because the account has an entry of its own
  /// for it. Empty when the quarantine is gone.
  final StudyData remaining;
}

const studyDataLegacyKey = 'study-data-v1-legacy';
const studyDataMigrationMarkerKey = 'study-data-migration-v1';

/// Moves the learning notes that older versions stored in the settings shared
/// by all accounts out of there, without ever deciding whose they are.
///
/// 1. At the first start they are copied unchanged into a quarantine
///    document. Only when that copy has been read back and compared, the
///    marker says `quarantined`, and only then they are removed from the
///    shared settings. Every step can be repeated; a failed or interrupted
///    run leaves the notes where they were, and a read that fails sets
///    nothing and is tried again at the next start.
/// 2. No account reads the quarantine. The user can assign it to the account
///    that is signed in (entries the account already has are kept, never
///    replaced) or discard it after a second confirmation.
/// 3. A file is deleted only after its copy has been checked, and the entry
///    that pointed to it is out of the quarantine.
class StudyDataMigration {
  StudyDataMigration({required this.service, required this.settings});

  final StudyDataService service;
  final SettingsPersistenceService settings;

  /// Called before each step of a run; tests make a run stop here.
  @visibleForTesting
  Future<void> Function(String step)? onStep;

  Future<void> _step(String name) async => await onStep?.call(name);

  // --- marker and quarantine document ---

  Future<StudyMigrationStatus?> status() async {
    final raw = await service.read(studyDataMigrationMarkerKey);
    return switch (raw) {
      'done' => StudyMigrationStatus.done,
      'quarantined' => StudyMigrationStatus.quarantined,
      _ => null,
    };
  }

  Future<void> _writeMarker(StudyMigrationStatus status) async {
    await service.write(studyDataMigrationMarkerKey, status.name);
    if (await service.read(studyDataMigrationMarkerKey) != status.name) {
      throw const StudyDataUnreadable();
    }
  }

  /// The quarantine document, or null when there is none.
  Future<StudyData?> readQuarantine() async {
    final raw = await service.read(studyDataLegacyKey);
    return raw == null ? null : StudyData.decode(raw);
  }

  Future<void> _writeQuarantine(StudyData data) async {
    await service.write(studyDataLegacyKey, data.encode());
    final back = await readQuarantine();
    if (back == null || back != data) throw const StudyDataUnreadable();
  }

  // --- first run ---

  /// Brings the notes of the shared settings into the quarantine, once.
  ///
  /// Returns null when the migration had to be postponed. Throws
  /// [StudyDataUnreadable] when something it needs cannot be read; nothing is
  /// changed then, and the next start tries again.
  Future<StudyMigrationStatus?> ensureQuarantined() async {
    final marker = await status();
    if (marker == StudyMigrationStatus.done) return marker;
    if (marker == StudyMigrationStatus.quarantined) {
      return _tidyQuarantine();
    }

    await _step('read-shared');
    final shared = await settings.legacyStudyData();
    if (shared == null || shared.isEmpty) {
      await _step('write-marker-done');
      await _writeMarker(StudyMigrationStatus.done);
      return StudyMigrationStatus.done;
    }

    // An earlier run may have stopped after writing the document.
    final earlier = await readQuarantine();
    final document = earlier == null ? shared : earlier.withMissingFrom(shared);
    await _step('write-quarantine');
    await _writeQuarantine(document);
    await _step('write-marker');
    await _writeMarker(StudyMigrationStatus.quarantined);
    return _tidyQuarantine();
  }

  /// With the marker set: removes the notes from the shared settings once the
  /// quarantine is known to hold all of them, and closes an empty quarantine.
  Future<StudyMigrationStatus> _tidyQuarantine() async {
    final quarantine = await readQuarantine();
    final shared = await settings.legacyStudyData();
    final hasShared = shared != null && !shared.isEmpty;
    if (quarantine == null || quarantine.isEmpty) {
      if (hasShared) {
        // The settings still hold notes that the quarantine does not: keep
        // them safe again instead of closing the migration.
        await _step('restore-quarantine');
        await _writeQuarantine(shared);
        return StudyMigrationStatus.quarantined;
      }
      await _finish();
      return StudyMigrationStatus.done;
    }
    if (hasShared && quarantine.contains(shared)) {
      await _step('drop-shared');
      await settings.dropLegacyStudyData();
    }
    return StudyMigrationStatus.quarantined;
  }

  Future<void> _finish() async {
    // Whatever the shared settings still hold is in the accounts by now or
    // was discarded by the user.
    await _step('drop-shared-final');
    await settings.dropLegacyStudyData();
    await _step('delete-quarantine');
    await service.deleteKey(studyDataLegacyKey);
    await _step('write-marker-final');
    await _writeMarker(StudyMigrationStatus.done);
  }

  // --- what is left ---

  /// Numbers for the messages, or null when nothing is left in quarantine.
  Future<LegacyStudySummary?> summary() async {
    if (await status() != StudyMigrationStatus.quarantined) return null;
    final quarantine = await readQuarantine();
    if (quarantine == null || quarantine.isEmpty) return null;
    return LegacyStudySummary(
      exams: quarantine.keys.length,
      notes: quarantine.noteCount,
      files: quarantine.fileCount,
    );
  }

  // --- assign ---

  /// Gives the quarantined notes to [scope]. [current] is what the account has
  /// in the app right now; entries it has are never replaced.
  ///
  /// Order: copy the files and check the copies, write the account's
  /// document and read it back, take the moved entries out of the quarantine,
  /// and only then delete the files that were moved. Whatever stops the run,
  /// every note and every file is still in the quarantine or in the account.
  Future<StudyAssignOutcome> assign(
    AccountScope scope, {
    StudyData current = StudyData.empty,
  }) async {
    if (await status() != StudyMigrationStatus.quarantined) {
      return const StudyAssignOutcome(
          moved: StudyData.empty, remaining: StudyData.empty);
    }
    final quarantine = await readQuarantine();
    if (quarantine == null || quarantine.isEmpty) {
      await _finish();
      return const StudyAssignOutcome(
          moved: StudyData.empty, remaining: StudyData.empty);
    }
    final account = (await service.load(scope)).withMissingFrom(current);

    await _step('copy-files');
    final copies = <String, String>{};
    final rewritten = await _rewriteAttachments(
        quarantine.attachments, scope, copies);
    final candidates = StudyData(
      progress: quarantine.progress,
      notes: quarantine.notes,
      attachments: rewritten,
      phases: quarantine.phases,
    );

    final merged = account.withMissingFrom(candidates);
    await _step('write-account');
    await service.save(scope, merged);
    final back = await service.load(scope);
    if (back != merged) throw const StudyDataUnreadable();

    // What the account holds with the value it had in the quarantine is done
    // with, whether this run moved it or an earlier one.
    final done = StudyData(
      progress: _equalEntries(merged.progress, candidates.progress),
      notes: _equalEntries(merged.notes, candidates.notes),
      attachments: _equalEntries(merged.attachments, candidates.attachments),
      phases: _equalEntries(merged.phases, candidates.phases),
    );
    final remaining = StudyData(
      progress: _unmoved(quarantine.progress, merged.progress),
      notes: _unmoved(quarantine.notes, merged.notes),
      attachments: _unmoved(quarantine.attachments, merged.attachments,
          rewritten: candidates.attachments),
      phases: _unmoved(quarantine.phases, merged.phases),
    );

    await _step('shrink-quarantine');
    if (remaining.isEmpty) {
      await _finish();
    } else {
      await _writeQuarantine(remaining);
    }

    await _step('delete-files');
    final stillNeeded = _legacyFilePaths(remaining.attachments);
    for (final entry in copies.entries) {
      if (!stillNeeded.contains(entry.key)) {
        await _deleteQuietly(File(entry.key));
      }
    }
    return StudyAssignOutcome(moved: done, remaining: remaining);
  }

  /// Entries of [part] that [whole] holds with the same value.
  static Map<String, String> _equalEntries(
          Map<String, String> whole, Map<String, String> part) =>
      {
        for (final entry in part.entries)
          if (whole[entry.key] == entry.value) entry.key: entry.value,
      };

  /// Entries of [quarantined] that the account has not taken over: it has
  /// none, or one of its own with another value. For attachments the value
  /// the entry would have after its files were copied is what counts.
  static Map<String, String> _unmoved(
    Map<String, String> quarantined,
    Map<String, String> account, {
    Map<String, String>? rewritten,
  }) =>
      {
        for (final entry in quarantined.entries)
          if (account[entry.key] != (rewritten ?? quarantined)[entry.key])
            entry.key: entry.value,
      };

  // --- files ---

  /// The attachment metadata with every file of the shared folder copied into
  /// the folder of [scope]. [copies] collects source path -> verified copy.
  /// A file that cannot be copied keeps its old absolute path and so stays
  /// where it is.
  Future<Map<String, String>> _rewriteAttachments(
    Map<String, String> attachments,
    AccountScope scope,
    Map<String, String> copies,
  ) async {
    final result = <String, String>{};
    for (final entry in attachments.entries) {
      final files = decodeAssessmentAttachments(entry.value);
      if (files.isEmpty) {
        result[entry.key] = entry.value;
        continue;
      }
      final rewritten = <AssessmentAttachment>[];
      for (final file in files) {
        final name = await _copyIntoAccount(file.path, scope, copies);
        rewritten.add(name == null
            ? file
            : AssessmentAttachment(name: file.name, path: name));
      }
      result[entry.key] = encodeAssessmentAttachments(rewritten);
    }
    return result;
  }

  /// Copies the file at [path] into the folder of [scope] and returns its
  /// name there, or null if it is not a regular file loose in the shared
  /// folder or the copy cannot be verified.
  Future<String?> _copyIntoAccount(
    String path,
    AccountScope scope,
    Map<String, String> copies,
  ) async {
    final source = File(path);
    final root = await assessmentAttachmentsRoot();
    try {
      if (!await _isLooseFileOf(source, root)) return null;
      final name = source.uri.pathSegments.last;
      if (!isSafeFileNameSegment(name)) return null;
      final folder = await assessmentAttachmentFolder(scope);
      await folder.create(recursive: true);
      final sourceHash = await _hash(source);
      for (var attempt = 0; attempt < 50; attempt++) {
        final candidate = attempt == 0 ? name : 'm${attempt}_$name';
        final target = File('${folder.path}${Platform.pathSeparator}$candidate');
        if (await FileSystemEntity.isLink(target.path)) continue;
        if (await target.exists()) {
          // An earlier run copied it already.
          if (await _hash(target) == sourceHash) {
            copies[source.path] = target.path;
            return candidate;
          }
          continue;
        }
        final partial = File('${target.path}.part');
        await source.copy(partial.path);
        await partial.rename(target.path);
        if (await _hash(target) != sourceHash) {
          await _deleteQuietly(target);
          return null;
        }
        copies[source.path] = target.path;
        return candidate;
      }
    } catch (_) {
      // Not copied: the file stays where it is and the entry keeps its path.
    }
    return null;
  }

  Future<bool> _isLooseFileOf(File file, Directory root) async {
    if (!await root.exists() ||
        await FileSystemEntity.isLink(file.path) ||
        !await file.exists()) {
      return false;
    }
    final parent = await Directory(file.parent.path).resolveSymbolicLinks();
    return parent == await root.resolveSymbolicLinks();
  }

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Set<String> _legacyFilePaths(Map<String, String> attachments) => {
        for (final value in attachments.values)
          for (final file in decodeAssessmentAttachments(value))
            if (!isSafeFileNameSegment(file.path)) file.path,
      };

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists() && !await FileSystemEntity.isLink(file.path)) {
        await file.delete();
      }
    } catch (_) {
      // A leftover file is not data loss; it is not referenced anymore.
    }
  }

  // --- discard ---

  /// Deletes the quarantine and the files it refers to. The user has been
  /// asked twice before this is called.
  Future<void> discard() async {
    if (await status() != StudyMigrationStatus.quarantined) return;
    final quarantine = await readQuarantine();
    final root = await assessmentAttachmentsRoot();
    if (quarantine != null) {
      await _step('delete-quarantined-files');
      for (final path in _legacyFilePaths(quarantine.attachments)) {
        final file = File(path);
        // Only files that lie loose in the shared folder were ours to keep.
        if (await _isLooseFileOf(file, root)) await _deleteQuietly(file);
      }
    }
    await _finish();
  }
}
