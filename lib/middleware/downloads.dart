// Copyright (C) 2021 Michael Debertol
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

part of 'middleware.dart';

// Downloading, validating, saving and opening files of the school
// server in the folder of the signed-in account.

Future<String>? _attachmentDownloadDirectoryFuture;
final Map<String, Future<Uint8List>> _authenticatedBytesInFlight =
    <String, Future<Uint8List>>{};

Future<String> _getAttachmentDownloadDirectory() {
  final override = attachmentDownloadDirectoryOverride;
  if (override != null) return override();
  final cached = _attachmentDownloadDirectoryFuture;
  if (cached != null) {
    return cached;
  }

  // TODO: this remains to be tested on all platforms
  final future = () async {
    try {
      return (await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      ))!
          .first
          .path;
    } catch (_) {
      privacyLog('technical_operation');
      return (await getApplicationDocumentsDirectory()).path;
    }
  }();
  _attachmentDownloadDirectoryFuture = future;
  return future;
}

/// The folder of one account inside the attachment download directory. Files
/// of other accounts, and files saved before accounts had folders, are not in
/// it and so are never found, opened or replaced for this account.
Future<String> _accountDownloadFolder(AccountScope scope) async =>
    '${await _getAttachmentDownloadDirectory()}/${scope.fileId}';

/// Resolves [fileName] inside the download folder of [scope].
///
/// Attachment names are derived from backend metadata, so anything that is
/// not a single plain file name, or that is a link which could redirect the
/// access elsewhere, is rejected with `null` instead of being allowed to
/// leave the folder.
Future<File?> _attachmentFile(String fileName, AccountScope scope) async {
  if (!isSafeFileNameSegment(fileName)) {
    return null;
  }
  final folder = await _accountDownloadFolder(scope);
  final file = File('$folder/$fileName');
  if (await FileSystemEntity.isLink(folder) ||
      await FileSystemEntity.isLink(file.path)) {
    return null;
  }
  return file;
}

/// Deletes the download folder of [scope] with everything in it.
Future<void> _deleteAccountDownloads(AccountScope scope) async {
  try {
    final folder = await _accountDownloadFolder(scope);
    // A link planted in place of the folder is removed, never followed.
    if (await FileSystemEntity.isLink(folder)) {
      await Link(folder).delete();
    } else if (await Directory(folder).exists()) {
      await Directory(folder).delete(recursive: true);
    }
  } catch (_) {
    privacyLog('technical_operation');
  }
}

/// Downloads a file.
///
/// Returns true on success and false on a failure. The file is only written
/// once the authenticated response has been validated, so an expired session
/// never leaves a login page behind as a supposedly downloaded document.
Future<bool> downloadFile(
  String url,
  String fileName,
  Map<String, dynamic> parameters,
) async {
  // The request goes out on the session that asked, and a document is only
  // saved while the app is still in that session.
  final session = _Session.capture();
  final loggedIn = await session.wrapper.ensureLoggedIn();
  session.ensureCurrent();
  if (!loggedIn) {
    privacyLog('technical_operation');
    return false;
  }

  // The browser has no app folder: the web app hands the document to the
  // browser's downloads instead of saving it (see browser_download.dart).
  final saveFile =
      kIsWeb ? null : await _attachmentFile(fileName, session.scope);
  if (saveFile == null && !kIsWeb) {
    privacyLog('technical_operation');
    return false;
  }
  if (saveFile != null && await saveFile.exists()) {
    final shouldOverwrite = await askShouldOverwriteFile(fileName);
    session.ensureCurrent();
    if (shouldOverwrite == null) {
      return false;
    } else if (!shouldOverwrite) {
      return true;
    }
  }

  // Mirrors Wrapper.send: one background relogin, then one forced relogin.
  const maxLoginRetries = 2;
  for (var attempt = 0; attempt <= maxLoginRetries; attempt++) {
    if (attempt > 0) {
      final relogin = await session.wrapper.ensureLoggedIn(
        isRetryAfterUnexpectedLogout: true,
        forceRelogin: attempt > 1,
      );
      session.ensureCurrent();
      if (!relogin) {
        privacyLog('technical_operation');
        return false;
      }
    }
    final List<int> bytes;
    final String contentType;
    try {
      final result = await session.wrapper.dio.get<List<int>>(
        url,
        queryParameters: parameters,
        options: dio.Options(responseType: dio.ResponseType.bytes),
      );
      session.ensureCurrent();
      if (result.statusCode != 200) {
        privacyLog('technical_operation');
        return false;
      }
      bytes = result.data ?? const <int>[];
      contentType = result.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    } on StaleSessionException {
      rethrow;
    } catch (_) {
      // A request that failed because the session was retired is no failure.
      session.ensureCurrent();
      privacyLog('technical_operation');
      return false;
    }

    switch (validateDownloadedDocument(bytes, contentType, fileName)) {
      case DownloadValidation.valid:
        if (saveFile == null) return saveInBrowser(fileName, bytes);
        try {
          await _writeFileAtomically(saveFile, bytes);
          return true;
        } catch (_) {
          privacyLog('technical_operation');
          return false;
        }
      case DownloadValidation.loginPage:
        privacyLog('technical_operation');
        continue;
      case DownloadValidation.invalid:
        privacyLog('technical_operation');
        return false;
    }
  }
  return false;
}

enum DownloadValidation { valid, loginPage, invalid }

/// Checks that an HTTP 200 download body is the requested document and not
/// the login page or an error response.
///
/// HTML and JSON bodies are only accepted when [fileName] asks for such a
/// document, so legitimate `.html`/`.json` attachments keep working.
@visibleForTesting
DownloadValidation validateDownloadedDocument(
  List<int> bytes,
  String contentType,
  String fileName,
) {
  if (bytes.isEmpty) {
    return DownloadValidation.invalid;
  }
  final prefix = utf8
      .decode(bytes.take(64 * 1024).toList(), allowMalformed: true)
      .replaceFirst('﻿', '')
      .trimLeft();
  final looksLikeMarkup = prefix.startsWith('<');
  if (looksLikeMarkup && Wrapper.isLoginPage(prefix)) {
    return DownloadValidation.loginPage;
  }
  final extension = fileName.contains('.')
      ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
      : '';
  final normalizedContentType = contentType.toLowerCase();
  if (looksLikeMarkup &&
      normalizedContentType.contains('text/html') &&
      !const {'htm', 'html', 'xhtml', 'xml', 'svg'}.contains(extension)) {
    return DownloadValidation.invalid;
  }
  if ((prefix.startsWith('{') || prefix.startsWith('[')) &&
      normalizedContentType.contains('application/json') &&
      extension != 'json') {
    return DownloadValidation.invalid;
  }
  return DownloadValidation.valid;
}

/// Writes [bytes] to a sibling temporary file and moves it into place, so a
/// failed write never replaces or leaves behind a partial [file].
Future<void> _writeFileAtomically(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final partial = File('${file.path}.part');
  if (await FileSystemEntity.isLink(partial.path)) {
    throw FileSystemException('Refusing to write through a link', partial.path);
  }
  try {
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
  } catch (_) {
    if (await partial.exists()) {
      await partial.delete();
    }
    rethrow;
  }
}

/// The server had no usable answer, or there was no session to ask it with.
class AuthenticatedBytesUnavailable implements Exception {
  const AuthenticatedBytesUnavailable();
}

/// Throws [AuthenticatedBytesUnavailable] unless the answer really is the file:
/// an expired session answers with status 200 and the login page.
Future<Uint8List> fetchAuthenticatedBytes(String url) async {
  final session = _Session.capture();
  // One request per session: another account must not share this answer.
  final key = '${session.generation}|$url';
  final existing = _authenticatedBytesInFlight[key];
  if (existing != null) {
    return existing;
  }
  final request = () async {
    // Mirrors Wrapper.send: a login page is worth one more login.
    for (var attempt = 0; attempt < 2; attempt++) {
      final loggedIn = await session.wrapper.ensureLoggedIn(
        isRetryAfterUnexpectedLogout: attempt > 0,
      );
      session.ensureCurrent();
      if (!loggedIn) break;
      final response = await session.wrapper.dio.get<List<int>>(
        url,
        options: dio.Options(responseType: dio.ResponseType.bytes),
      );
      // Bytes fetched for an account the app has left are not for the next one.
      session.ensureCurrent();
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      final contentType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      switch (validateDownloadedDocument(bytes, contentType, '')) {
        case DownloadValidation.valid:
          return bytes;
        case DownloadValidation.loginPage:
          continue;
        case DownloadValidation.invalid:
          throw const AuthenticatedBytesUnavailable();
      }
    }
    throw const AuthenticatedBytesUnavailable();
  }();
  _authenticatedBytesInFlight[key] = request;
  try {
    return await request;
  } finally {
    if (identical(_authenticatedBytesInFlight[key], request)) {
      final removed = _authenticatedBytesInFlight.remove(key);
      assert(identical(removed, request));
    }
  }
}

/// [url] on a school server as the current session must request it: through
/// the school proxy in the web build. Unchanged in native builds.
String schoolTransportUrl(String url) => wrapper.transportUrl(url);

/// Whether the account signed in now has [fileName] saved.
Future<bool> canOpenFile(String fileName) =>
    _canOpenFileIn(_Session.capture(), fileName);

Future<bool> _canOpenFileIn(_Session session, String fileName) async {
  // Web: nothing is kept; every open downloads the document again.
  if (kIsWeb) return false;
  return await (await _attachmentFile(fileName, session.scope))?.exists() ??
      false;
}

/// Opens a downloaded attachment and tells the user when that fails.
Future<void> openFile(String fileName) async {
  // Web: downloadFile has already handed the document to the browser.
  if (kIsWeb) return;
  privacyLog('technical_operation');
  final file = await _attachmentFile(fileName, _Session.capture().scope);
  if (file == null || !await _openDownloadedFile(file)) {
    showSnackBar(tr('courseMaterials.openFailed'));
  }
}

/// Opens [file] with the platform's viewer. Only [ResultType.done] counts as
/// success; no app, a denied permission, an error code or an exception from
/// the plugin all report failure.
Future<bool> _openDownloadedFile(File file) async {
  try {
    final result =
        await (downloadedFileOpenerOverride ?? OpenFile.open)(file.path);
    return result.type == ResultType.done;
  } catch (_) {
    return false;
  }
}

Future<bool?> askShouldOverwriteFile(String fileName) {
  return navigatorKey!.currentState!.push<bool>(
    DialogRoute(
      builder: (context) {
        return InfoDialog(
          title: Text(tr('files.overwrite.title')),
          content: Text(
            tr('files.overwrite.body', args: {'fileName': fileName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('files.overwrite.keep')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('files.overwrite.redownload')),
            ),
          ],
        );
      },
      context: navigatorKey!.currentContext!,
    ),
  );
}
