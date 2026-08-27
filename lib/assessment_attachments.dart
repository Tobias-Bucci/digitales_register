import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// Metadata only; file payloads remain in the app's private local storage.
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

Future<AssessmentAttachment?> pickAndStoreAssessmentAttachment() async {
  final result = await FilePicker.pickFiles();
  if (result == null || result.files.isEmpty) return null;
  final selected = result.files.single;
  final name = selected.name.trim();
  if (name.isEmpty) return null;
  final root = await getApplicationSupportDirectory();
  final folder =
      Directory('${root.path}${Platform.pathSeparator}assessment_attachments');
  await folder.create(recursive: true);
  final safeName = name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  final destination = File(
      '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
  final bytes = selected.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    await destination.writeAsBytes(bytes, flush: true);
  } else if (selected.path != null && selected.path!.isNotEmpty) {
    await File(selected.path!).copy(destination.path);
  } else {
    return null;
  }
  return AssessmentAttachment(name: name, path: destination.path);
}

/// Opens the local copy with the operating system's registered application.
/// The bundled OpenFile version invokes a macOS command on Windows, so use
/// Explorer there instead.
Future<String?> openAssessmentAttachment(
    AssessmentAttachment attachment) async {
  if (!await File(attachment.path).exists()) {
    return 'Die lokale Datei wurde nicht gefunden.';
  }
  if (Platform.isWindows) {
    try {
      await Process.start('explorer.exe', [attachment.path]);
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
      ? await _copyToExternalCacheForOpening(attachment)
      : attachment.path;
  if (path == null) {
    return 'Die Datei konnte nicht für das Öffnen vorbereitet werden.';
  }
  final result = await OpenFile.open(path);
  return result.type == ResultType.done
      ? null
      : 'Die Datei konnte nicht geöffnet werden: ${result.message}';
}

Future<String?> _copyToExternalCacheForOpening(
    AssessmentAttachment attachment) async {
  try {
    final directories = await getExternalCacheDirectories();
    if (directories == null || directories.isEmpty) return null;
    final folder = Directory(
        '${directories.first.path}${Platform.pathSeparator}assessment_open');
    await folder.create(recursive: true);
    final safeName = attachment.name.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    final destination = File(
        '${folder.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
    await File(attachment.path).copy(destination.path);
    return destination.path;
  } catch (_) {
    return null;
  }
}

Future<void> removeAssessmentAttachment(AssessmentAttachment attachment) async {
  final file = File(attachment.path);
  if (await file.exists()) await file.delete();
}
