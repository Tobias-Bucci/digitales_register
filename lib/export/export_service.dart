// Copyright (C) 2026 Tobias Bucci
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:archive/archive.dart';
import 'package:dr/export/export_csv.dart';
import 'package:dr/export/export_data.dart';
import 'package:dr/export/export_pdf.dart';
import 'package:dr/i18n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ExportFile {
  const ExportFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  String get extension => name.split('.').last;
}

class ExportEmptyException implements Exception {}

class ExportTooLargeException implements Exception {}

typedef ExportSaveDialog = Future<String?> Function(
    ExportFile file, String title);

/// Dart keeps the export in memory. The existing file_picker writes bytes
/// through native save dialogs without broad filesystem permissions. Its iOS
/// staging copy is removed by the bundled native implementation.
class ExportService {
  const ExportService({this.saveDialog = _nativeSave});
  final ExportSaveDialog saveDialog;

  Future<ExportFile> create(
      {required List<ExportSection> sections,
      required ExportFormat format,
      required AppLocalizations l10n,
      required String scope,
      DateTime? created,
      int? schoolYear}) async {
    if (sections.isEmpty || sections.every((s) => s.records.isEmpty)) {
      throw ExportEmptyException();
    }
    final count = sections.fold<int>(0, (sum, s) => sum + s.records.length);
    final chars = sections.expand((s) => s.records).fold<int>(
        0,
        (sum, r) =>
            sum +
            r.body.length +
            r.title.length +
            r.fields.values.fold<int>(0, (s, v) => s + v.length) +
            r.tables
                .expand((t) => t)
                .expand((r) => r)
                .fold<int>(0, (s, v) => s + v.length));
    if (count > 20000 || chars > 10000000) throw ExportTooLargeException();
    final timestamp = created ?? DateTime.now();
    final label =
        sections.length == 1 ? sections.single.category.name : 'export';
    final stem =
        'Digitales_Register_${label}_${schoolYear == null ? '' : '$schoolYear-${schoolYear + 1}_'}${DateFormat('yyyyMMdd_HHmmss_SSS').format(timestamp)}';
    if (format == ExportFormat.pdf) {
      final regular =
          await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      final emoji = await rootBundle.load('assets/fonts/NotoEmoji.ttf');
      final bytes = await compute(
          createExportPdf,
          ExportPdfRequest(sections.where((s) => s.records.isNotEmpty).toList(),
              l10n, timestamp, scope, regular, bold, emoji));
      return ExportFile('$stem.pdf', bytes);
    }
    return compute(_csvFiles, (sections, l10n, stem));
  }

  Future<bool> save(ExportFile file, String title) async =>
      await saveDialog(file, title) != null;

  static Future<String?> _nativeSave(ExportFile file, String title) =>
      FilePicker.saveFile(
          dialogTitle: title,
          fileName: file.name,
          type: FileType.custom,
          allowedExtensions: [file.extension],
          bytes: file.bytes,
          lockParentWindow: true);
}

ExportFile _csvFiles((List<ExportSection>, AppLocalizations, String) request) {
  final (sections, l10n, stem) = request;
  if (sections.length == 1) {
    return ExportFile('$stem.csv', createExportCsv(sections.single, l10n));
  }
  final archive = Archive();
  for (final section in sections) {
    archive.addFile(ArchiveFile.bytes(
        '${section.category.name}.csv', createExportCsv(section, l10n)));
  }
  return ExportFile(
      '$stem.zip', Uint8List.fromList(ZipEncoder().encode(archive)));
}
