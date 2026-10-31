import 'dart:convert';
import 'dart:ffi';

import 'package:biometric_storage/src/biometric_storage_win32.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeCredentialBlobAndFree', () {
    test('decodes the owned copy, not the native memory after it was freed',
        () {
      final bytes = utf8.encode('Pässword-€-secret');
      final blob = calloc<Uint8>(bytes.length);
      blob.asTypedList(bytes.length).setAll(0, bytes);
      var freed = 0;
      try {
        final result = decodeCredentialBlobAndFree(blob, bytes.length, () {
          freed++;
          // Simulate the allocator reusing the released buffer: everything
          // that still views this memory afterwards sees invalid UTF-8.
          blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0xFF);
        });
        expect(result, 'Pässword-€-secret');
        expect(freed, 1);
      } finally {
        calloc.free(blob);
      }
    });

    test('decodes an empty blob', () {
      final blob = calloc<Uint8>(1);
      try {
        expect(decodeCredentialBlobAndFree(blob, 0, () {}), '');
      } finally {
        calloc.free(blob);
      }
    });

    test('still frees the native buffer when decoding fails', () {
      final blob = calloc<Uint8>(2);
      blob.asTypedList(2).setAll(0, [0xFF, 0xFE]);
      var freed = 0;
      try {
        expect(
          () => decodeCredentialBlobAndFree(blob, 2, () => freed++),
          throwsFormatException,
        );
        expect(freed, 1);
      } finally {
        calloc.free(blob);
      }
    });
  });
}
