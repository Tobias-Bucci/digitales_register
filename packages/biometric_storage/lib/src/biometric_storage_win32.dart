import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:win32/win32.dart';

import './biometric_storage.dart';

final _logger = Logger('biometric_storage_win32');

/// Copies [size] bytes from the native [blob] into Dart-owned memory, then
/// calls [free] to release the native buffer, and only then decodes the copy.
///
/// `asTypedList` only creates a view onto native memory, so decoding it after
/// the buffer was freed (CredFree) would read released memory.
@visibleForTesting
String decodeCredentialBlobAndFree(
  Pointer<Uint8> blob,
  int size,
  void Function() free,
) {
  final Uint8List copy;
  try {
    copy = Uint8List.fromList(blob.asTypedList(size));
  } catch (_) {
    free();
    rethrow;
  }
  free();
  return utf8.decode(copy);
}

class Win32BiometricStoragePlugin extends BiometricStorage {
  Win32BiometricStoragePlugin() : super.create();

  static const namePrefix = 'design.codeux.authpass.';

  /// Registers this class as the default instance of [PathProviderPlatform]
  static void registerWith() {
    BiometricStorage.instance = Win32BiometricStoragePlugin();
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate() async {
    return CanAuthenticateResponse.errorHwUnavailable;
  }

  @override
  Future<BiometricStorageFile> getStorage(
    String name, {
    StorageFileInitOptions? options,
    bool forceInit = false,
    PromptInfo promptInfo = PromptInfo.defaultValues,
  }) async {
    return BiometricStorageFile(this, namePrefix + name, promptInfo);
  }

  @override
  Future<bool> linuxCheckAppArmorError() async => false;

  @override
  Future<bool> delete(
    String name,
    PromptInfo promptInfo,
  ) async {
    final namePointer = TEXT(name);
    try {
      final result = CredDelete(namePointer, CRED_TYPE_GENERIC, 0);
      if (result != TRUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error ($result): $errorCode');
        }
        return false;
      }
    } finally {
      calloc.free(namePointer);
    }
    return true;
  }

  @override
  Future<String?> read(
    String name,
    PromptInfo promptInfo,
  ) async {
    _logger.finer('read($name)');
    final credPointer = calloc<Pointer<CREDENTIAL>>();
    final namePointer = TEXT(name);
    try {
      if (CredRead(namePointer, CRED_TYPE_GENERIC, 0, credPointer) != TRUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_NOT_FOUND) {
          _logger.fine('Unable to find credential of name $name');
        } else {
          _logger.warning('Error: $errorCode ',
              WindowsException(HRESULT_FROM_WIN32(errorCode)));
        }
        return null;
      }
      final cred = credPointer.value.ref;
      return decodeCredentialBlobAndFree(
        cred.CredentialBlob,
        cred.CredentialBlobSize,
        () {
          _logger.fine('CredFree()');
          CredFree(credPointer.value);
        },
      );
    } finally {
      _logger.fine('free(credPointer)');
      calloc.free(credPointer);
      _logger.fine('free(namePointer)');
      calloc.free(namePointer);
      _logger.fine('read($name) done.');
    }
  }

  @override
  Future<void> write(
    String name,
    String content,
    PromptInfo promptInfo,
  ) async {
    _logger.fine('write()');
    final examplePassword = utf8.encode(content);
    final blob = examplePassword.allocatePointer();
    final namePointer = TEXT(name);
    final userNamePointer = TEXT('flutter.biometric_storage');

    final credential = calloc<CREDENTIAL>()
      ..ref.Type = CRED_TYPE_GENERIC
      ..ref.TargetName = namePointer
      ..ref.Persist = CRED_PERSIST_LOCAL_MACHINE
      ..ref.UserName = userNamePointer
      ..ref.CredentialBlob = blob
      ..ref.CredentialBlobSize = examplePassword.length;
    try {
      final result = CredWrite(credential, 0);
      if (result != TRUE) {
        final errorCode = GetLastError();
        throw BiometricStorageException(
            'Error writing credential $name ($result): $errorCode');
      }
    } finally {
      _logger.fine('free');
      calloc.free(blob);
      calloc.free(credential);
      calloc.free(namePointer);
      calloc.free(userNamePointer);
      _logger.fine('free done');
    }
  }
}
