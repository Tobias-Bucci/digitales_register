import 'dart:convert';
import 'dart:io';

import 'package:dr/account_scope.dart';
import 'package:dr/privacy_log.dart';
import 'package:dr/util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata only; file payloads remain in the app's private local storage.
///
/// [path] is the bare file name inside the folder of the account that owns the
/// attachment. Attachments saved by older versions have the absolute path of a
/// file that lies directly in the shared attachment folder instead.
class AssessmentAttachment {
  const AssessmentAttachment({required this.name, required this.path});
  final String name;
  final String path;

  Map<String, String> toJson() => {'name': name, 'path': path};

  static AssessmentAttachment? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final path = value['path'];
    if (name is! String || path is! String || name.isEmpty || path.isEmpty) {
      return null;
    }
    return AssessmentAttachment(name: name, path: path);
  }
}

List<AssessmentAttachment> decodeAssessmentAttachments(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return const [];
    return decoded
        .map(AssessmentAttachment.fromJson)
        .whereType<AssessmentAttachment>()
        .toList();
  } catch (_) {
    return const [];
  }
}

String encodeAssessmentAttachments(Iterable<AssessmentAttachment> files) =>
    jsonEncode(files.map((file) => file.toJson()).toList(growable: false));

/// Replaces the attachment folder in tests.
@visibleForTesting
Future<Directory> Function()? assessmentAttachmentsRootOverride;

/// The folder the attachments of all accounts are kept in: one folder per
/// account, and, from older versions, files that lie loose in it.
Future<Directory> assessmentAttachmentsRoot() async {
  final override = assessmentAttachmentsRootOverride;
  if (override != null) return override();
  final root = await getApplicationSupportDirectory();
  return Directory(
      '${root.path}${Platform.pathSeparator}assessment_attachments');
}

/// The folder of the attachments of one account. Files of other accounts, and
/// those older versions kept loose in the shared folder, are not in it.
Future<Directory> assessmentAttachmentFolder(AccountScope scope) async {
  final root = await assessmentAttachmentsRoot();
  return Directory('${root.path}${Platform.pathSeparator}${scope.fileId}');
}

final _absolutePath = RegExp(r'^([\\/]|[A-Za-z]:[\\/])');

bool _isAbsolutePath(String path) => _absolutePath.hasMatch(path);

/// The file an attachment of [scope] is stored in, or null when its name does
/// not lead to a plain file of the account's folder.
Future<File?> resolveAssessmentAttachmentFile(
    AssessmentAttachment attachment, AccountScope scope) async {
  if (!isSafeFileNameSegment(attachment.path)) {
    // Saved by an older version: an absolute path. Anything else that is not
    // a plain file name is not a file of ours.
    return _isAbsolutePath(attachment.path) ? File(attachment.path) : null;
  }
  final folder = await assessmentAttachmentFolder(scope);
  if (await FileSystemEntity.isLink(folder.path)) return null;
  final file =
      File('${folder.path}${Platform.pathSeparator}${attachment.path}');
  if (await FileSystemEntity.isLink(file.path)) return null;
  return file;
}

/// Copies the file the user picks into the attachment folder of [scope].
Future<AssessmentAttachment?> pickAndStoreAssessmentAttachment(
    AccountScope scope) async {
  final result = await FilePicker.pickFiles();
  if (result == null || result.files.isEmpty) return null;
  final selected = result.files.single;
  final name = selected.name.trim();
  if (name.isEmpty) return null;
  final folder = await assessmentAttachmentFolder(scope);
  await folder.create(recursive: true);
  final safeName = name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  final storedName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';
  final destination =
      File('${folder.path}${Platform.pathSeparator}$storedName');
  final bytes = selected.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    await destination.writeAsBytes(bytes, flush: true);
  } else if (selected.path != null && selected.path!.isNotEmpty) {
    await File(selected.path!).copy(destination.path);
  } else {
    return null;
  }
  return AssessmentAttachment(name: name, path: storedName);
}

/// Opens the local copy with the operating system's registered application.
/// The bundled OpenFile version invokes a macOS command on Windows, so use
/// Explorer there instead.
Future<String?> openAssessmentAttachment(
    AssessmentAttachment attachment, AccountScope scope) async {
  final stored = await resolveAssessmentAttachmentFile(attachment, scope);
  if (stored == null || !await stored.exists()) {
    return 'Die lokale Datei wurde nicht gefunden.';
  }
  if (Platform.isWindows) {
    try {
      await Process.start('explorer.exe', [stored.path]);
      return null;
    } catch (_) {
      return 'Die Datei konnte nicht geöffnet werden.';
    }
  }
  // OpenFile treats internal application-support paths as unrestricted
  // external storage on Android and requests MANAGE_EXTERNAL_STORAGE. Export a
  // disposable copy to our own external cache instead; FileProvider can grant
  // the reader access to that path without any storage permission.
  final path = Platform.isAndroid
      ? await _copyToExternalCacheForOpening(attachment, stored)
      : stored.path;
  if (path == null) {
    return 'Die Datei konnte nicht für das Öffnen vorbereitet werden.';
  }
  final result = await OpenFile.open(path);
  return result.type == ResultType.done
      ? null
      : 'Die Datei konnte nicht geöffnet werden: ${result.message}';
}

Future<String?> _copyToExternalCacheForOpening(
    AssessmentAttachment attachment, File stored) async {
  try {
    final directories = await getExternalCacheDirectories();
    if (directories == null || directories.isEmpty) return null;
    final folder = Directory(
        '${directories.first.path}${Platform.pathSeparator}assessment_open');
    await folder.create(recursive: true);
    final safeName = attachment.name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    final destination = File(
        '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
    await stored.copy(destination.path);
    return destination.path;
  } catch (_) {
    return null;
  }
}

Future<void> removeAssessmentAttachment(
    AssessmentAttachment attachment, AccountScope scope) async {
  final file = await resolveAssessmentAttachmentFile(attachment, scope);
  if (file != null && await file.exists()) await file.delete();
}

/// Deletes every attachment of [scope] with its folder. Files that older
/// versions kept loose in the shared folder are not touched.
Future<void> deleteAssessmentAttachmentFolder(AccountScope scope) async {
  try {
    final folder = await assessmentAttachmentFolder(scope);
    // A link planted in place of the folder is removed, never followed.
    if (await FileSystemEntity.isLink(folder.path)) {
      await Link(folder.path).delete();
    } else if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
  } catch (_) {
    privacyLog('technical_operation');
  }
}
